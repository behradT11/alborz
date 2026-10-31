// Service Worker — کارکرد آفلاین. با هر انتشار نسخه را بالا ببرید (یا node scripts/build-sw.mjs را اجرا کنید).
const VERSION = 'og-89d8baa5c8';
const ASSETS = [
  "app.html",
  "assets/icons/apple-touch-icon.png",
  "assets/icons/icon-192.png",
  "assets/icons/icon-512.png",
  "assets/icons/icon.svg",
  "assets/icons/maskable-512.png",
  "css/app.css",
  "css/fonts.css",
  "css/landing.css",
  "index.html",
  "js/app.bundle.js",
  "js/boot-check.js",
  "js/config.js",
  "js/theme.js",
  "manifest.webmanifest",
  "privacy.html",
  "terms.html",
  "vendor/supabase.js"
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(ASSETS.map((a) => './' + a))).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});
// فقط درخواست‌های هم‌مبدأ GET کش می‌شوند؛ درخواست‌های Supabase هرگز کش نمی‌شوند.
self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;
  // config.js همیشه از شبکه (تا تغییر کلیدها فوراً اعمال شود)
  if (url.pathname.endsWith('/js/config.js')) {
    e.respondWith(fetch(req).then((res) => { if (res.ok) { const copy = res.clone(); caches.open(VERSION).then((c) => c.put(req, copy)); } return res; }).catch(() => caches.match(req)));
    return;
  }
  // صفحه‌ها: اول شبکه (برای گرفتن نسخهٔ تازه)، در صورت قطعی از کش
  if (req.mode === 'navigate') {
    e.respondWith(fetch(req).then((res) => { const copy = res.clone(); caches.open(VERSION).then((c) => c.put(req, copy)); return res; })
      .catch(() => caches.match(req, { ignoreSearch: true }).then((r) => r || caches.match('./app.html'))));
    return;
  }
  // دارایی‌ها: کش، و به‌روزرسانی در پس‌زمینه
  e.respondWith(caches.match(req).then((cached) => {
    const net = fetch(req).then((res) => { if (res.ok) { const copy = res.clone(); caches.open(VERSION).then((c) => c.put(req, copy)); } return res; }).catch(() => cached);
    return cached || net;
  }));
});
