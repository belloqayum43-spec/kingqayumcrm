// Bump this name when changing the precache list or offline behavior.
const CACHE = 'kingqayum-crm-v5';
const PREFIX = 'kingqayum-crm-';
const ASSETS = ['./', './index.html', './styles.css', './manifest.webmanifest', './icon.svg', './js/db.js', './js/core.js', './js/dm-studio.js', './js/app.js'];

self.addEventListener('install', event => {
  // Install only after every shell asset was cached. A partial new cache must
  // never replace a working older worker.
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(ASSETS)));
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    await self.clients.claim();
    const keys = await caches.keys();
    await Promise.all(keys.filter(key => key.startsWith(PREFIX) && key !== CACHE).map(key => caches.delete(key)));
  })());
});

self.addEventListener('fetch', event => {
  const request = event.request;
  if (request.method !== 'GET' || new URL(request.url).origin !== self.location.origin) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    try {
      // Prefer current deployed assets when connected; retain a cached copy for
      // offline use and fall back to the shell for navigation requests.
      const response = await fetch(request);
      if (response.ok) await cache.put(request, response.clone());
      return response;
    } catch {
      const cached = await cache.match(request);
      if (cached) return cached;
      if (request.mode === 'navigate') return (await cache.match('./index.html')) || Response.error();
      return Response.error();
    }
  })());
});
