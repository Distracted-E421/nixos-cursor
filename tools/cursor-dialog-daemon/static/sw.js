// Service Worker for Cursor Dialog PWA

const CACHE_NAME = 'cursor-dialog-v2';
const STATIC_ASSETS = [
  '/',
  '/manifest.json',
];

// Install event - cache static assets
self.addEventListener('install', (event) => {
  console.log('[SW] Install');
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll(STATIC_ASSETS);
    })
  );
  self.skipWaiting();
});

// Listen for messages from main thread to show notifications
self.addEventListener('message', (event) => {
  console.log('[SW] Message received:', event.data);
  
  if (event.data && event.data.type === 'SHOW_NOTIFICATION') {
    const { title, body, tag } = event.data;
    
    self.registration.showNotification(title, {
      body: body || 'New dialog waiting',
      icon: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect fill="%236366f1" width="100" height="100" rx="20"/><text x="50" y="70" font-size="50" text-anchor="middle" fill="white">💬</text></svg>',
      badge: 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 100"><rect fill="%236366f1" width="100" height="100" rx="20"/></svg>',
      vibrate: [200, 100, 200],
      tag: tag || 'cursor-dialog',
      renotify: true,
      requireInteraction: true,
      actions: [
        { action: 'open', title: 'Open' },
        { action: 'dismiss', title: 'Dismiss' },
      ],
    }).then(() => {
      console.log('[SW] Notification shown');
    }).catch(err => {
      console.error('[SW] Notification error:', err);
    });
  }
});

// Activate event - clean old caches
self.addEventListener('activate', (event) => {
  console.log('[SW] Activate');
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys
          .filter((key) => key !== CACHE_NAME)
          .map((key) => caches.delete(key))
      );
    })
  );
  self.clients.claim();
});

// Fetch event - serve from cache, fallback to network
self.addEventListener('fetch', (event) => {
  // Only cache GET requests
  if (event.request.method !== 'GET') return;

  // Don't cache API or WebSocket requests
  const url = new URL(event.request.url);
  if (url.pathname.startsWith('/api') || url.pathname === '/ws') {
    return;
  }

  event.respondWith(
    caches.match(event.request).then((cached) => {
      // Return cached version, but also update cache
      const fetched = fetch(event.request).then((response) => {
        if (response.ok) {
          const clone = response.clone();
          caches.open(CACHE_NAME).then((cache) => {
            cache.put(event.request, clone);
          });
        }
        return response;
      }).catch(() => cached);

      return cached || fetched;
    })
  );
});

// Push notification event
self.addEventListener('push', (event) => {
  console.log('[SW] Push received');
  
  let data = { title: 'New Dialog', body: 'A new Cursor dialog is waiting' };
  
  if (event.data) {
    try {
      data = event.data.json();
    } catch (e) {
      data.body = event.data.text();
    }
  }

  event.waitUntil(
    self.registration.showNotification(data.title, {
      body: data.body,
      icon: '/manifest.json',
      badge: '/manifest.json',
      vibrate: [200, 100, 200],
      tag: 'cursor-dialog',
      renotify: true,
      requireInteraction: true,
      actions: [
        { action: 'open', title: 'Open' },
        { action: 'dismiss', title: 'Dismiss' },
      ],
    })
  );
});

// Notification click handler
self.addEventListener('notificationclick', (event) => {
  console.log('[SW] Notification click');
  event.notification.close();

  if (event.action === 'dismiss') return;

  // Open or focus the app
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((windowClients) => {
      // If already open, focus it
      for (const client of windowClients) {
        if (client.url.includes(self.location.origin) && 'focus' in client) {
          return client.focus();
        }
      }
      // Otherwise open new window
      if (clients.openWindow) {
        return clients.openWindow('/');
      }
    })
  );
});

