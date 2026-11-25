/**
 * 海畔 · 云端 API（Docker 自托管版）
 *
 * 设备认证（非对称挑战应答，无任何预共享密钥）：
 * - POST /device/register {xh, publicKey}  登记/校验设备公钥（仅 APP 白名单内学号）
 * - POST /auth/challenge {xh}              下发一次性挑战码
 * - POST /auth/verify {xh, challenge, signature}  验签并签发会话令牌
 * - 其余接口需 Authorization: Bearer <token>
 *
 * 业务接口：
 * - POST /             上报登录学号（去重）
 * - GET  /             返回 {"count":N,"ids":[...]}（仅管理员）
 * - GET  /gates?xh=    返回 {select, updateBlock, app}
 * - GET  /permission?xh=&feature=  单功能授权查询
 * - GET  /perm?feature=&type=  名单查询（仅管理员）
 * - POST /perm {feature,type,action,xh} 名单增删 / 重置设备（仅管理员）
 * - GET  /notes     学号备注查询（仅管理员）
 * - POST /notes {xh,note} 学号备注写入/清空（仅管理员）
 *
 * 数据持久化：$DATA_DIR/haipan.json（建议挂载宿主机卷）。
 * 无第三方依赖，Node 18+ 直接运行。
 */
'use strict';

const http = require('http');
const https = require('https');
const net = require('net');
const fs = require('fs');
const fsp = fs.promises;
const path = require('path');
const crypto = require('crypto');

/**
 * 进程级 DNS 缓存。
 *
 * 每条隧道子流都会 net.connect 到教务，Node 每次都要做一次 getaddrinfo。
 * 容器内 Docker 默认 DNS 转发在部分环境要 2s×2 次重试才返回，导致每条连接
 * 凭空多出 4–5 秒（实测直连教务只要 45–75ms，经隧道每跳却要 4.8 秒）。
 * 这里按 10 分钟 TTL 缓存解析结果，命中时直接走 nextTick，不阻塞。
 */
const dns = require('node:dns');
const DNS_TTL = 10 * 60 * 1000;
const dnsCache = new Map();
const _dnsLookup = dns.lookup;
dns.lookup = function lookup(hostname, options, callback) {
  if (typeof options === 'function') {
    callback = options;
    options = {};
  }
  const opts = options || {};
  // all / IPv6 优先的调用不做缓存，避免改变原有语义
  if (opts.all || opts.family === 6) {
    return _dnsLookup.call(this, hostname, opts, callback);
  }
  const hit = dnsCache.get(hostname);
  if (hit && Date.now() - hit.at < DNS_TTL) {
    process.nextTick(() => callback(null, hit.address, hit.family));
    return undefined;
  }
  return _dnsLookup.call(this, hostname, opts, (err, address, family) => {
    if (!err && address) {
      dnsCache.set(hostname, { address, family, at: Date.now() });
    }
    callback(err, address, family);
  });
};

const PORT = Number(process.env.PORT || 8080);
const DATA_DIR = process.env.DATA_DIR || '/data';
const ADMIN = process.env.ADMIN || '202411413203';

// 国内直连端口：只跑 TLS（自签证书由客户端固定指纹），不接受任何明文 HTTP。
// 公网经阿里云 TCP 穿透映射到宿主机 18443。
const TLS_PORT = Number(process.env.TLS_PORT || 8443);
const TLS_CERT = process.env.TLS_CERT || path.join(DATA_DIR, 'tls', 'cert.pem');
const TLS_KEY = process.env.TLS_KEY || path.join(DATA_DIR, 'tls', 'key.pem');

const SESSION_TTL = 30 * 60 * 1000; // 会话 30 分钟
const CHALLENGE_TTL = 2 * 60 * 1000; // 挑战码 2 分钟且一次性

// select=抢课(黑名单，默认可用) update=更新(黑名单) app=APP准入(白名单，默认禁止)
const FEATURES = ['select', 'update', 'app'];
const DATA_FILE = path.join(DATA_DIR, 'haipan.json');

let state = { users: [], cfg: {}, devices: {}, notes: {}, settings: {} };
let writeChain = Promise.resolve();

// 会话与挑战码只驻留内存：服务重启后客户端会自动重新认证
const sessions = new Map();
const challenges = new Map();

function load() {
  try {
    const raw = fs.readFileSync(DATA_FILE, 'utf8');
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === 'object') {
      state.users = Array.isArray(parsed.users) ? parsed.users : [];
      state.cfg = parsed.cfg && typeof parsed.cfg === 'object' ? parsed.cfg : {};
      state.devices =
        parsed.devices && typeof parsed.devices === 'object' ? parsed.devices : {};
      state.notes =
        parsed.notes && typeof parsed.notes === 'object' ? parsed.notes : {};
      state.settings =
        parsed.settings && typeof parsed.settings === 'object'
          ? parsed.settings
          : {};
    }
  } catch (_) {
    // 首次启动或无数据文件：使用空状态
  }
}

