import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'tools_config.dart';
import 'version_editor.dart';

class AppStoreVersionSubmitter {
  var api = AppStoreConnectApi();

  submit() async {
    var version = VersionEditor().readCurrentVersion().join('.');
    await submitLatestVersionForReview(version, 'IOS');
    await submitLatestVersionForReview(version, 'MAC_OS');
  }

  submitLatestVersionForReview(String appVersion, String platform) async {
    var build = await waitForBuild(appVersion, platform);
    var pendingVersion = await getPendingVersion(platform);

    var versionId = pendingVersion['id'];
    await updateVersion(build, appVersion, versionId, platform);
    await updateAppVersionLocalizations(versionId);
    await submitPlatformVersion(platform, versionId);

    print('Submitted $platform $appVersion');
  }

  Future<Map> waitForBuild(String appVersion, String platform) async {
    var buildVersion = int.parse(appVersion.split('.')[2]);
    var timeoutAt = DateTime.now().add(const Duration(minutes: 10));
    print('Checking build $buildVersion...');
    while (DateTime.now().isBefore(timeoutAt)) {
      var build = await fetchBuild(platform, buildVersion);
      if (build != null) {
        var state = build['attributes']['processingState'];
        if (state == 'VALID') {
          print('Build found and processed');
          return build;
        } else {
          print('Build $buildVersion found, but not yet processed ($state)');
        }
      } else {
        print('No build for version $buildVersion $platform yet');
      }
      await Future.delayed(const Duration(seconds: 5));
    }
    throw Exception('Could not find build. Timeout reached');
  }

  fetchBuild(String platform, int buildVersion) async {
    bool isCorrectPlatform(build) {
      // Hack for checking. Only mac builds seems to have the lsMinimumSystemVersion
      // set to a none null value
      var isIos = build['attributes']['lsMinimumSystemVersion'] == null;
      return platform == 'IOS' ? isIos : !isIos;
    }

    var res = await api.send('GET', '/apps/${Config.appStoreAppId}/builds');
    var allBuilds = List.from(res['data']);
    var builds = allBuilds
        .where((it) => it['attributes']['version'] == '$buildVersion')
        .where((it) => isCorrectPlatform(it));
    return builds.isNotEmpty ? builds.first : null;
  }

  Future<Map> getPendingVersion(String platform) async {
    var appId = Config.appStoreAppId;
    var result = await api.send(
        'GET', '/apps/$appId/appStoreVersions?filter[platform]=$platform');
    var allVersions = List.from(result['data']);
    var pendingVersions = allVersions.where((it) {
      var state = it['attributes']['appStoreState'];
      return ['PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED'].contains(state);
    });

    if (pendingVersions.isNotEmpty) {
      return pendingVersions.first;
    } else {
      return createAppVersion(platform);
    }
  }

  Future<Map> createAppVersion(String platform) async {
    var body = {
      'data': {
        'attributes': {
          'platform': platform,
          'versionString': '1.0.0',
        },
        'relationships': {
          'app': {
            'data': {'id': Config.appStoreAppId, 'type': 'apps'}
          }
        },
        'type': 'appStoreVersions',
      }
    };
    var result = await api.send('POST', '/appStoreVersions', body);
    return result['data'];
  }

  updateVersion(
      Map build, String appVersion, String versionId, String platform) async {
    var body = {
      'data': {
        'id': versionId,
        'type': 'appStoreVersions',
        'attributes': {
          'versionString': appVersion,
        },
        'relationships': {
          'build': {
            'data': {
              'id': build['id'],
              'type': 'builds',
            }
          }
        },
      },
    };
    await api.send('PATCH', '/appStoreVersions/$versionId', body);
  }

  updateAppVersionLocalizations(String versionId) async {
    var localeResult = await api.send(
        'GET', '/appStoreVersions/$versionId/appStoreVersionLocalizations');
    for (var locale in localeResult['data']) {
      var localeId = locale['id'];
      var body = {
        'data': {
          'id': localeId,
          'type': 'appStoreVersionLocalizations',
          'attributes': {
            'whatsNew': 'Improvements and fixes',
          },
        },
      };
      await api.send('PATCH', '/appStoreVersionLocalizations/$localeId', body);
    }
  }

