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
  async fetch(request, env, ctx) {
    const url0 = new URL(request.url);
    const origin0 = request.headers.get('origin');
    let response;
    try {
      response = await route(request, env);
    } catch (error) {
      response = json({ error: `服务内部错误：${error?.message || error}` }, { status: 500 });
    }
    ctx.waitUntil(recordRequest(env, request, url0, origin0, response.status).catch(() => {}));
    return response;
  }
};

async function route(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { headers: cors(request, env) });
    const origin = request.headers.get('origin');
    if (origin && origin !== env.ALLOWED_ORIGIN) return json({ error: '来源未授权' }, { status: 403 });
    const url = new URL(request.url);
    // 自检端点：用于确认线上跑的是哪一份代码，以及各项绑定是否就绪。
    if (request.method === 'GET' && url.pathname === '/ping')
      return withCors(request, env, json({
        ok: true,
        build: '2026-08-30-sync-diagnostics',
        hasSyncRoutes: true,
        dbBound: Boolean(env.DB),
        timerBound: Boolean(env.TIMER),
        allowedOrigin: env.ALLOWED_ORIGIN || null,
        now: new Date().toISOString()
      }));
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
    if (request.method === 'POST' && url.pathname === '/sync/upload') {
      if (!env.DB) return withCors(request, env, json({ error: '云端同步数据库尚未配置' }, { status: 503 }));
      const body = await request.json().catch(() => null);
      const deviceCode = body?.deviceCode;
      const payload = body?.payload;
      const baseUpdatedAt = body?.baseUpdatedAt;
      if (typeof deviceCode !== 'string' || !/^[A-Za-z0-9_-]{16,128}$/.test(deviceCode) || !payload || typeof payload !== 'object' || Array.isArray(payload)) {
        return withCors(request, env, json({ error: '同步参数无效' }, { status: 400 }));
      }
      const serialized = JSON.stringify(payload);
      if (serialized.length > 1024 * 1024) return withCors(request, env, json({ error: '备份数据超过 1MB 限制' }, { status: 413 }));
      const updatedAt = new Date().toISOString();
      const statement = typeof baseUpdatedAt === 'string'
        ? env.DB.prepare(`INSERT INTO sync_backups (device_code, payload, updated_at) VALUES (?, ?, ?) ON CONFLICT(device_code) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at WHERE sync_backups.updated_at = ?`).bind(deviceCode, serialized, updatedAt, baseUpdatedAt)
        : env.DB.prepare(`INSERT INTO sync_backups (device_code, payload, updated_at) VALUES (?, ?, ?) ON CONFLICT(device_code) DO UPDATE SET payload = excluded.payload, updated_at = excluded.updated_at`).bind(deviceCode, serialized, updatedAt);
      const result = await statement.run();
      if (typeof baseUpdatedAt === 'string' && result.meta.changes === 0) return withCors(request, env, json({ error: '云端数据已在另一台设备更新，请重新同步', conflict: true }, { status: 409 }));
      return withCors(request, env, json({ updatedAt }));
    }
    if (request.method === 'GET' && url.pathname === '/sync/download') {
      if (!env.DB) return withCors(request, env, json({ error: '云端同步数据库尚未配置' }, { status: 503 }));
      const deviceCode = url.searchParams.get('deviceCode');
      if (typeof deviceCode !== 'string' || !/^[A-Za-z0-9_-]{16,128}$/.test(deviceCode)) return withCors(request, env, json({ error: '同步码无效' }, { status: 400 }));
      const row = await env.DB.prepare('SELECT payload, updated_at AS updatedAt FROM sync_backups WHERE device_code = ?').bind(deviceCode).first();
      if (!row) return withCors(request, env, json({ error: '没有找到云端备份' }, { status: 404 }));
      let payload;
      try { payload = JSON.parse(row.payload); } catch { return withCors(request, env, json({ error: '云端备份已损坏' }, { status: 500 })); }
      return withCors(request, env, json({ payload, updatedAt: row.updatedAt }));
    }
    const match = url.pathname.match(/^\/reminders\/([\w-]+)\/cancel$/);
    if (request.method === 'POST' && match) {
      const object = env.TIMER.get(env.TIMER.idFromName(match[1]));
      const response = await object.fetch('https://timer.internal/cancel', { method: 'POST' });
      return withCors(request, env, response);
    }
    return withCors(request, env, json({
      error: `未找到接口：${request.method} ${url.pathname}`,
      receivedMethod: request.method,
      receivedPath: url.pathname,
      available: ['GET /ping', 'GET /vapid-public-key', 'POST /reminders', 'POST /sync/upload', 'GET /sync/download', 'POST /reminders/:id/cancel']
    }, { status: 404 }));
}

async function recordRequest(env, request, url, origin, status) {
  if (!env.DB) return;
  try {
    await env.DB.prepare(
      'INSERT INTO request_log (ts, method, path, status, origin, ua) VALUES (?, ?, ?, ?, ?, ?)'
    )
      .bind(
        new Date().toISOString(),
        request.method,
        url.pathname,
        status,
        origin || null,
        (request.headers.get('user-agent') || '').slice(0, 180)
      )
      .run();
  } catch (_) {
    // 日志失败不能影响主流程
  }
}

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
