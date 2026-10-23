'use strict';

const COS = require('cos-nodejs-sdk-v5');

const BUCKET = process.env.COS_BUCKET;
const REGION = process.env.COS_REGION || 'ap-guangzhou';
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS ||
  'https://syc13534102408-gif.github.io').split(',').map((s) => s.trim());

const MAX_PAYLOAD = 1024 * 1024; // 1MB
const CODE_RE = /^[A-Za-z0-9_-]{16,128}$/;

// 注意：云函数保留 SCF_ / QCLOUD_ / TENCENTCLOUD_ 前缀，自定义变量不能用，
// 所以用 PINE_ 前缀。
const SECRET_ID = process.env.PINE_SECRET_ID;

// 智能解析（/plan/parse）。密钥**只**放函数环境变量，客户端永远拿不到；
// 这样 APK 反编译也偷不走，且用户换模型不用发新包。
const LLM_KEY = process.env.PINE_LLM_API_KEY;
const LLM_BASE = (process.env.PINE_LLM_BASE_URL || 'https://api.deepseek.com').replace(/\/+$/, '');
const LLM_MODEL = process.env.PINE_LLM_MODEL || 'deepseek-chat';
const PLAN_MAX_TEXT = 20000;
const PLAN_TIMEOUT_MS = 12000;
const SECRET_KEY = process.env.PINE_SECRET_KEY;

let cosClient = null;
function cos() {
  if (!cosClient) {
    cosClient = new COS({ SecretId: SECRET_ID, SecretKey: SECRET_KEY });
  }
  return cosClient;
}

function corsHeaders(origin) {
  const allow = origin && ALLOWED_ORIGINS.includes(origin)
    ? origin
    : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allow,
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'content-type',
    'Vary': 'Origin',
  };
}

function reply(statusCode, body, origin) {
  return {
    isBase64Encoded: false,
    statusCode,
    headers: {
      ...corsHeaders(origin),
      'Content-Type': 'application/json; charset=utf-8',
    },
    body: typeof body === 'string' ? body : JSON.stringify(body),
  };
}

const keyOf = (deviceCode) => `sync/${deviceCode}.json`;

// 会话实时镜像：与备份净荷（sync/）完全分离，只有最新的会话快照，直接覆盖写。
const sessionKeyOf = (deviceCode) => `session/${deviceCode}.json`;
const MAX_SESSION_PAYLOAD = 16 * 1024;

function readObject(key) {
  return new Promise((resolve, reject) => {
    cos().getObject(
      { Bucket: BUCKET, Region: REGION, Key: key },
      (err, data) => {
        if (err) {
          // COS 在对象不存在时返回 404 / NoSuchKey
          if (err.statusCode === 404 || err.code === 'NoSuchKey') {
            resolve(null);
          } else {
            reject(err);
          }
          return;
        }
        const raw = data.Body && data.Body.toString ? data.Body.toString() : String(data.Body || '');
        resolve(raw);
      }
    );
  });
}

function writeObject(key, body) {
  return new Promise((resolve, reject) => {
    cos().putObject(
      { Bucket: BUCKET, Region: REGION, Key: key, Body: body, ContentType: 'application/json' },
      (err) => (err ? reject(err) : resolve())
    );
  });
}

async function handleUpload(body, origin) {
  const { deviceCode, payload, baseUpdatedAt } = body || {};
  if (typeof deviceCode !== 'string' || !CODE_RE.test(deviceCode)) {
    return reply(400, { error: '同步参数无效' }, origin);
  }
  if (!payload || typeof payload !== 'object' || Array.isArray(payload)) {
    return reply(400, { error: '同步参数无效' }, origin);
  }
  const serialized = JSON.stringify(payload);
  if (serialized.length > MAX_PAYLOAD) {
    return reply(413, { error: '备份数据超过 1MB 限制' }, origin);
  }

  const existing = await readObject(keyOf(deviceCode));
  if (typeof baseUpdatedAt === 'string' && existing) {
    let current = null;
    try {
      current = JSON.parse(existing);
    } catch (_) {
      current = null;
    }
    if (current && current.updatedAt && current.updatedAt !== baseUpdatedAt) {
      return reply(409, { error: '云端数据已在另一台设备更新，请重新同步', conflict: true }, origin);
    }
  }

  const updatedAt = new Date().toISOString();
  await writeObject(keyOf(deviceCode), JSON.stringify({ payload, updatedAt }));
  return reply(200, { updatedAt }, origin);
}