function save() {
  // 串行写入 + 原子替换，避免并发请求写坏 JSON
  writeChain = writeChain.then(async () => {
    await fsp.mkdir(DATA_DIR, { recursive: true });
    const tmp = `${DATA_FILE}.tmp`;
    await fsp.writeFile(tmp, JSON.stringify(state), 'utf8');
    await fsp.rename(tmp, DATA_FILE);
  }).catch((e) => console.error('持久化失败', e));
  return writeChain;
}

/** 学号脱敏：保留前 2 后 2，中间用 *；用于日志与对外返回 */
function maskId(xh) {
  const s = String(xh || '').trim();
  if (s.length <= 4) return s;
  return `${s.slice(0, 2)}${'*'.repeat(s.length - 4)}${s.slice(-2)}`;
}

function listOf(key) {
  const list = state.cfg[key];
  if (!Array.isArray(list)) return [];
  return list.filter((x) => typeof x === 'string' && /^\d{6,20}$/.test(x));
}

function users() {
  return [
    ...new Set(
      state.users
        .map((x) => String(x).trim())
        .filter((x) => /^\d{6,20}$/.test(x))
    ),
  ];
}

// block 名单用 block_<feature>；app 的准入是白名单，存 allow_app
function cfgKey(feature, type) {
  if (!FEATURES.includes(feature)) return null;
  if (type === 'block') return feature === 'app' ? null : `block_${feature}`;
  return feature === 'app' ? 'allow_app' : feature;
}

// 隧道入口：默认主通道；管理员可在 APP 调试页维护后下发，客户端按序测速切换
const DEFAULT_TUNNEL = 'https://haipan-api.cjhong.top';
// 国内直连入口（阿里云 TCP 穿透 + 自签 TLS），始终排在列表首位
const DIRECT_TUNNEL = process.env.DIRECT_TUNNEL || 'https://8.148.27.215:48644';

