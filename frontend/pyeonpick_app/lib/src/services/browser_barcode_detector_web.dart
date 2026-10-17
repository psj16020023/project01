import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

@JS('BarcodeDetector')
extension type _NativeBarcodeDetector._(JSObject _) implements JSObject {
  external factory _NativeBarcodeDetector();

  external JSPromise<JSArray<_DetectedBarcode>> detect(
    web.HTMLVideoElement source,
  );
}

extension type _DetectedBarcode._(JSObject _) implements JSObject {
  external JSString? get rawValue;
}

/// Adds the browser's hardware-optimized BarcodeDetector where available.
/// mobile_scanner's ZXing detector remains active as the cross-browser path.
class BrowserBarcodeDetector {
  BrowserBarcodeDetector();

  final StreamController<String> _barcodes = StreamController.broadcast();
  _NativeBarcodeDetector? _detector;
  Timer? _timer;
  web.HTMLVideoElement? _video;
  bool _detecting = false;
  bool _disposed = false;

  Stream<String> get barcodes => _barcodes.stream;

  Future<void> start() async {
    if (_disposed || _timer != null) return;
    if (!globalContext.has('BarcodeDetector')) return;

    try {
      _detector = _NativeBarcodeDetector();
    } catch (_) {
      return;
    }

    for (var attempt = 0; attempt < 8 && !_disposed; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      _video = _activeCameraVideo();
      if (_video != null) break;
    }
    if (_video == null || _disposed) return;

    _timer = Timer.periodic(const Duration(milliseconds: 180), (_) {
      unawaited(_detect());
    });
    await _detect();
  }

  web.HTMLVideoElement? _activeCameraVideo() {
    final videos = web.document.querySelectorAll('video');
    for (var index = videos.length - 1; index >= 0; index -= 1) {
      final video = videos.item(index) as web.HTMLVideoElement;
      if (video.srcObject != null && video.videoWidth > 0) return video;
    }
    return null;
  }

  Future<void> _detect() async {
    final detector = _detector;
    final video = _video;
    if (_disposed || _detecting || detector == null || video == null) return;
    if (video.paused || video.videoWidth == 0) return;

    _detecting = true;
    try {
      final results = (await detector.detect(video).toDart).toDart;
      for (final result in results) {
        final value = result.rawValue?.toDart.trim();
        if (value != null && value.isNotEmpty && !_barcodes.isClosed) {
          _barcodes.add(value);
        }
      }
    } catch (_) {
      // A frame can be unavailable while the camera changes resolution.
    } finally {
      _detecting = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_barcodes.close());
  }
}
