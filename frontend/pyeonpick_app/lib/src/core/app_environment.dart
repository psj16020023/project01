import 'package:flutter/foundation.dart';

enum DataMode { mock, remote }

class AppEnvironment {
  const AppEnvironment({
    required this.dataMode,
    required this.apiBaseUrl,
  });

  factory AppEnvironment.fromDefines() {
    const mode = String.fromEnvironment('DATA_MODE', defaultValue: 'mock');
    const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    return AppEnvironment(
      dataMode: mode == 'remote' ? DataMode.remote : DataMode.mock,
      apiBaseUrl: apiBaseUrl.isEmpty ? _defaultApiBaseUrl() : apiBaseUrl,
    );
  }

  final DataMode dataMode;
  final String apiBaseUrl;

  static String _defaultApiBaseUrl() {
    if (kIsWeb) {
      return '${Uri.base.origin}/api';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:3000/api';
      case TargetPlatform.iOS:
        return 'http://127.0.0.1:3000/api';
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return 'http://127.0.0.1:3000/api';
      case TargetPlatform.fuchsia:
        return 'http://127.0.0.1:3000/api';
    }
  }
}