function tunnelEndpoints() {
  const raw = Array.isArray(state.cfg.tunnelEndpoints)
    ? state.cfg.tunnelEndpoints
    : [];
  const list = [];
  if (DIRECT_TUNNEL) list.push({ name: '国内直连', url: DIRECT_TUNNEL });
  for (const item of raw) {
    const url = String((item && item.url) || '').trim();
    if (!/^https:\/\/[a-z0-9.-]+(:\d+)?$/i.test(url)) continue;
    if (list.some((x) => x.url === url)) continue;
    const name = String((item && item.name) || '').trim().slice(0, 16);
    list.push({ name: name || url.replace(/^https:\/\//, ''), url });
    if (list.length >= 6) break;
  }
  if (!list.length) list.push({ name: '主通道', url: DEFAULT_TUNNEL });
  // 云端默认入口：管理端可指定，客户端首次同步（无本地选择）时采用
  const def = String(state.cfg.defaultTunnel || '').trim();
  const hasDef = list.some((x) => x.url === def);
  return list.map((x, i) => ({ ...x, default: hasDef ? x.url === def : i === 0 }));
}

function send(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    'content-type': 'application/json; charset=utf-8',
    'access-control-allow-origin': '*',
    'access-control-allow-headers': 'content-type,authorization',
    'access-control-allow-methods': 'GET,POST,OPTIONS',
    // 含权限/名单数据，禁止任何中间层缓存
    'cache-control': 'no-store',
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve) => {
    let raw = '';
    req.on('data', (c) => {
      raw += c;
      if (raw.length > 1e6) req.destroy();
    });
    req.on('end', () => {
      try {
        resolve(JSON.parse(raw || '{}'));
      } catch (_) {
        resolve({});
      }
    });
  });
}

function pruneAuth() {
  const now = Date.now();
  for (const [k, v] of challenges) if (v.expires <= now) challenges.delete(k);
  for (const [k, v] of sessions) if (v.expires <= now) sessions.delete(k);
}

function sessionOf(req) {
  const raw = String(req.headers.authorization || '');
  const token = raw.toLowerCase().startsWith('bearer ')
    ? raw.slice(7).trim()
    : String(req.headers['x-session'] || '').trim();
  if (!token) return null;
  const s = sessions.get(token);
  if (!s) return null;
  if (s.expires <= Date.now()) {
    sessions.delete(token);
    return null;
  }
  return s;
}

function appAllowed(xh) {
  return xh === ADMIN || listOf('allow_app').includes(xh);
}

/** 用登记的 SPKI 公钥验证挑战签名（SHA256withECDSA，DER 签名） */
function verifySignature(xh, data, signatureB64) {
  const device = state.devices[xh];
  if (!device || !device.publicKey) return false;
  try {
    const key = crypto.createPublicKey({
      key: Buffer.from(device.publicKey, 'base64'),
      format: 'der',
      type: 'spki',
    });
    return crypto.verify(
      'sha256',
      Buffer.from(String(data), 'utf8'),
      key,
      Buffer.from(String(signatureB64), 'base64')
    );
  } catch (_) {
    return false;
  }
}

async function handle(req, res) {
  if (req.method === 'OPTIONS') return send(res, 204, {});
  const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
  pruneAuth();
  const now = Date.now();

  // ---- 引导：登记设备公钥（只接受 APP 白名单内学号）----
  if (url.pathname === '/device/register') {
    if (req.method !== 'POST') {
      return send(res, 405, { error: 'method_not_allowed' });
    }
    const body = await readBody(req);
    const xh = String(body.xh || '').trim();
    const publicKey = String(body.publicKey || '').trim();
    if (!/^\d{6,20}$/.test(xh) || publicKey.length < 60) {
      return send(res, 400, { error: 'bad_request' });
    }
    if (!appAllowed(xh)) return send(res, 403, { error: 'not_allowed' });
    const known = state.devices[xh];
    if (known && known.publicKey !== publicKey) {
      // 换绑策略由管理员在 APP「用户统计」页开关控制（默认允许，保持一键换机体验）。
      // 关闭后公钥只能登记一次，防止知道学号的人覆盖绑定、踢掉原会话并冒用隧道。
      if (state.settings.allowRebind === false) {
        console.log('device rebind blocked', maskId(xh));
        return send(res, 409, {
          error: 'device_mismatch',
          message: '该学号已绑定其他设备，请联系管理员重置',
        });
      }
      console.log('device rebind', maskId(xh));
      for (const [token, s] of sessions) {
        if (s.xh === xh) sessions.delete(token);
      }
    }
    if (!known) {
      state.devices[xh] = { publicKey, createdAt: now };
      await save();
    } else if (known.publicKey !== publicKey) {
      known.publicKey = publicKey;
      known.updatedAt = now;
      await save();
    }
    return send(res, 200, { ok: true });
  }

  // ---- 引导：一次性挑战码 ----
  if (url.pathname === '/auth/challenge') {
    if (req.method !== 'POST') {
      return send(res, 405, { error: 'method_not_allowed' });
    }
    const body = await readBody(req);
    const xh = String(body.xh || '').trim();
    if (!/^\d{6,20}$/.test(xh)) return send(res, 400, { error: 'bad_request' });
    if (!state.devices[xh]) return send(res, 403, { error: 'not_registered' });
    const challenge = crypto.randomBytes(24).toString('hex');
    challenges.set(challenge, { xh, expires: now + CHALLENGE_TTL });
    return send(res, 200, {
      challenge,
      expiresIn: Math.floor(CHALLENGE_TTL / 1000),
    });
  }

  // ---- 引导：验签换取会话令牌 ----
  if (url.pathname === '/auth/verify') {
    if (req.method !== 'POST') {
      return send(res, 405, { error: 'method_not_allowed' });
    }
    const body = await readBody(req);
    const xh = String(body.xh || '').trim();
    const challenge = String(body.challenge || '').trim();
    const signature = String(body.signature || '').trim();
    const record = challenges.get(challenge);
    if (!record || record.xh !== xh || record.expires <= now) {
      challenges.delete(challenge);
      return send(res, 401, { error: 'challenge_expired' });
    }
    challenges.delete(challenge); // 一次性，防重放
    if (!verifySignature(xh, challenge, signature)) {
      return send(res, 401, { error: 'bad_signature' });
    }
    const token = crypto.randomBytes(24).toString('hex');
    sessions.set(token, { xh, expires: now + SESSION_TTL });
    return send(res, 200, {
      token,
      expiresIn: Math.floor(SESSION_TTL / 1000),
    });
  }

  // ---- 公共：健康检查（通道测速，不要求会话）----
  if (url.pathname === '/health') {
    return send(res, 200, { ok: true, ts: now });
  }

  // ---- 公共：隧道入口配置（客户端启动同步 / 管理页展示）----
  if (url.pathname === '/tunnel/endpoints' && req.method === 'GET') {
    return send(res, 200, { ok: true, endpoints: tunnelEndpoints() });
  }

  // ---- 其余接口一律要求有效会话 ----
  const session = sessionOf(req);
  if (!session) return send(res, 401, { error: 'unauthorized' });
  const isAdmin = session.xh === ADMIN;

  const featureFrom = (feat) =>
    FEATURES.includes(String(feat || '').trim())
      ? String(feat).trim()
      : 'select';
  const typeFrom = (type) => (type === 'block' ? 'block' : 'allow');

  // ---- /tunnel/endpoints（仅管理员写入）----
  if (url.pathname === '/tunnel/endpoints' && req.method === 'POST') {
    if (!isAdmin) return send(res, 403, { ok: false, error: 'forbidden' });
    const body = await readBody(req);
    const input = Array.isArray(body.endpoints) ? body.endpoints : [];
    const list = [];
    for (const item of input) {
      const raw = String((item && item.url) || '').trim();
      if (!raw) continue;
      let u;
      try {
        u = new URL(raw.replace(/^wss:/i, 'https:'));
      } catch (_) {
        return send(res, 400, { ok: false, error: 'bad_url' });
      }
      if (u.protocol !== 'https:') {
        return send(res, 400, { ok: false, error: 'bad_url' });
      }
      const name = String((item && item.name) || '').trim().slice(0, 16);
      list.push({
        name: name || u.host,
        url: `https://${u.host}`,
      });
      if (list.length >= 6) break;
    }
    if (!list.length) return send(res, 400, { ok: false, error: 'empty' });
    const wanted = String(body.default || '').trim();
    state.cfg.tunnelEndpoints = list;
    state.cfg.defaultTunnel =
      wanted && (wanted === DIRECT_TUNNEL || list.some((x) => x.url === wanted))
        ? wanted
        : list[0].url;
    await save();
    console.log('tunnel endpoints updated by', maskId(session.xh));
    return send(res, 200, { ok: true, endpoints: tunnelEndpoints() });
  }

  // ---- /gates ----
  if (url.pathname === '/gates') {
    const xh = (url.searchParams.get('xh') || session.xh).trim();
    if (xh !== session.xh && !isAdmin) {
      return send(res, 403, { error: 'forbidden' });
    }
    return send(res, 200, {
      select: !listOf('block_select').includes(xh),
      updateBlock: listOf('block_update').includes(xh),
      app: appAllowed(xh),
    });
  }

  // ---- /permission ----
  if (url.pathname === '/permission') {
    const xh = (url.searchParams.get('xh') || session.xh).trim();
    if (xh !== session.xh && !isAdmin) {
      return send(res, 403, { error: 'forbidden' });
    }
    const feature = featureFrom(url.searchParams.get('feature'));
    const allowed = listOf(cfgKey(feature, 'allow')).includes(xh);
    // 不回显学号，只返回判定结果
    return send(res, 200, { allowed, feature });
  }

  // ---- /notes（仅管理员会话）：学号备注，便于区分同号段用户 ----
  if (url.pathname === '/notes') {
    if (!isAdmin) {
      return send(res, 403, { ok: false, error: 'unauthorized' });
    }
    if (req.method === 'GET') {
      const notes = {};
      for (const [k, v] of Object.entries(state.notes || {})) {
        if (!/^\d{6,20}$/.test(k)) continue;
        const note = typeof v === 'string' ? v.trim().slice(0, 40) : '';
        if (note) notes[k] = note;
      }
      return send(res, 200, { ok: true, notes });
    }
    if (req.method === 'POST') {
      const body = await readBody(req);
      const xh = String(body.xh || '').trim();
      if (!/^\d{6,20}$/.test(xh)) {
        return send(res, 200, { ok: false, error: 'bad_xh' });
      }
      const note = String(body.note || '')
        .replace(/\s+/g, ' ')
        .trim()
        .slice(0, 40);
      if (!state.notes || typeof state.notes !== 'object') state.notes = {};
      if (note) state.notes[xh] = note;
      else delete state.notes[xh];
      await save();
      return send(res, 200, { ok: true, note });
    }
    return send(res, 200, { ok: false, error: 'method_not_allowed' });
  }

  // ---- /perm（仅管理员会话）----
  if (url.pathname === '/perm') {
    if (!isAdmin) {
      return send(res, 403, { ok: false, error: 'unauthorized' });
    }
    if (req.method === 'GET') {
      const feature = featureFrom(url.searchParams.get('feature'));
      const type = typeFrom(url.searchParams.get('type'));
      const key = cfgKey(feature, type);
      return send(res, 200, {
        ok: true,
        feature,
        type,
        list: key ? listOf(key) : [],
      });
    }

    if (req.method === 'POST') {
      const body = await readBody(req);
      const feature = featureFrom(body.feature);
      const type = typeFrom(body.type);
      const action = String(body.action || '').trim();
      const xh = String(body.xh || '').trim();
      if (!/^\d{6,20}$/.test(xh)) {
        return send(res, 200, { ok: false, error: 'bad_xh' });
      }
      // 管理员可重置某学号的设备公钥（换机/重装后重新登记）
      if (action === 'resetDevice') {
        delete state.devices[xh];
        await save();
        return send(res, 200, { ok: true, action });
      }
      const key = cfgKey(feature, type);
      if (!key) {
        return send(res, 200, { ok: false, error: 'bad_type', feature, type });
      }
      let list = listOf(key);
      if (action === 'add' && !list.includes(xh)) list.push(xh);
      if (action === 'remove') {
        list = list.filter((x) => x !== xh);
        // 移出 APP 名单时同步清除设备公钥，便于再次审批后重新登记
        if (key === 'allow_app') delete state.devices[xh];
      }
      state.cfg[key] = [...new Set(list)];
      await save();
      return send(res, 200, {
        ok: true,
        action,
        type,
        feature,
        list: state.cfg[key],
      });
    }

    return send(res, 200, { ok: false, error: 'method_not_allowed' });
  }

  // ---- /settings（仅管理员）：运行开关，改完立即持久化 ----
  if (url.pathname === '/settings') {
    if (!isAdmin) {
      return send(res, 403, { ok: false, error: 'unauthorized' });
    }
    if (req.method === 'GET') {
      return send(res, 200, {
        ok: true,
        allowRebind: state.settings.allowRebind !== false,
      });
    }
    if (req.method === 'POST') {
      const body = await readBody(req);
      if (typeof body.allowRebind === 'boolean') {
        state.settings.allowRebind = body.allowRebind;
        await save();
        console.log('settings allowRebind =', body.allowRebind);
      }
      return send(res, 200, {
        ok: true,
        allowRebind: state.settings.allowRebind !== false,
      });
    }
    return send(res, 405, { ok: false, error: 'method_not_allowed' });
  }

  // ---- 用量统计 ----
  if (req.method === 'POST') {
    const body = await readBody(req);
    const xh = String((body && body.xh) || session.xh).trim();
    if (xh !== session.xh && !isAdmin) {
      return send(res, 403, { error: 'forbidden' });
    }
    if (/^\d{6,20}$/.test(xh)) {
      state.users = [...new Set([...users(), xh])];
      await save();
    }
    return send(res, 200, { ok: true });
  }
  if (!isAdmin) return send(res, 403, { error: 'unauthorized' });
  const ids = users().sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  // 仅管理员会话可读；返回完整学号便于识别与备注
  return send(res, 200, { count: ids.length, ids });
}

// ---- 公网裸端口防护（仅国内直连的 TLS 端口启用）----
// 该端口直接暴露在公网 IP+高位端口上，必然被全端口扫描遇到，因此：
// 1) 限每 IP 新建连接频率，超限临时拉黑（只防洪水，正常使用远低于阈值）；
// 2) 并发隧道按「学号」限制，按 IP 只留一个很宽的总量上限——
//    校园网/运营商 NAT 下大量用户共享同一个公网 IP，按 IP 限制会误伤；
// 3) 非法请求（越权目标/子协议不符）累计后拉黑；令牌过期等认证失败阈值更宽；
// 4) 失败计数 10 分钟无新增自动清零，避免弱网历史事件累计成误封；
// 5) TLS 只接受固定子协议，普通浏览器访问拿不到可用服务。
const RATE_WINDOW = 60 * 1000;
const RATE_MAX = 120; // 每 IP 每分钟新建 TCP（含普通 HTTPS 请求）
const MAX_SOCKETS_PER_IP = 64; // 每 IP 并发隧道总量（NAT 共享公网 IP 时留足余量）
const MAX_TUNNEL_PER_XH = 4; // 单学号并发隧道（正常只开 1 条复用通道）
const HARD_FAIL_MAX = 8; // 越权目标 / 子协议不符，典型扫描特征
const SOFT_FAIL_MAX = 30; // 未认证、TLS 握手失败（令牌过期、弱网重连都算正常）
const FAIL_DECAY_MS = 10 * 60 * 1000; // 10 分钟无新失败即清零
const BLOCK_MS = 10 * 60 * 1000;
// 共享源（见 isSharedSource）：只留一个很高的洪水阈值，不做封禁
const RATE_MAX_SHARED = 600;

const ipStats = new Map();
const userTunnels = new Map(); // xh -> 活跃隧道数

function ipOf(socket) {
  const raw = String((socket && socket.remoteAddress) || '');
  return raw.replace(/^::ffff:/, '') || 'unknown';
}

/**
 * 所有公网用户都经隧道/Cloudflare 转到宿主机端口，再经 docker-proxy 进容器，
 * 因此容器看到的源地址统一是回环或内网（连 Cloudflare 通道也一样）。
 * 这种地址无法区分个体，按 IP 限流/封禁会「连坐」全部用户，
 * 所以共享源只保留抗洪水的连接速率上限，不做失败封禁。
 */
function isSharedSource(ip) {
  return (
    ip === 'unknown' ||
    ip === '127.0.0.1' ||
    ip === '::1' ||
    /^10\./.test(ip) ||
    /^192\.168\./.test(ip) ||
    /^172\.(1[6-9]|2\d|3[01])\./.test(ip) ||
    /^169\.254\./.test(ip)
  );
}

function ipStat(socket) {
  const ip = ipOf(socket);
  let st = ipStats.get(ip);
  if (!st) {
    // 记录只保留近期状态，表过大时整体清空，避免被扫端口撑爆内存
    if (ipStats.size > 5000) ipStats.clear();
    st = {
      conn: 0,
      resetAt: 0,
      active: 0,
      hard: 0,
      soft: 0,
      lastFailAt: 0,
      blockedUntil: 0,
      shared: isSharedSource(ip),
    };
    ipStats.set(ip, st);
  }
  return st;
}

/** 记一次失败；hard=扫描特征，soft=认证/握手类可恢复失败。 */
function noteFail(socket, kind) {
  const st = ipStat(socket);
  // 共享源无法定位到人，封禁会误伤所有用户，只记日志不累计
  if (st.shared) return;
  const now = Date.now();
  if (now - st.lastFailAt > FAIL_DECAY_MS) {
    st.hard = 0;
    st.soft = 0;
  }
  st.lastFailAt = now;
  if (kind === 'target' || kind === 'protocol') st.hard++;
  else st.soft++;
  if (st.hard >= HARD_FAIL_MAX || st.soft >= SOFT_FAIL_MAX) {
    st.hard = 0;
    st.soft = 0;
    st.blockedUntil = now + BLOCK_MS;
    console.log(`guard block ${ipOf(socket)} (${kind})`);
  }
}

/** 新建连接限频；返回 false 表示应直接断开。 */
function guardConnection(socket) {
  const st = ipStat(socket);
  const now = Date.now();
  if (st.blockedUntil > now) {
    socket.destroy();
    return false;
  }
  if (now > st.resetAt) {
    st.conn = 0;
    st.resetAt = now + RATE_WINDOW;
  }
  st.conn++;
  const limit = st.shared ? RATE_MAX_SHARED : RATE_MAX;
  if (st.conn > limit) {
    // 共享源只断这一条，不整体封禁
    if (!st.shared) {
      st.blockedUntil = now + BLOCK_MS;
      st.soft = 0;
      st.hard = 0;
      console.log(`guard rate ${ipOf(socket)}`);
    }
    socket.destroy();
    return false;
  }
  return true;
}

/** 每 IP 并发隧道总量（宽上限，只挡住异常占用）。 */
function enterSocket(socket) {
  const st = ipStat(socket);
  if (st.blockedUntil > Date.now()) {
    socket.destroy();
    return false;
  }
  // 共享源是全体用户的合计，上限放宽；真实公网 IP 仍按 64 条
  const cap = st.shared ? MAX_SOCKETS_PER_IP * 4 : MAX_SOCKETS_PER_IP;
  if (st.active >= cap) {
    socket.destroy();
    return false;
  }
  st.active++;
  let released = false;
  socket.on('close', () => {
    if (released) return;
    released = true;
    st.active = Math.max(0, st.active - 1);
  });
  return true;
}

/** 同学号并发隧道上限：认证后按身份限制，不受 NAT 共享 IP 影响。 */
function enterUserTunnel(xh, socket) {
  const n = userTunnels.get(xh) || 0;
  if (n >= MAX_TUNNEL_PER_XH) {
    socket.write('HTTP/1.1 429 Too Many Requests\r\n\r\n');
    socket.destroy();
    return false;
  }
  userTunnels.set(xh, n + 1);
  let released = false;
  socket.on('close', () => {
    if (released) return;
    released = true;
    const cur = userTunnels.get(xh) || 1;
    if (cur <= 1) userTunnels.delete(xh);
    else userTunnels.set(xh, cur - 1);
  });
  return true;
}

// ---- 校外教务通道：WebSocket <-> TCP（只放行教务域名）----
// APP 在手机本地起 CONNECT 代理，把教务流量经 Cloudflare Tunnel 送到这里，
// 再由校园网内的本机转发到 jw/authserver，登录、验证码、Cookie 全部保持原样。
const TUNNEL_TARGETS = new Set([
  'jw.gdou.edu.cn:443',
  'jw.gdou.edu.cn:80',
  'authserver.gdou.edu.cn:443',
  'authserver.gdou.edu.cn:80',
]);
const WS_GUID = '258EAFA5-E914-47DA-95CA-C5AB0DC85B11';
// 直连端口要求带固定子协议，普通浏览器/扫描器握手一律不认
const WS_PROTOCOL = 'haipan-v1';

function wsProtocolOk(req) {
  const raw = String(req.headers['sec-websocket-protocol'] || '');
  return raw.split(',').some((s) => s.trim() === WS_PROTOCOL);
}

/** 回 101 完成握手；返回 false 表示缺少必要头。 */
function acceptUpgrade(req, socket) {
  const key = String(req.headers['sec-websocket-key'] || '');
  if (!key) return false;
  const accept = crypto
    .createHash('sha1')
    .update(key + WS_GUID)
    .digest('base64');
  socket.write(
    'HTTP/1.1 101 Switching Protocols\r\n' +
      'Upgrade: websocket\r\n' +
      'Connection: Upgrade\r\n' +
      `Sec-WebSocket-Accept: ${accept}\r\n` +
      // 客户端声明了子协议就必须回显，否则 Dart 侧会判定握手失败
      (wsProtocolOk(req) ? `Sec-WebSocket-Protocol: ${WS_PROTOCOL}\r\n` : '') +
      '\r\n'
  );
  return true;
}

function wsFrame(opcode, payload) {
  const len = payload.length;
  let header;
  if (len < 126) {
    header = Buffer.from([0x80 | opcode, len]);
  } else if (len < 65536) {
    header = Buffer.alloc(4);
    header[0] = 0x80 | opcode;
    header[1] = 126;
    header.writeUInt16BE(len, 2);
  } else {
    header = Buffer.alloc(10);
    header[0] = 0x80 | opcode;
    header[1] = 127;
    header.writeBigUInt64BE(BigInt(len), 2);
  }
  return Buffer.concat([header, payload]);
}

function wsSend(socket, opcode, payload) {
  if (!socket.destroyed) socket.write(wsFrame(opcode, payload));
}

function handleTunnel(req, socket, strict) {
  pruneAuth();
  const session = sessionOf(req);
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname !== '/tunnel') return socket.destroy();
  if (strict && !wsProtocolOk(req)) {
    noteFail(socket, 'protocol');
    return socket.destroy();
  }
  if (!session) {
    noteFail(socket, 'auth');
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
    return socket.destroy();
  }
  if (!enterUserTunnel(session.xh, socket)) return;
  const host = String(url.searchParams.get('host') || '').toLowerCase();
  const port = Number(url.searchParams.get('port') || 443);
  const target = `${host}:${port}`;
  if (!TUNNEL_TARGETS.has(target)) {
    noteFail(socket, 'target');
    socket.write('HTTP/1.1 403 Forbidden\r\n\r\n');
    return socket.destroy();
  }
  if (!acceptUpgrade(req, socket)) return socket.destroy();

  const tcp = net.connect({ host, port });
  tcp.setNoDelay(true);
  console.log(`tunnel open ${maskId(session.xh)} -> ${target}`);
  let closed = false;
  const close = () => {
    if (closed) return;
    closed = true;
    tcp.destroy();
    if (!socket.destroyed) {
      // 先写入 Close 帧再 end()，让已排队的响应帧刷出；
      // 直接 destroy 会丢掉「响应后立刻断开」的目标站数据。
      wsSend(socket, 0x8, Buffer.alloc(0));
      socket.end();
    }
    console.log(`tunnel close ${maskId(session.xh)} -> ${target}`);
  };

  tcp.on('connect', () => {});
  tcp.on('data', (chunk) => wsSend(socket, 0x2, chunk));
  tcp.on('error', close);
  tcp.on('close', close);
  socket.on('error', close);
  socket.on('close', close);

  let buf = Buffer.alloc(0);
  let frag = Buffer.alloc(0);
  socket.on('data', (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    for (;;) {
      if (buf.length < 2) return;
      const b0 = buf[0];
      const b1 = buf[1];
      const fin = (b0 & 0x80) !== 0;
      const opcode = b0 & 0x0f;
      const masked = (b1 & 0x80) !== 0;
      let len = b1 & 0x7f;
      let off = 2;
      if (len === 126) {
        if (buf.length < 4) return;
        len = buf.readUInt16BE(2);
        off = 4;
      } else if (len === 127) {
        if (buf.length < 10) return;
        len = Number(buf.readBigUInt64BE(2));
        off = 10;
      }
      if (len > 1 << 20) return close();
      if (!masked) return close();
      if (buf.length < off + 4 + len) return;
      const mask = buf.subarray(off, off + 4);
      off += 4;
      const payload = Buffer.alloc(len);
      for (let i = 0; i < len; i++) payload[i] = buf[off + i] ^ mask[i & 3];
      buf = buf.subarray(off + len);
      if (opcode === 0x8) return close();
      if (opcode === 0x9) {
        wsSend(socket, 0xa, payload);
        continue;
      }
      if (opcode === 0xa) continue;
      if (opcode === 0x0 || opcode === 0x1 || opcode === 0x2) {
        frag = Buffer.concat([frag, payload]);
        if (fin) {
          if (!tcp.destroyed) tcp.write(frag);
          frag = Buffer.alloc(0);
        }
      }
    }
  });
}