async function handleDownload(query, origin) {
  const deviceCode = (query && (query.deviceCode || query.devicecode)) || '';
  if (typeof deviceCode !== 'string' || !CODE_RE.test(deviceCode)) {
    return reply(400, { error: '同步码无效' }, origin);
  }
  const raw = await readObject(keyOf(deviceCode));
  if (!raw) return reply(404, { error: '没有找到云端备份' }, origin);

  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (_) {
    return reply(500, { error: '云端备份已损坏' }, origin);
  }
  return reply(200, { payload: parsed.payload, updatedAt: parsed.updatedAt }, origin);
}

async function handleSessionPublish(body, origin) {
  const { deviceCode, deviceId, seq, session, taskName } = body || {};
  if (typeof deviceCode !== 'string' || !CODE_RE.test(deviceCode)) {
    return reply(400, { error: '同步码无效' }, origin);
  }
  if (typeof deviceId !== 'string' || deviceId.length < 4 || deviceId.length > 64) {
    return reply(400, { error: '设备标识无效' }, origin);
  }
  if (!Number.isInteger(seq) || seq < 0) {
    return reply(400, { error: 'seq 无效' }, origin);
  }
  if (session !== null && (typeof session !== 'object' || Array.isArray(session))) {
    return reply(400, { error: '会话状态无效' }, origin);
  }
  const record = {
    deviceId,
    seq,
    at: new Date().toISOString(),
    session: session ?? null,
    taskName: typeof taskName === 'string' ? taskName : null,
  };
  const serialized = JSON.stringify(record);
  if (serialized.length > MAX_SESSION_PAYLOAD) {
    return reply(413, { error: '会话状态超过 16KB 限制' }, origin);
  }
  await writeObject(sessionKeyOf(deviceCode), serialized);
  return reply(200, { seq, at: record.at }, origin);
}

async function handleSessionPoll(query, origin) {
  const deviceCode = (query && (query.deviceCode || query.devicecode)) || '';
  if (typeof deviceCode !== 'string' || !CODE_RE.test(deviceCode)) {
    return reply(400, { error: '同步码无效' }, origin);
  }
  // 无记录 / 记录损坏都返回空态，轮询端无需特判 404。
  const empty = { seq: 0, deviceId: null, at: null, session: null, taskName: null };
  const raw = await readObject(sessionKeyOf(deviceCode));
  if (!raw) return reply(200, empty, origin);
  let parsed;
  try {
    parsed = JSON.parse(raw);
  } catch (_) {
    return reply(200, empty, origin);
  }
  return reply(200, {
    seq: Number.isInteger(parsed.seq) ? parsed.seq : 0,
    deviceId: typeof parsed.deviceId === 'string' ? parsed.deviceId : null,
    at: typeof parsed.at === 'string' ? parsed.at : null,
    session: parsed.session && typeof parsed.session === 'object' ? parsed.session : null,
    taskName: typeof parsed.taskName === 'string' ? parsed.taskName : null,
  }, origin);
}

// ---------- 智能解析：自然语言/网页 → 标准日程文本 ----------
//
// 为什么放服务端：模型密钥不能进客户端（APK 可反编译），而且解析规则要能随时改，
// 不该逼用户装新包。客户端只发文本、收文本，落库仍走本地 plan_import.dart。
// 返回格式固定成「日期<TAB>条目」，正好是 parsePlan() 的输入。

