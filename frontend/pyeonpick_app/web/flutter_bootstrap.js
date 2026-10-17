{{flutter_js}}
{{flutter_build_config}}

(async () => {
  // mobile_scanner only passes the requested camera direction on web. Apply
  // quality preferences before getUserMedia creates the stream so Safari and
  // Chromium do not settle on a low-resolution preview that is hard to decode.
  if (navigator.mediaDevices?.getUserMedia) {
    try {
      const getUserMedia = navigator.mediaDevices.getUserMedia.bind(
        navigator.mediaDevices,
      );
      navigator.mediaDevices.getUserMedia = (constraints = {}) => {
        const requestedVideo = constraints.video;
        if (!requestedVideo) return getUserMedia(constraints);

        const video =
          requestedVideo === true || typeof requestedVideo !== "object"
            ? {}
            : requestedVideo;
        return getUserMedia({
          ...constraints,
          video: {
            width: { ideal: 1920 },
            height: { ideal: 1080 },
            aspectRatio: { ideal: 16 / 9 },
            frameRate: { ideal: 30 },
            ...video,
          },
        });
      };
    } catch (_) {
      // Keep booting if a browser does not allow wrapping MediaDevices.
    }
  }

  if ("serviceWorker" in navigator) {
    try {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(
        registrations.map((registration) => registration.unregister()),
      );
    } catch (_) {}
  }

  if ("caches" in window) {
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map((key) => caches.delete(key)));
    } catch (_) {}
  }

  const build = _flutter.buildConfig?.builds?.[0];
  if (build) {
    build.mainJsPath = `main.dart.js?v=${Date.now()}`;
  }

  _flutter.loader.load({
    config: {
      canvasKitBaseUrl: "canvaskit",
    },
  });
})();