// ---- 隧道多路复用：一条 WebSocket 承载多条 TCP 流 ----
// 每个 CONNECT 单独握手在公网高延迟下代价很大（日志里 open/close 几乎 1:1），
// 复用一条长连接后，后续请求只需一个 OPEN 帧，不再重复 TLS/WS 握手。
// 帧格式：[type:1][streamId:4][payload]
// 1=OPEN(hostLen:1 + host + port:2) 2=DATA 3=CLOSE 4=PING 5=PONG
function readWsMessages(socket, onMessage, onClose) {
  let buf = Buffer.alloc(0);
  let frag = Buffer.alloc(0);
  socket.on('data', (chunk) => {
    buf = Buffer.concat([buf, chunk]);
    for (;;) {
      if (buf.length < 2) return;
      const b0 = buf[0];
      const b1 = buf[1];
      const fin = (b0 & 0x80) !== 0;
      const opcode = b0 & 0x0f;
      const masked = (b1 & 0x80) !== 0;
      let len = b1 & 0x7f;
      let off = 2;
      if (len === 126) {
        if (buf.length < 4) return;
        len = buf.readUInt16BE(2);
        off = 4;
      } else if (len === 127) {
        if (buf.length < 10) return;
        len = Number(buf.readBigUInt64BE(2));
        off = 10;
      }
      if (len > 1 << 20 || !masked) return onClose();
      if (buf.length < off + 4 + len) return;
      const mask = buf.subarray(off, off + 4);
      off += 4;
      const payload = Buffer.alloc(len);
      for (let i = 0; i < len; i++) payload[i] = buf[off + i] ^ mask[i & 3];
      buf = buf.subarray(off + len);
      if (opcode === 0x8) return onClose();
      if (opcode === 0x9) {
        wsSend(socket, 0xa, payload);
        continue;
      }
      if (opcode === 0xa) continue;
      if (opcode === 0x0 || opcode === 0x1 || opcode === 0x2) {
        frag = Buffer.concat([frag, payload]);
        if (fin) {
          const msg = frag;
          frag = Buffer.alloc(0);
          onMessage(msg);
        }
      }
    }
  });
}

