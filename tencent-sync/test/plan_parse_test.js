// 本地单测：node --test tencent-sync/test
// 只测解析与路由层，不真的打模型接口（fetch 被替换成假实现）。
const test = require('node:test');
const assert = require('node:assert');

process.env.PINE_LLM_API_KEY = 'sk-test';
process.env.COS_BUCKET = 'test-bucket';
const mod = require('../src/index.js');
const { sanitizePlan, stripHtml } = mod._test;

function eventFor(body) {
  return {
    httpMethod: 'POST',
    path: '/plan/parse',
    headers: { origin: 'https://example.com' },
    body: JSON.stringify(body),
  };
}

test('sanitizePlan 只留「日期+条目」行，丢掉解释与项目符号', () => {
  const raw = [
    '好的，下面是日程：',
    '- 10/24 2018 数一复盘',
    '* 10/25  现控 ch5 下半',
    '这里不需要额外说明',
    '10/26',
  ].join('\n');
  assert.strictEqual(
    sanitizePlan(raw),
    '10/24\t2018 数一复盘\n10/25\t现控 ch5 下半',
  );
});

test('sanitizePlan 接受 ISO 日期', () => {
  assert.strictEqual(sanitizePlan('2026-10-27 816 真题①'), '2026-10-27\t816 真题①');
});

test('stripHtml 去掉脚本样式，块级标签转换行', () => {
  const html = '<script>x=1</script><style>.a{}</style><p>10/24 复盘</p><p>10/25 现控</p>';
  const text = stripHtml(html);
  assert.ok(!text.includes('x=1'));
  assert.ok(text.includes('10/24 复盘'));
  assert.ok(text.includes('10/25 现控'));
});

test('handlePlanParse 把模型输出清洗后返回 plan 字段', async () => {
  const realFetch = global.fetch;
  global.fetch = async () => ({
    ok: true,
    status: 200,
    text: async () => JSON.stringify({
      choices: [{ message: { content: '10/24\t2018 复盘\n10/25\t现控 ch6' } }],
      usage: { total_tokens: 42 },
    }),
  });
  try {
    const res = await mod.main_handler(eventFor({ text: '下周一二做点复盘' }));
    const body = JSON.parse(res.body);
    assert.strictEqual(res.statusCode, 200);
    assert.strictEqual(body.plan, '10/24\t2018 复盘\n10/25\t现控 ch6');
    assert.strictEqual(body.lines, 2);
    assert.strictEqual(body.model, 'deepseek-chat');
  } finally {
    global.fetch = realFetch;
  }
});

test('模型返回不可解析内容时给出 422 而不是空 plan', async () => {
  const realFetch = global.fetch;
  global.fetch = async () => ({
    ok: true,
    status: 200,
    text: async () => JSON.stringify({ choices: [{ message: { content: '抱歉，我无法理解' } }] }),
  });
  try {
    const res = await mod.main_handler(eventFor({ text: '??? ' }));
    assert.strictEqual(res.statusCode, 422);
  } finally {
    global.fetch = realFetch;
  }
});

test('缺 text/url 返回 400', async () => {
  const res = await mod.main_handler(eventFor({}));
  assert.strictEqual(res.statusCode, 400);
});

test('未配置密钥时返回 501 且有 hint', async () => {
  const realKey = process.env.PINE_LLM_API_KEY;
  delete process.env.PINE_LLM_API_KEY;
  delete require.cache[require.resolve('../src/index.js')];
  const fresh = require('../src/index.js');
  try {
    const res = await fresh.main_handler(eventFor({ text: '10/24 复盘' }));
    const body = JSON.parse(res.body);
    assert.strictEqual(res.statusCode, 501);
    assert.ok(body.hint.includes('PINE_LLM_API_KEY'));
  } finally {
    process.env.PINE_LLM_API_KEY = realKey;
    delete require.cache[require.resolve('../src/index.js')];
  }
});
