import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class User {
  String id;

  User(this.id);

  static User create(String id) {
    return User(id);
  }

  static User decode(Map data) {
    String id = data['id'];
    return User(id);
  }

  Map<String, dynamic> encode({bool firebase = false}) {
    return {
      'id': id,
    };
  }
}

class UserState {
  SharedPreferences prefs;

  UserState(this.prefs);

  User? getCurrentUser() {
    var json = prefs.getString('currentUser');
    if (json != null) {
      var data = jsonDecode(json);
      var user = User.decode(data);
      return user;
    } else {
      return null;
    }
  }

  saveUser(User currentUser) async {
    var json = jsonEncode(currentUser.encode());
    prefs.setString('currentUser', json);
  }
}
