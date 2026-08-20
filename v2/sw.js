/* Service worker: cachea la app para que funcione sin internet. */
const CACHE = 'diario-gym-v2-011';
const FILES = ['./', './index.html', './manifest.json', './icon-180.png', './icon-192.png', './icon-512.png', './icon-512-maskable.png', './hero.jpg'];

self.addEventListener('install', e => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(FILES)).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

/* El HTML y el JS de la app se piden SIEMPRE frescos.
   GitHub Pages los manda con max-age=600, así que sin {cache:'reload'} el navegador
   devolvía su propia copia vieja y el service worker la guardaba como si fuera nueva:
   por eso un cambio recién publicado podía tardar en aparecer en el teléfono. */
const esCodigo = url => url.pathname.endsWith('/') ||
                        url.pathname.endsWith('.html') ||
                        url.pathname.endsWith('.js');

self.addEventListener('fetch', e => {
  if (e.request.method !== 'GET') return;
  const url = new URL(e.request.url);
  const fresco = url.origin === self.location.origin && esCodigo(url);
  /* Ojo: no se puede hacer new Request(req, init) si req es de navegación,
     así que en ese caso se pide la URL directamente. */
  const peticion = fresco
    ? fetch(url.href, { cache: 'reload', credentials: 'same-origin' })
    : fetch(e.request);

  e.respondWith(
    peticion
      .then(r => {
        const copy = r.clone();
        caches.open(CACHE).then(c => c.put(e.request, copy)).catch(() => {});
        return r;
      })
      .catch(() => caches.match(e.request).then(r => r || caches.match('./index.html')))
  );
});
