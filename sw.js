/* Service worker : coque de l'appli disponible hors-ligne, mises à jour prioritaires quand le réseau répond */
const V = "calendrier-v1", SHELL = ["./", "./index.html", "./manifest.webmanifest", "./icon-192.png", "./icon-512.png"];
const CDN = ["cdnjs.cloudflare.com", "cdn.jsdelivr.net"];
self.addEventListener("install", e => { e.waitUntil(caches.open(V).then(c => c.addAll(SHELL)).then(() => self.skipWaiting())); });
self.addEventListener("activate", e => {
  e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== V).map(k => caches.delete(k)))).then(() => self.clients.claim()));
});
const timeout = (p, ms) => Promise.race([p, new Promise((_, ko) => setTimeout(() => ko(new Error("timeout")), ms))]);
self.addEventListener("fetch", e => {
  const r = e.request; if (r.method !== "GET") return;
  const u = new URL(r.url);
  if (u.origin === location.origin) {
    // page et fichiers de l'appli : réseau d'abord (version à jour), cache en secours (hors-ligne / réseau lent)
    e.respondWith(timeout(fetch(r), 5000).then(res => {
      if (res.ok) { const cp = res.clone(); caches.open(V).then(c => c.put(r, cp)); }
      return res;
    }).catch(() => caches.match(r, { ignoreSearch: true }).then(m => m || (r.mode === "navigate" ? caches.match("./index.html") : Response.error()))));
  } else if (CDN.includes(u.hostname)) {
    // bibliothèques (Leaflet, Supabase, xlsx) : cache d'abord, versions figées par l'URL
    e.respondWith(caches.match(r).then(m => m || fetch(r).then(res => {
      if (res.ok) { const cp = res.clone(); caches.open(V).then(c => c.put(r, cp)); }
      return res;
    })));
  }
  // Supabase, tuiles de carte, etc. : pas d'interception
});
