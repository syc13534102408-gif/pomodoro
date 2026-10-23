// ⚠️ 已冻结（2026-10-23）：仅网页端使用，网页端自 2026-09-02 起停止维护。
// 安卓/macOS 的提醒走本地通知 + 系统闹钟，不经过这里。详见 CHANGELOG.md 2026-10-23。
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
