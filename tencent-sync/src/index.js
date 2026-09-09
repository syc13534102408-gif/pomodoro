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
    return reply(404, {
      error: `未找到接口：${method} ${path}`,
      receivedMethod: method,
      receivedPath: path,
    }, origin);
  } catch (error) {
    return reply(500, { error: `服务内部错误：${error && error.message ? error.message : error}` }, origin);
  }
};
