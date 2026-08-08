import 'account_string_store.dart';
import 'browser_account_string_store_stub.dart'
    if (dart.library.html) 'browser_account_string_store_web.dart';

Future<AccountStringStore?> createBrowserAccountStringStore() {
  return createPlatformBrowserAccountStringStore();
}
