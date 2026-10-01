const CACHE_NAME = "jf-seehausen-offline-v2";

const APP_SHELL = [
  "./",
  "./index.html",
  "./flutter_bootstrap.js",
  "./manifest.json",
  "./favicon.png",
  "./jf_alarm.wav",
  "./icons/Icon-192.png",
  "./icons/Icon-512.png",
  "./icons/Icon-maskable-192.png",
  "./icons/Icon-maskable-512.png"
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(async (cache) => {
      for (const url of APP_SHELL) {
        try {
          await cache.add(url);
        } catch (_) {
          // Manche generierten Flutter-Dateien sind erst nach dem Build vorhanden.
          // Sie werden später über den Runtime-Cache gespeichert.
        }
      }
    })
  );

  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches.keys().then((keys) =>
      Promise.all(
        keys
          .filter(
            (key) =>
              key.startsWith("jf-seehausen-offline-") &&
              key !== CACHE_NAME
          )
          .map((key) => caches.delete(key))
      )
    )
  );

  self.clients.claim();
});

self.addEventListener("fetch", (event) => {
  const request = event.request;

  if (request.method !== "GET") return;

  const url = new URL(request.url);

  // Supabase und andere API-Aufrufe niemals durch alte Cache-Antworten ersetzen.
  // Die Flutter-App verwaltet ihre Offline-Daten selbst.
  if (
    url.hostname.endsWith(".supabase.co") ||
    url.pathname.includes("/rest/v1/") ||
    url.pathname.includes("/auth/v1/")
  ) {
    return;
  }

  // Nur Dateien der eigentlichen App cachen.
  // Firebase Messaging verwendet weiterhin seinen eigenen Service Worker.
  if (url.origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    event.respondWith(
      fetch(request)
        .then((response) => {
          // Nur vollständige HTTP-200-Antworten cachen.
          // 206 Partial Content darf nicht mit Cache.put() gespeichert werden.
          if (response.ok && response.status !== 206) {
            const copy = response.clone();

            caches
              .open(CACHE_NAME)
              .then((cache) => cache.put("./index.html", copy))
              .catch(() => {});
          }

          return response;
        })
        .catch(async () => {
          return (
            (await caches.match(request)) ||
            (await caches.match("./index.html")) ||
            (await caches.match("./"))
          );
        })
    );

    return;
  }

  event.respondWith(
    caches.match(request).then((cached) => {
      const network = fetch(request)
        .then((response) => {
          // WICHTIG:
          // HTTP 206 = Partial Content.
          // Solche Antworten unterstützt Cache.put() nicht.
          if (
            response &&
            response.ok &&
            response.status !== 206
          ) {
            const copy = response.clone();

            caches
              .open(CACHE_NAME)
              .then((cache) => cache.put(request, copy))
              .catch(() => {});
          }

          return response;
        })
        .catch(() => cached);

      // Bereits vorhandene Dateien funktionieren weiterhin offline.
      return cached || network;
    })
  );
});
