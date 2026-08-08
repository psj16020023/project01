import 'package:flutter_test/flutter_test.dart';
import 'package:pyeonpick_app/src/core/app_environment.dart';

void main() {
  test('uses the remote API when DATA_MODE is omitted', () {
    final environment = AppEnvironment.fromDefines();

    expect(environment.dataMode, DataMode.remote);
    expect(environment.apiBaseUrl, isNotEmpty);
  });
}