function handleMux(req, socket, strict) {
  pruneAuth();
  const session = sessionOf(req);
  const url = new URL(req.url, 'http://localhost');
  if (url.pathname !== '/tunnel-mux') return socket.destroy();
  if (strict && !wsProtocolOk(req)) {
    noteFail(socket, 'protocol');
    return socket.destroy();
  }
  if (!session) {
    noteFail(socket, 'auth');
    socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
    return socket.destroy();
  }
  if (!enterUserTunnel(session.xh, socket)) return;
  if (!acceptUpgrade(req, socket)) return socket.destroy();

  const streams = new Map();
  const stats = { opened: 0, rejected: 0, up: 0, down: 0 };
  let closed = false;

  const send = (type, id, payload) => {
    if (closed || socket.destroyed) return;
    const head = Buffer.alloc(5);
    head[0] = type;
    head.writeUInt32BE(id >>> 0, 1);
    const frame = payload && payload.length
      ? Buffer.concat([head, payload])
      : head;
    wsSend(socket, 0x2, frame);
  };

  const shutdown = () => {
    if (closed) return;
    closed = true;
    for (const tcp of streams.values()) tcp.destroy();
    streams.clear();
    if (!socket.destroyed) {
      wsSend(socket, 0x8, Buffer.alloc(0));
      socket.end();
    }
    console.log(
      `mux close ${maskId(session.xh)} (streams=${stats.opened}, rejected=${
        stats.rejected
      }, up=${(stats.up / 1048576).toFixed(2)}MB, down=${(
        stats.down / 1048576
      ).toFixed(2)}MB)`
    );
  };

  console.log(`mux open ${maskId(session.xh)}`);
  socket.on('error', shutdown);
  socket.on('close', shutdown);

  readWsMessages(
    socket,
    (msg) => {
      if (msg.length < 5) return;
      const type = msg[0];
      const id = msg.readUInt32BE(1);
      const body = msg.subarray(5);
      if (type === 4) {
        // 应用层心跳：穿过 Cloudflare 保持连接活跃
        send(5, id, Buffer.alloc(0));
        return;
      }
      if (type === 1) {
        const hostLen = body.length >= 1 ? body[0] : 0;
        if (!hostLen || body.length < 1 + hostLen + 2) {
          send(3, id);
          return;
        }
        const host = body
          .subarray(1, 1 + hostLen)
          .toString('utf8')
          .toLowerCase();
        const port = body.readUInt16BE(1 + hostLen);
        const target = `${host}:${port}`;
        if (!TUNNEL_TARGETS.has(target) || streams.has(id)) {
          stats.rejected++;
          send(3, id);
          return;
        }
        const tcp = net.connect({ host, port });
        tcp.setNoDelay(true);
        streams.set(id, tcp);
        stats.opened++;
        let done = false;
        const end = () => {
          if (done) return;
          done = true;
          streams.delete(id);
          tcp.destroy();
          send(3, id);
        };
        tcp.on('data', (chunk) => {
          stats.down += chunk.length;
          send(2, id, chunk);
        });
        tcp.on('error', end);
        tcp.on('close', end);
        return;
      }
      if (type === 2) {
        const tcp = streams.get(id);
        if (tcp && !tcp.destroyed) {
          stats.up += body.length;
          tcp.write(body);
        }
        return;
      }
      if (type === 3) {
        const tcp = streams.get(id);
        if (tcp) {
          streams.delete(id);
          tcp.destroy();
        }
      }
    },
    shutdown
  );
}

