// Minimal service worker: makes ROUNA OS installable. Always uses the network so staff never see stale data.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", e => e.waitUntil(self.clients.claim()));
self.addEventListener("fetch", () => {});
