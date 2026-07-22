/* ServiceTag offline cache
 * Strategy:
 *  - HTML page: network-first (so a fresh deploy shows up the moment you're
 *    online) with a cached fallback (so it still opens with no signal).
 *  - Everything else (fonts, etc.): cache-first, filled in as it's fetched.
 * Bump CACHE when you want to force-clear old cached assets.
 */
const CACHE = "servicetag-shell-v5";
const CORE = ["./", "./index.html", "./manifest.webmanifest", "./icon-192.png", "./icon-512.png", "./apple-touch-icon.png"];

self.addEventListener("install", (e) => {
  e.waitUntil(
    caches.open(CACHE).then((c) => c.addAll(CORE)).then(() => self.skipWaiting())
  );
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET") return;

  // App shell: try network, fall back to the cached page when offline.
  if (req.mode === "navigate") {
    e.respondWith((async () => {
      try {
        const res = await fetch(req);
        const c = await caches.open(CACHE);
        c.put("./index.html", res.clone()).catch(() => {});
        return res;
      } catch (_) {
        return (await caches.match("./index.html")) || Response.error();
      }
    })());
    return;
  }

  // Other assets: serve from cache, otherwise fetch and remember.
  e.respondWith((async () => {
    const cached = await caches.match(req);
    if (cached) return cached;
    try {
      const res = await fetch(req);
      const c = await caches.open(CACHE);
      c.put(req, res.clone()).catch(() => {});
      return res;
    } catch (_) {
      return cached || Response.error();
    }
  })());
});
