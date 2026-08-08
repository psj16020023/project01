{{flutter_js}}
{{flutter_build_config}}

(async () => {
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
