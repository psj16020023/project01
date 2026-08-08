import 'package:web/web.dart' as web;

import 'account_string_store.dart';

class BrowserAccountStringStore implements AccountStringStore {
  const BrowserAccountStringStore();

  @override
  String? getString(String key) {
    return web.window.localStorage.getItem(key);
  }

  @override
  Future<bool> setString(String key, String value) async {
    web.window.localStorage.setItem(key, value);
    return web.window.localStorage.getItem(key) == value;
  }

  @override
  Future<bool> remove(String key) async {
    web.window.localStorage.removeItem(key);
    return true;
  }
}

Future<AccountStringStore?> createPlatformBrowserAccountStringStore() async {
  try {
    const probeKey = 'pyeonpick_account_storage_probe';
    web.window.localStorage.setItem(probeKey, 'ok');
    final available = web.window.localStorage.getItem(probeKey) == 'ok';
    web.window.localStorage.removeItem(probeKey);
    return available ? const BrowserAccountStringStore() : null;
  } catch (_) {
    return null;
  }
}
