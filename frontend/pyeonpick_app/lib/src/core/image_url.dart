import 'package:flutter/foundation.dart';

String displayImageUrl(String value, {Uri? base, bool isWeb = kIsWeb}) {
  final raw = value.trim();
  if (!isWeb ||
      raw.isEmpty ||
      raw.startsWith('data:') ||
      raw.startsWith('blob:')) {
    return raw;
  }
  final origin = base ?? Uri.base;
  final uri = origin.resolve(raw);
  if (uri.scheme != 'http' && uri.scheme != 'https') return raw;
  if (uri.origin == origin.origin) {
    if (uri.path != '/api/image-proxy') return raw;
    return uri
        .replace(
          queryParameters: {...uri.queryParameters, 'format': 'flutter-v1'},
        )
        .toString();
  }
  // Version the URL so cached AVIF responses are not reused after deployment.
  return origin
      .resolve('/api/image-proxy')
      .replace(queryParameters: {'url': uri.toString(), 'format': 'flutter-v1'})
      .toString();
}
