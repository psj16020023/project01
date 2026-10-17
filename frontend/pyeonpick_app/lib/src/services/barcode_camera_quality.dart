import 'barcode_camera_quality_stub.dart'
    if (dart.library.html) 'barcode_camera_quality_web.dart';

Future<void> optimizeBarcodeCameraForWeb() {
  return optimizePlatformBarcodeCameraForWeb();
}
