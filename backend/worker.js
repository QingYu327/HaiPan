/**
 * 海畔 · 用量统计 + 云端风控 Worker（经典 Service Worker）
 *
 * - POST /            上报登录学号（去重存 COUNT KV）
 * - GET  /            返回 {"count":N,"ids":[学号,...]}
 * - GET  /permission?xh=..   云端风控：单功能授权查询
 * - GET  /gates?xh=..        抢课黑名单 / 更新黑名单 / APP 准入
 * - GET  /perm?admin=..&secret=..        名单管理（管理员查询）
 * - POST /perm  {admin, secret, feature, type, action, xh}
 *       管理员在 APP 内直接增删名单（免发版）
 *
 * 依赖 KV 绑定：COUNT（计数）、ALLOW（名单配置，cfg JSON）。
 */

// ⚠️ 新版 APP 已改为「设备公钥 + 挑战签名」认证，仅 backend/server.js 支持。
// 此 Worker 版本仅供旧版部署参考；公网域名请指向 fnOS 上的 server.js。
// 管理员学号与预共享密钥（旧版静态校验）
const ADMIN = '202411413203';
const PERM_SECRET = 'HAIPAN_PERM_0827';

// 可选：在 Worker 变量里配置 API_TOKEN 后，所有请求都必须带 x-api-token。
// 未配置时保持原行为，避免影响现有部署。
const API_TOKEN =
  typeof globalThis.API_TOKEN === 'string' ? globalThis.API_TOKEN : '';

// 受控功能：
// select=抢课(黑名单，默认可用) update=更新(黑名单) app=APP准入(白名单，默认禁止)
const FEATURES = ['select', 'update', 'app'];

addEventListener('fetch', (event) => {
  event.respondWith(handle(event.request));
});

// 名单存 ALLOW KV 的 key="cfg"，值为 JSON：
// 抢课黑名单 block_select、更新黑名单 block_update、APP 准入 allow_app
async function readCfg() {
  try {
    const raw = await ALLOW.get('cfg');
    if (raw) {
      const p = JSON.parse(raw);
      if (p && typeof p === 'object') return p;
    }
  } catch (_) {}
  return {};
}

async function writeCfg(cfg) {
  await ALLOW.put('cfg', JSON.stringify(cfg));
}

function listOf(cfg, feature) {
  return (cfg[feature] || []).filter(
    (x) => typeof x === 'string' && /^\d{6,20}$/.test(x)
  );
}

// 由功能名 + 名单类型得到 cfg 里的 key：
// block 名单用 block_<feature>；app 的准入是白名单，存 allow_app
function cfgKey(feature, type) {
  if (!FEATURES.includes(feature)) return null;
  if (type === 'block') return feature === 'app' ? null : `block_${feature}`;
  return feature === 'app' ? 'allow_app' : feature;
}

async function handle(request) {
  const url = new URL(request.url);

  if (API_TOKEN) {
    const token = (
      request.headers.get('x-api-token') ||
      url.searchParams.get('token') ||
      ''
    ).trim();
    if (token !== API_TOKEN) return json({ error: 'unauthorized' }, 401);
  }

  // ---- /gates：抢课（黑名单外可用）+ 更新黑名单 + APP 准入（默认禁止）----
  if (url.pathname === '/gates') {
    const xh = (url.searchParams.get('xh') || '').trim();
    const cfg = await readCfg();
    return json({
      select: !listOf(cfg, 'block_select').includes(xh),
      updateBlock: listOf(cfg, 'block_update').includes(xh),
      app: xh === ADMIN || listOf(cfg, 'allow_app').includes(xh),
    });
  }

  // ---- 云端风控：单功能授权查询（默认 select）----
  if (url.pathname === '/permission') {
    const xh = (url.searchParams.get('xh') || '').trim();
    const feature = (url.searchParams.get('feature') || 'select').trim();
    const cfg = await readCfg();
    const allowed = listOf(cfg, cfgKey(feature, 'allow')).includes(xh);
    return json({ allowed, xh, feature });
  }

  // ---- /perm 名单管理：type=allow(白名单,默认) | block(黑名单)，仅管理员 ----
  if (url.pathname === '/perm') {
    const cfg = await readCfg();
    const authorized = (admin, secret) =>
      admin === ADMIN && secret === PERM_SECRET;
    const featureFrom = (feat) =>
      FEATURES.includes((feat || '').trim()) ? (feat || '').trim() : 'select';
    const typeFrom = (type) => (type === 'block' ? 'block' : 'allow');

    if (request.method === 'GET') {
      const admin = (url.searchParams.get('admin') || '').trim();
      const secret = (url.searchParams.get('secret') || '').trim();
      const feature = featureFrom(url.searchParams.get('feature'));
      const type = typeFrom(url.searchParams.get('type'));
      const key = cfgKey(feature, type);
      if (!authorized(admin, secret)) {
        return json({ ok: false, error: 'unauthorized', feature, type, list: [] });
      }
      return json({ ok: true, feature, type, list: listOf(cfg, key) });
    }

    if (request.method === 'POST') {
      let body = {};
      try { body = await request.json(); } catch (_) {}
      const admin = String(body.admin || '').trim();
      const secret = String(body.secret || '').trim();
      if (!authorized(admin, secret)) {
        return json({ ok: false, error: 'unauthorized' });
      }
      const feature = featureFrom(body.feature);
      const type = typeFrom(body.type);
      const action = String(body.action || '').trim();
      const xh = String(body.xh || '').trim();
      const key = cfgKey(feature, type);
      if (!key) {
        return json({ ok: false, error: 'bad_type', feature, type });
      }
      if (!/^\d{6,20}$/.test(xh)) {
        return json({ ok: false, error: 'bad_xh', feature, type, list: listOf(cfg, key) });
      }
      let list = listOf(cfg, key);
      if (action === 'add' && !list.includes(xh)) list.push(xh);
      if (action === 'remove') list = list.filter((x) => x !== xh);
      cfg[key] = [...new Set(list)];
      await writeCfg(cfg);
      return json({ ok: true, action, type, xh, feature, list: cfg[key] });
    }

    return json({ ok: false, error: 'method_not_allowed' });
  }

  // ---- 用量统计 ----
  const key = 'haipan_users';
  let list = [];
  try {
    const raw = await COUNT.get(key);
    if (raw) {
      const p = JSON.parse(raw);
      if (Array.isArray(p)) list = p;
    }
  } catch (_) {}
  list = list.map((x) => String(x).trim()).filter((x) => /^\d{6,20}$/.test(x));
  list = [...new Set(list)];

  if (request.method === 'POST') {
    let xh = '';
    try {
      const body = await request.json();
      xh = String((body && body.xh) || '').trim();
    } catch (_) {}
    if (/^\d{6,20}$/.test(xh)) {
      list = [...new Set([...list, xh])];
      await COUNT.put(key, JSON.stringify(list));
    }
  }
  list.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  return json({ count: list.length, ids: list });
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}