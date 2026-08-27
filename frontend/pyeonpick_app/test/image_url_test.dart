import 'package:flutter_test/flutter_test.dart';
import 'package:pyeonpick_app/src/core/image_url.dart';

void main() {
  final base = Uri.parse('https://pyeonpick.example/');
  String url(String value) => displayImageUrl(value, base: base, isWeb: true);
  test('external images use the versioned compatible proxy', () {
    final proxy = Uri.parse(url('https://photos.example/a.jpg?width=200'));
    expect(proxy.origin, base.origin);
    expect(
      proxy.queryParameters['url'],
      'https://photos.example/a.jpg?width=200',
    );
    expect(proxy.queryParameters['format'], 'flutter-v1');
  });
  test('local uploads, data URLs and native requests are preserved', () {
    expect(url('/api/posts/123/images/0'), '/api/posts/123/images/0');
    expect(url('data:image/png;base64,AAAA'), 'data:image/png;base64,AAAA');
    expect(
      displayImageUrl('https://photos.example/a.jpg', isWeb: false),
      'https://photos.example/a.jpg',
    );
  });
  test('existing proxy URLs are versioned without proxying the proxy', () {
    final first = url('https://photos.example/a.jpg');
    expect(url(first), first);
    final relative = Uri.parse(
      url('/api/image-proxy?url=https%3A%2F%2Fphotos.example%2Fa.jpg'),
    );
    expect(relative.queryParameters['url'], 'https://photos.example/a.jpg');
    expect(relative.queryParameters['format'], 'flutter-v1');
  });
}
