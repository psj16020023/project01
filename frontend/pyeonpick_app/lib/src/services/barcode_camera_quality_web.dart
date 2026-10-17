import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

const int _preferredWidth = 1920;
const int _preferredHeight = 1080;

Future<void> optimizePlatformBarcodeCameraForWeb() async {
  // mobile_scanner's web implementation currently requests only the camera
  // direction. Ask the active track for a sharper preview after it starts.
  for (var attempt = 0; attempt < 5; attempt += 1) {
    await Future<void>.delayed(
      Duration(milliseconds: attempt == 0 ? 150 : 300),
    );

    final videoElements = web.document.querySelectorAll('video');
    for (var index = videoElements.length - 1; index >= 0; index -= 1) {
      final video = videoElements.item(index) as web.HTMLVideoElement;
      final source = video.srcObject;
      if (source == null) continue;

      try {
        final stream = source as web.MediaStream;
        final tracks = stream.getVideoTracks().toDart;
        if (tracks.isEmpty) continue;

        await tracks.first
            .applyConstraints(
              web.MediaTrackConstraints(
                width: web.ConstrainULongRange(ideal: _preferredWidth),
                height: web.ConstrainULongRange(ideal: _preferredHeight),
                frameRate: web.ConstrainDoubleRange(ideal: 30),
              ),
            )
            .toDart;
        return;
      } catch (_) {
        // Some browsers expose the stream before the track is ready. Retrying
        // is safe, and unsupported constraints simply keep the default feed.
      }
    }
  }
}
