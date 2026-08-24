import { buildPushPayload } from '@block65/webcrypto-web-push';

const json = (body, init = {}) => new Response(JSON.stringify(body), { headers: { 'content-type': 'application/json; charset=utf-8', ...init.headers }, ...init });
const cors = (request, env) => ({
  'access-control-allow-origin': env.ALLOWED_ORIGIN,
  'access-control-allow-methods': 'GET, POST, OPTIONS',
  'access-control-allow-headers': 'content-type',
  'vary': 'Origin'
});
const withCors = (request, env, response) => { const headers = new Headers(response.headers); Object.entries(cors(request, env)).forEach(([key, value]) => headers.set(key, value)); return new Response(response.body, { status: response.status, headers }); };
const validSubscription = subscription => subscription && typeof subscription.endpoint === 'string' && subscription.keys && typeof subscription.keys.p256dh === 'string' && typeof subscription.keys.auth === 'string';

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { headers: cors(request, env) });
    const origin = request.headers.get('origin');
    if (origin && origin !== env.ALLOWED_ORIGIN) return json({ error: '来源未授权' }, { status: 403 });
    const url = new URL(request.url);
    if (request.method === 'GET' && url.pathname === '/vapid-public-key') return withCors(request, env, json({ publicKey: env.VAPID_PUBLIC_KEY }));
    if (request.method === 'POST' && url.pathname === '/reminders') {
      const reminder = await request.json().catch(() => null);
      const endsAt = Number(reminder?.endsAt);
      if (!validSubscription(reminder?.subscription) || !Number.isFinite(endsAt) || endsAt <= Date.now()) return withCors(request, env, json({ error: '提醒参数无效或已经过期' }, { status: 400 }));
      const id = crypto.randomUUID();
      const object = env.TIMER.get(env.TIMER.idFromName(id));
      const response = await object.fetch('https://timer.internal/schedule', { method: 'POST', body: JSON.stringify({ ...reminder, id, endsAt }) });
      return withCors(request, env, response);
    }
    const match = url.pathname.match(/^\/reminders\/([\w-]+)\/cancel$/);
    if (request.method === 'POST' && match) {
      const object = env.TIMER.get(env.TIMER.idFromName(match[1]));
      const response = await object.fetch('https://timer.internal/cancel', { method: 'POST' });
      return withCors(request, env, response);
    }
    return withCors(request, env, json({ error: '未找到接口' }, { status: 404 }));
  }
};

export class TimerReminder {
  constructor(state, env) { this.state = state; this.env = env; }
  async fetch(request) {
    const path = new URL(request.url).pathname;
    if (request.method === 'POST' && path === '/schedule') {
      const reminder = await request.json();
      await this.state.storage.put('reminder', reminder);
      await this.state.storage.setAlarm(reminder.endsAt);
      return json({ id: reminder.id });
    }
    if (request.method === 'POST' && path === '/cancel') {
      await this.state.storage.deleteAll();
      await this.state.storage.deleteAlarm();
      return json({ cancelled: true });
    }
    return json({ error: '未找到接口' }, { status: 404 });
  }
  async alarm() {
    const reminder = await this.state.storage.get('reminder');
    if (!reminder) return;
    const payload = await buildPushPayload({
      data: JSON.stringify({ title: reminder.title || '松果 · 专注完成', body: reminder.body || '这一轮已经结束，休息一下吧。', url: reminder.url || '/' }),
      options: { ttl: 300, urgency: 'high' }
    }, reminder.subscription, { subject: this.env.VAPID_SUBJECT, publicKey: this.env.VAPID_PUBLIC_KEY, privateKey: this.env.VAPID_PRIVATE_KEY });
    const response = await fetch(reminder.subscription.endpoint, payload);
    if (!response.ok && response.status !== 404 && response.status !== 410) throw new Error(`推送服务返回 ${response.status}`);
    await this.state.storage.deleteAll();
  }
}
