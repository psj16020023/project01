import 'package:flutter/foundation.dart';

enum DataMode { mock, remote }

class AppEnvironment {
  const AppEnvironment({
    required this.dataMode,
    required this.apiBaseUrl,
    required this.mapTilerApiKey,
    required this.mapTilerMapId,
  });

  factory AppEnvironment.fromDefines() {
    const mode = String.fromEnvironment('DATA_MODE', defaultValue: 'remote');
    const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    const mapTilerApiKey = String.fromEnvironment(
      'MAPTILER_API_KEY',
      defaultValue: '',
    );
    const mapTilerMapId = String.fromEnvironment(
      'MAPTILER_MAP_ID',
      defaultValue: 'streets-v2',
    );
    return AppEnvironment(
      dataMode: mode == 'remote' ? DataMode.remote : DataMode.mock,
      apiBaseUrl: apiBaseUrl.isEmpty ? _defaultApiBaseUrl() : apiBaseUrl,
      mapTilerApiKey: mapTilerApiKey,
      mapTilerMapId: mapTilerMapId,
    );
  }

  final DataMode dataMode;
  final String apiBaseUrl;
  final String mapTilerApiKey;
  final String mapTilerMapId;

  bool get hasMapTiler => mapTilerApiKey.trim().isNotEmpty;

  static String _defaultApiBaseUrl() {
    if (kIsWeb) {
      return '${Uri.base.origin}/api';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'http://10.0.2.2:4173/api';
      case TargetPlatform.iOS:
        return 'http://127.0.0.1:4173/api';
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
        return 'http://127.0.0.1:4173/api';
      case TargetPlatform.fuchsia:
        return 'http://127.0.0.1:4173/api';
    }
  }
}
