# TCP 隧道：把内网 Web 服务带到公网

> 面向后续维护者：解释海畔 App「校外通道」为什么能把校园网里的教务网页（HTTP/HTTPS）原样搬到手机上，
> 以及如何把同样的机制复用到其他内网 Web 服务（如本地 80 端口的网页）。

## 1. 整体链路

```
手机 App（WebView / Dio）
   │  ① 走本地 HTTP 代理 127.0.0.1:<随机端口>
   ▼
本地 CONNECT 代理（Dart ServerSocket）
   │  ② CONNECT jw.gdou.edu.cn:443
   ▼
隧道 WebSocket（wss:// 或 TLS 自签直连）
   │  ③ 多路复用帧：一个 WS 承载多条 TCP 流
   ▼
NAS 服务端（容器内 :8443 / :8080）
   │  ④ net.connect(目标域名, 端口)
   ▼
校园网内 jw.gdou.edu.cn / authserver.gdou.edu.cn
```

关键点：**隧道只搬运 TCP 字节，不解析 HTTP**。所以 HTTPS、Cookie、验证码、302 跳转、WebSocket
全部保持原样，服务端不需要知道页面内容。

## 2. 两个子机制

### 2.1 本地 CONNECT 代理

- App 启动时在 `127.0.0.1` 上随机端口起一个 `ServerSocket`（`campus_tunnel.dart`）。
- 需要时把 Dio 的 `proxy` 与 WebView 的代理都指向它。
- 收到 `CONNECT host:port` 后校验白名单（只允许 `jw.gdou.edu.cn`、`authserver.gdou.edu.cn` 的 80/443），
  再向隧道申请一条新流。

### 2.2 多路复用（mux）

- 一条 WebSocket 可以同时承载多条 TCP 流，避免每次点击都重新握手。
- 帧格式：`[type:1][streamId:4][payload:N]`
  - `type=1`：打开流（payload 为目标 `host:port`）
  - `type=2`：数据（双向共用）
  - `type=3`：关闭流
- 20 秒心跳；服务端对每条流做目标白名单校验，越权直接拒绝并计入风控。

## 3. 为什么"HTTP 代理"能转发 HTTPS

CONNECT 是 HTTP 协议里专门为隧道设计的动词：客户端说"帮我把到 host:443 的 TCP 连起来"，
代理回 `200 Connection Established` 后，双方只转发原始字节。TLS 握手发生在手机和教务服务器之间，
**端到端加密**，中间任何一跳（App 本地代理、隧道服务端、frp 节点）都看不到明文，
也无法替换证书——客户端还会做证书指纹固定（`tls_pin.dart`）。

## 4. 传输层：TLS over TCP

| 入口 | 形式 | 说明 |
|---|---|---|
| 国内直连 | `https://IP:高位端口` | 阿里云/MeFrp/其他 frp 的 TCP 透传 → NAS:18443；自签 EC 证书，客户端按 SHA-256 指纹固定 |
| Cloudflare | `https://api.example.com` | WSS 经 CF 边缘；证书由 CF 签发，指纹固定逻辑自动跳过 |

服务端 `:8443` 只接受 TLS，明文 HTTP 打到该端口不会有任何响应；WebSocket 必须带固定子协议 `haipan-v1`，
再加 Bearer 会话令牌，三者缺一不可。

## 5. 与 HTTP 反向代理的差别

| | HTTP 反向代理（Nginx/CF） | TCP 隧道（本项目） |
|---|---|---|
| 能否转发 HTTPS 业务 | 需要终止 TLS，证书、Cookie 域、重定向都要改 | 原样透传，零改造 |
| 能否转发非 HTTP 协议 | 不能 | 能（任意 TCP，如数据库、SSH） |
| 服务端能否看到内容 | 能 | 不能（端到端加密） |
| 对客户端要求 | 无 | 需要装客户端/代理 |

## 6. 复用：本地 80 端口的 Web 页面

可以，且不需要改协议，只需两步：

1. 在服务端白名单里增加目标（例如 `192.168.6.x:80` 或 `127.0.0.1:80`），仍然是 `CONNECT`。
2. 客户端把浏览器的 HTTP 代理指向本地代理端口（Android WebView 可设置；桌面浏览器直接填代理）。

注意：

- 明文 HTTP 没有加密，隧道段虽然有 TLS，但**内容在服务端之后是明文**；只建议内网/可信环境使用。
- 若页面用绝对地址跳转或依赖域名，需要保证手机侧能解析该域名（必要时加 hosts 或用 IP 访问）。
- 若目标服务只监听 `127.0.0.1`，请在服务端所在机器上放行，或做端口转发到可达地址。

## 7. 三条 TCP 通道能否替代 HTTP（Cloudflare）通道？

**能力上可以。** 三条 TCP 通道最终都进同一个 NAS 端口，提供完全相同的 API 与教务隧道；
客户端只按入口列表切换，协议层没有差别。实测（2026-11-24，本机）：

| 通道 | 延迟 | 带宽 |
|---|---|---|
| 东莞 MeFrp | ~0.09s | ≈12Mbps（硬上限） |
| 深圳 frp | ~0.11s | 80–110Mbps（实测） |
| 阿里云 MeFrp | ~0.29s | — |
| Cloudflare | ~0.92s | — |

建议保留 Cloudflare 作为跨供应商兜底：

- 两条 TCP 通道同属免费 frp 生态，同源故障时会一起不可用；
- 新装 App 的引导入口仍需一个可用地址（现由云端「默认入口」下发，但首次启动前拿不到配置）。

## 8. 局限

- 只支持 TCP；UDP/QUIC/WebRTC 不适用。
- 免费 frp 有流量额度（东莞 10GB 量级），且高峰期可能抖动；额度耗尽表现为连不上，客户端会自动回退。
- 服务端看到的所有连接源地址都是内网/回环（docker-proxy/隧道转发），因此按 IP 的风控只保留
  抗洪水阈值，不做封禁（见 `server.js` 的 `isSharedSource`）。
