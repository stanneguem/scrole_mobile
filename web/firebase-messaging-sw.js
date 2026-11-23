// Firebase Cloud Messaging background worker for Scrole Web.
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyApUvHYMz0uqnSCpBgUt-br6uyMhNnaFIw',
  authDomain: 'scrole-cd3c3.firebaseapp.com',
  projectId: 'scrole-cd3c3',
  storageBucket: 'scrole-cd3c3.firebasestorage.app',
  messagingSenderId: '267698917909',
  appId: '1:267698917909:web:3854117b525e5dee66b41c',
  measurementId: 'G-SLSNTKMZ1X'
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const data = payload.data || {};
  const title = data.title || 'Scrole';
  const options = {
    body: data.body || 'Vous avez une nouvelle notification.',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: { url: data.url || data.deep_link || '/', notificationId: data.notification_id || null },
    tag: data.notification_id || undefined,
    renotify: false
  };
  return self.registration.showNotification(title, options);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const target = new URL(event.notification.data?.url || '/', self.location.origin).href;
  event.waitUntil((async () => {
    const windows = await clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const client of windows) {
      if ('focus' in client) {
        await client.focus();
        if ('navigate' in client && client.url !== target) await client.navigate(target);
        return;
      }
    }
    if (clients.openWindow) await clients.openWindow(target);
  })());
});