/** 挂载 HTTP 处理与 WS 升级；strict 用于国内直连的 TLS 端口。 */
function attach(server, strict) {
  // 慢速连接防护：头部超时即断开，避免被扫描器长期占位
  server.headersTimeout = 10 * 1000;
  server.requestTimeout = 15 * 1000;
  if (strict) {
    server.on('connection', (socket) => {
      if (!guardConnection(socket)) return;
      // 5 秒内连 TLS 握手的第一字节都没发来，直接断开
      const timer = setTimeout(() => {
        if (socket.bytesRead === 0) socket.destroy();
      }, 5000);
      socket.on('close', () => clearTimeout(timer));
      socket.on('error', () => {});
    });
    server.on('tlsClientError', (_err, socket) => {
      noteFail(socket, 'tls');
      socket.destroy();
    });
  }
  server.on('request', (req, res) => {
    handle(req, res).catch((e) => {
      console.error(e);
      send(res, 500, { error: 'internal_error' });
    });
  });
  server.on('upgrade', (req, socket) => {
    try {
      if (strict && !enterSocket(socket)) return;
      const path = String(req.url || '').split('?')[0];
      if (path === '/tunnel-mux') handleMux(req, socket, strict);
      else handleTunnel(req, socket, strict);
    } catch (e) {
      console.error('tunnel upgrade 失败', e);
      socket.destroy();
    }
  });
}

load();
const server = http.createServer();
attach(server, false);
server.listen(PORT, '0.0.0.0', () => {
  console.log(`haipan api listening on :${PORT}, data=${DATA_FILE}`);
});

// 国内直连：只监听 TLS，明文 HTTP 在 8443 上没有任何响应
try {
  const tlsOptions = {
    cert: fs.readFileSync(TLS_CERT),
    key: fs.readFileSync(TLS_KEY),
  };
  const tlsServer = https.createServer(tlsOptions);
  attach(tlsServer, true);
  tlsServer.listen(TLS_PORT, '0.0.0.0', () => {
    console.log(`haipan api TLS listening on :${TLS_PORT}`);
  });
} catch (e) {
  // 证书缺失时仅损失直连通道，Cloudflare 主通道照常工作
  console.warn(`TLS 未启用（${TLS_CERT}）：${e.message}`);
}

