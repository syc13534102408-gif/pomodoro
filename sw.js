self.addEventListener('push', event => {
  const payload = event.data?.json() || {};
  event.waitUntil(self.registration.showNotification(payload.title || '松果 · 专注完成', {
    body: payload.body || '这一轮已经结束，休息一下吧。',
    tag: 'pine-pomodoro-end',
    renotify: true,
    data: { url: payload.url || './' }
  }));
});

self.addEventListener('notificationclick', event => {
  event.notification.close();
  event.waitUntil(clients.openWindow(event.notification.data?.url || './'));
});
