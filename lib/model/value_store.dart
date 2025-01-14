import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import 'device.dart';

class ValueStore {
  SharedPreferences prefs;

  ValueStore(this.prefs);

  Future<String> getDeviceId() async {
    var deviceId = prefs.getString('deviceId') ?? '';
    if (deviceId.length < 5) {
      deviceId = generateId(28);
      await prefs.setString('deviceId', deviceId);
    }
    return deviceId;
  }

  setDeviceName(String name) {
    return prefs.setString('deviceName', name);
  }

  Future<String> getDeviceName() async {
    var deviceName = prefs.getString('deviceName') ?? '';
    if (deviceName.isEmpty) {
      final deviceInfoPlugin = DeviceInfoPlugin();
      final deviceInfo = await deviceInfoPlugin.deviceInfo;
      var info = deviceInfo.toMap();
      deviceName = info['name'] ?? info['computerName'] ?? '';
      if (deviceName.isEmpty) {
        deviceName = info['manufacturer'] ?? Platform.operatingSystem;
        deviceName = deviceName.capitalize();
      }
      prefs.setString('deviceName', deviceName);
    }
    return deviceName;
  }

  List<Device> getReceivers() {
    var list = prefs.getStringList('receivers') ?? [];
    return list.map((r) => Device.decode(jsonDecode(r))).toList();
  }

  Device? getSelectedDevice() {
    var receivers = getReceivers();
    var selectedDeviceId = prefs.getString('selectedReceivingDeviceId');
    return receivers
        .where((it) => it.id == selectedDeviceId)
        .toList()
        .tryGet(0);
  }

  updateStartValues() {
    var firstSeenAt = prefs.getString('firstSeenAt');
    if (firstSeenAt == null) {
      var date = DateTime.now().toIso8601String();
      prefs.setString('firstSeenAt', date);
    }

    int appOpens = prefs.getInt('appOpenCount') ?? 0;
    appOpens++;
    prefs.setInt('appOpenCount', appOpens);
  }
}