  submitPlatformVersion(String platform, String versionId) async {
    var appId = Config.appStoreAppId;
    var reviewSubmissions =
        await api.send('GET', '/reviewSubmissions?filter[app]=$appId');
    var pendingSubmissions = reviewSubmissions['data']
        .where((it) => it['attributes']['state'] != 'COMPLETE')
        .toList();
    var platformPending = List.from(pendingSubmissions
        .where((it) => it['attributes']['platform'] == platform));

    var submission = platformPending.isNotEmpty ? platformPending.first : null;

    if (submission == null) {
      submission = await createReviewSubmission(platform);
      // Submission takes a few moments to be ready. Seems 1s is fine.
      await Future.delayed(const Duration(seconds: 1));
    }

    var submissionId = submission['id'];
    await createReviewSubmissionItem(platform, versionId, submissionId);

    var body = {
      'data': {
        'id': submissionId,
        'type': 'reviewSubmissions',
        'attributes': {
          'submitted': true,
        },
      }
    };
    await api.send('PATCH', '/reviewSubmissions/$submissionId', body);
  }

  createReviewSubmission(String platform) async {
    var body = {
      'data': {
        'type': 'reviewSubmissions',
        'attributes': {
          'platform': platform,
        },
        'relationships': {
          'app': {
            'data': {
              'id': Config.appStoreAppId,
              'type': 'apps',
            }
          },
        },
      }
    };
    var result = await api.send('POST', '/reviewSubmissions', body);
    return result['data'];
  }

  createReviewSubmissionItem(
      String platform, String versionId, String submissionId) async {
    var body = {
      'data': {
        'type': 'reviewSubmissionItems',
        'relationships': {
          'reviewSubmission': {
            'data': {
              'id': submissionId,
              'type': 'reviewSubmissions',
            }
          },
          'appStoreVersion': {
            'data': {
              'id': versionId,
              'type': 'appStoreVersions',
            }
          },
        },
      }
    };
    var result = await api.send('POST', '/reviewSubmissionItems', body);
    return result;
  }

  Future deleteAllBuilds() async {
    var res =
        await api.send('GET', '/apps/${Config.appStoreAppId}/builds?limit=200');
    var allBuilds = List.from(res['data']);
    var activeBuilds =
        allBuilds.where((it) => it['attributes']['expired'] == false);
    print('Active builds: ${activeBuilds.length}');
    for (var build in activeBuilds) {
      await expireBuild(build['id']);
    }
    print('Done!');
  }

  Future expireBuild(String buildId) {
    return api.send('PATCH', '/builds/$buildId', {
      'data': {
        'id': buildId,
        'type': 'builds',
        'attributes': {
          'expired': true,
        },
      },
    });
  }
}

class AppStoreConnectApi {
  send(String method, String apiPath, [Map? requestBody]) async {
    var basePath = 'https://api.appstoreconnect.apple.com/v1';
    var uri = Uri.parse('$basePath$apiPath');
    print('$method ${uri.host}${uri.path}');

    var req = http.Request(method, uri);
    var token = _generateAppleToken();
    req.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });
    if (requestBody != null) req.body = jsonEncode(requestBody);

    var res = await req.send();
    var body = await res.stream.bytesToString();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      print(body);
      throw Exception('Invalid apple status code ${res.statusCode}');
    }

    return jsonDecode(body);
  }

  _generateAppleToken() {
    int creationTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final jwt = JWT(
      {
        "iss": Config.appStoreConnectIssuerId,
        "iat": creationTime,
        "exp": creationTime + 60 * 20,
        "aud": "appstoreconnect-v1"
      },
      header: {
        "alg": "ES256",
        "kid": Config.appStoreConnectApiKeyName,
        "typ": "JWT"
      },
      issuer: Config.appStoreConnectIssuerId,
    );

    var pem = File(Config.appStoreConnectKeyPath).readAsStringSync();
    var token = jwt.sign(ECPrivateKey(pem), algorithm: JWTAlgorithm.ES256);

    return token;
  }
}
