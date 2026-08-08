import 'package:shared_preferences/shared_preferences.dart';

abstract class AccountStringStore {
  String? getString(String key);

  Future<bool> setString(String key, String value);

  Future<bool> remove(String key);
}

class SharedPreferencesAccountStringStore implements AccountStringStore {
  const SharedPreferencesAccountStringStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  String? getString(String key) => _prefs.getString(key);

  @override
  Future<bool> setString(String key, String value) {
    return _prefs.setString(key, value);
  }

  @override
  Future<bool> remove(String key) => _prefs.remove(key);
}

class MemoryAccountStringStore implements AccountStringStore {
  final Map<String, String> _values = <String, String>{};

  @override
  String? getString(String key) => _values[key];

  @override
  Future<bool> setString(String key, String value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    _values.remove(key);
    return true;
  }
}