function planToday() {
  // 服务器时区不可靠，显式按用户所在时区算"今天"，让"下周三"这类相对日期有锚点。
  return new Date().toLocaleDateString('zh-CN', {
    timeZone: 'Asia/Shanghai', year: 'numeric', month: '2-digit', day: '2-digit',
  });
}

function stripHtml(html) {
  return String(html || '')
    .replace(/<script[\s\S]*?<\/script>/gi, ' ')
    .replace(/<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/(p|div|li|tr|h[1-6])>/gi, '\n')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/[ \t]+/g, ' ')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

async function fetchPageText(url) {
  if (!/^https?:\/\//i.test(url)) throw new Error('只支持 http(s) 链接');
  const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return stripHtml(await res.text());
}

// 模型偶尔会加项目符号/解释句，这里只收「日期 正文」形态的行，坏行直接丢掉。
function sanitizePlan(raw) {
  const lines = [];
  for (const line of String(raw || '').split('\n')) {
    const text = line.trim().replace(/^[-*•·]\s*/, '');
    const m = text.match(/^(\d{4}-\d{1,2}-\d{1,2}|\d{1,2}[/-]\d{1,2})\s+(.+)$/);
    if (!m) continue;
    const date = m[1].replace(/-(?=\d{1,2}$)/, '-');
    const body = m[2].trim().replace(/\s+/g, ' ');
    if (body) lines.push(`${date}\t${body}`);
  }
  return lines.join('\n');
}

async function handlePlanParse(body, origin) {
  if (!LLM_KEY) {
    return reply(501, {
      error: '服务端未配置 PINE_LLM_API_KEY',
      hint: '在 tencent-sync 下用 PINE_LLM_API_KEY=... 重新 deploy.py --update',
      providers: 'OpenCode Zen 用 PINE_LLM_BASE_URL=https://opencode.ai/zen/v1；DeepSeek 用默认值',
    }, origin);
  }
  const text = typeof body?.text === 'string' ? body.text.trim() : '';
  const url = typeof body?.url === 'string' ? body.url.trim() : '';
  if (!text && !url) return reply(400, { error: '需要 text 或 url' }, origin);

  let source = text;
  if (url) {
    try {
      source = await fetchPageText(url);
    } catch (error) {
      return reply(400, { error: `抓取网页失败：${error.message}` }, origin);
    }
  }
  if (!source) return reply(400, { error: '内容为空' }, origin);
  if (source.length > PLAN_MAX_TEXT) source = source.slice(0, PLAN_MAX_TEXT);

  const system = [
    '你是日程抽取器。把输入里的学习计划抽成逐条日程。',
    `今天日期：${planToday()}（用户在中国时区）。相对日期（今晚/明天/周三/下周三）请换算成具体月日。`,
    '输出规则（严格遵守）：',
    '1. 每行一条，格式为「月/日 + 制表符 + 条目」，例如 10/24\t2018 数一复盘',
    '2. 禁止输出解释、标题、编号、markdown、代码块。',
    '3. 条目保留原文关键信息（科目、题号、限时时长），去掉"完成/做/进行"这类空话。',
    '4. 一条任务拆得越具体越好，但不要臆造原文没有的任务。',
  ].join('\n');

  let payload;
  try {
    const res = await fetch(`${LLM_BASE}/chat/completions`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${LLM_KEY}`,
      },
      body: JSON.stringify({
        model: LLM_MODEL,
        temperature: 0,
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: source },
        ],
      }),
      signal: AbortSignal.timeout(PLAN_TIMEOUT_MS),
    });
    const raw = await res.text();
    if (!res.ok) {
      // 把上游的英文错误翻成用户能行动的一句话，原始 body 仍放在 detail 里供排查。
      let error = `模型接口返回 ${res.status}`;
      if (res.status === 402 || /insufficient|funds|balance|quota/i.test(raw)) {
        error = '模型账户余额不足，充值后才能用智能解析';
      } else if (res.status === 401 || res.status === 403) {
        error = '模型密钥无效或无权限（OpenCode 的免费模型只能在官方客户端内使用）';
      } else if (res.status === 429) {
        error = '模型接口限流，稍后重试';
      } else if (res.status >= 500) {
        error = '模型服务暂时不可用，稍后重试';
      }
      return reply(502, { error, detail: raw.slice(0, 300), upstreamStatus: res.status }, origin);
    }
    payload = JSON.parse(raw);
  } catch (error) {
    return reply(502, { error: `调用模型失败：${error.message}` }, origin);
  }

  const content = payload?.choices?.[0]?.message?.content || '';
  const plan = sanitizePlan(content);
  if (!plan) {
    return reply(422, {
      error: '模型没有抽出可用日程',
      raw: String(content).slice(0, 300),
    }, origin);
  }
  return reply(200, {
    plan,
    lines: plan.split('\n').length,
    model: LLM_MODEL,
    fromUrl: Boolean(url),
    usage: payload?.usage || null,
  }, origin);
}

// 供本地 node:test 使用的钩子（SCF 只认 main_handler，多导几个不影响线上）。
exports._test = { sanitizePlan, stripHtml, handlePlanParse, fetchPageText };

exports.main_handler = async (event) => {
  const headers = event.headers || {};
  const origin = headers.origin || headers.Origin || null;
  const method = (event.httpMethod || (event.requestContext && event.requestContext.httpMethod) || 'GET').toUpperCase();
  const path = event.path || (event.requestContext && event.requestContext.path) || '/';
  const query = event.queryString || event.queryStringParameters || {};

  if (method === 'OPTIONS') {
    return { isBase64Encoded: false, statusCode: 204, headers: corsHeaders(origin), body: '' };
  }

  try {
    if (method === 'GET' && path.endsWith('/ping')) {
      return reply(200, {
        ok: true,
        provider: 'tencent-scf',
        bucketBound: Boolean(BUCKET),
        secretBound: Boolean(SECRET_ID && SECRET_KEY),
        llmBound: Boolean(LLM_KEY),
        region: REGION,
        now: new Date().toISOString(),
      }, origin);
    }
    if (method === 'POST' && path.endsWith('/sync/upload')) {
      let body = event.body;
      if (event.isBase64Encoded && body) {
        body = Buffer.from(body, 'base64').toString('utf8');
      }
      let parsed = null;
      try {
        parsed = body ? JSON.parse(body) : null;
      } catch (_) {
        parsed = null;
      }
      return await handleUpload(parsed, origin);
    }
    if (method === 'GET' && path.endsWith('/sync/download')) {
      return await handleDownload(query, origin);
    }
    if (method === 'POST' && path.endsWith('/session/publish')) {
      let body = event.body;
      if (event.isBase64Encoded && body) {
        body = Buffer.from(body, 'base64').toString('utf8');
      }
      let parsed = null;
      try {
        parsed = body ? JSON.parse(body) : null;
      } catch (_) {
        parsed = null;
      }
      return await handleSessionPublish(parsed, origin);
    }
    if (method === 'GET' && path.endsWith('/session/poll')) {
      return await handleSessionPoll(query, origin);
    }
    if (method === 'POST' && path.endsWith('/plan/parse')) {
      let body = event.body;
      if (event.isBase64Encoded && body) {
        body = Buffer.from(body, 'base64').toString('utf8');
      }
      let parsed = null;
      try {
        parsed = body ? JSON.parse(body) : null;
      } catch (_) {
        parsed = null;
      }
      return await handlePlanParse(parsed, origin);
    }
    return reply(404, {
      error: `未找到接口：${method} ${path}`,
      receivedMethod: method,
      receivedPath: path,
    }, origin);
  } catch (error) {
    return reply(500, { error: `服务内部错误：${error && error.message ? error.message : error}` }, origin);
  }
};
