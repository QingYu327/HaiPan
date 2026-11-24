# 海畔（jw_app）修改记录

> 本文件记录历次代码修改，避免因上下文压缩丢失改动信息。

> **记录规范（每次改动必填）**
> 1. 日期 + Batch 号 + 一句话主题；
> 2. 范围与涉及文件（客户端 / 原生 / 后端 / 部署）；
> 3. 关键决策与原因（为什么这样做，而不只是做了什么）；
> 4. 验证：`flutter analyze`、`flutter test`、`node --check`、构建号、真机安装；
> 5. 部署：后端是否已上 NAS、验证命令与结果；
> 6. 遗留问题与下一步。
> 新批次写在最上方（最新在前）。

## 2026-11-24 · Batch42：自查高优先级修复（设备换绑保护 / 退出登录冷启动 / 学期回退上限）（build 4094）

### 1. 原因
- `/device/register` 允许任意人用白名单学号覆盖公钥并踢掉原会话，从而冒用隧道；白名单学号曾出现在公开仓库。
- 主动退出登录只删学籍缓存、保留学号，冷启动按「有学号即已登录」进主页，再弹「登录失效」。
- 成绩/考试学期无数据时无限自动回退，教务持续返回空会连打接口并停留在多年前的旧学期。

### 2. 改动
- `backend/server.js` `/device/register`：已绑定学号换公钥默认拒绝，返回 409 `device_mismatch`（文案「该学号已绑定其他设备，请联系管理员重置」）；换机由管理员 `POST /perm {action:'resetDevice'}` 处理。自建部署可用 `ALLOW_DEVICE_REBIND=1` 恢复自动换绑（旧会话失效）。
- `jw_app/lib/providers/session_provider.dart`：新增 `jw.logged_out` 标记；`logout()`/`resetForRepair()` 置 true，登录成功置 false；`_restore()` 见 true 直接进登录页（学号仍保留用于回填），不再走缓存优先进主页。
- `jw_app/lib/ui/widgets/common.dart`：`autoFallbackTerm` 增加每作用域最多 2 次连续回退上限；`resetAutoFallback()` 在成绩/考试有数据时清零；手动选学期时也清零。
- `jw_app/lib/ui/grade/grade_page.dart`、`exam_page.dart`：数据非空时调用 `resetAutoFallback`。

### 3. 验证
- `flutter analyze` 无问题；`flutter test` 3/3；`node --check backend/server.js` 通过。
- arm64 构建 4094 → `C:\Users\Lime\Desktop\海畔_4094.apk`（手机未连接未装机）。
- 未实测：换绑 409（需在 NAS 部署新 server.js 后验证）、退出登录后冷启动（需真机安装后走一次退出+强杀）。

### 4. 部署
- 后端改动需在 NAS 重新 `docker compose up -d --build` 才生效；部署后旧设备若已换绑过不受影响。

### 5. 遗留（自查未修）
- `/tunnel/endpoints` 公开可读，云端入口下发未做签名校验；TLS 固定指纹对公共 CA 无约束。
- 隧道启用后不回落直连；mux OPEN 绕过单学号并发上限；resetDevice 不吊销已有会话。
- 导入弹窗/加载遮罩无条件 `nav.pop()`；上课提醒比设定早约 55 分钟；提醒 id 每小时重排导致旧通知点击被忽略。
- `academicProvider` 缓存未校验当前学年学期；日志每条重写整文件、mask 偏宽。

## 2026-11-24 · Batch41：反馈页精简 + 日志自动导出为附件；考试卡提亮；教室标签统一（build 4093）

### 1. 原因
- 反馈页说明文字过多、灰色小字噪音大；用户实际最需要的是「把日志一起发来」，手动附加容易漏。
- 考试卡的考试时间/地点/类型与课表信息混在一起，剩余天数不够显眼。
- 教室「不可借用」已足够表意，额外解释反而增加阅读负担。

### 2. 改动
- `lib/ui/profile/feedback_page.dart`（整体重写，StatefulWidget）
  - 只保留一张提示卡：「请务必附上日志：点击下方按钮会自动导出运行日志，并作为附件填入邮件。」其余灰色小字全部删除。
  - 反馈内容只给一份「信息描述模板」（问题描述/复现步骤/预期结果/实际结果/发生时间/所在页面/应用版本/手机型号与系统），配可选中文本 + 复制按钮。
  - 主按钮改为「导出日志并发送邮件」：先 `AppLog.exportForFeedback()` 导出脱敏日志，再走原生 `sendFeedbackMail` 拉起 `ACTION_SEND`（`message/rfc822` + `EXTRA_STREAM` + FileProvider），日志自动作为附件；失败退回 `openMailto`，再失败提示复制邮箱手动发送。
- `lib/util/app_log.dart`：新增 `exportForFeedback()`，导出到应用私有 `files/`，文件名 `haipan-feedback-<yyyyMMdd-HHmmss>.txt`，导出前清理同前缀旧文件；头部写入导出时间与日志条数。
- `android/.../MainActivity.kt`：`cn.gdou.xiuhong/app` 通道新增 `sendFeedbackMail`（收件人/主题/正文/附件路径），`FileProvider.getUriForFile` + `FLAG_GRANT_READ_URI_PERMISSION` + `createChooser`；无处理方返回 `false` 由 Flutter 兜底。
- `lib/ui/exam/exam_page.dart`
  - 卡片行改为带标签的 `考试时间：`、`考试类型：`、`考试地点：`（校区 · 教室）、`教学地点：`、`考试方式：`，重点项用 `tsBodyStrong` + primary 色图标提亮。
  - 新增 `_CountdownBadge`：剩余天数用 24 号加粗数字 + 「天后」小字；当天显示「今天」；0 天 danger、≤7 天 warning、其余 info；无日期显示「未公布」、已结束显示「已结束」并整卡 `Opacity(0.55)`。
- `lib/ui/profile/favorite_rooms_page.dart`：标签 `'不可借'` → `'不可借用'`，删除「教务标记该教室不可借用（不等于被占用）」解释块。

### 3. 验证
- `flutter analyze`：No issues found；`flutter test`：3/3 通过。
- 模拟器（x64，build 4092 同源代码）：反馈页点按钮成功生成 `/data/data/cn.gdou.xiuhong/files/haipan-feedback-20261124-132933.txt`（2076B，含脱敏日志 22 条），系统分享面板显示「正在分享 1 个文件」及 Gmail/云端硬盘；考试页截图确认加粗高亮与倒计时配色（6 天琥珀、21 天蓝、已结束置灰）。
- 构建：arm64 22.6MB → `C:\Users\Lime\Desktop\海畔_4093.apk`。
- 注：本次构建时手机未连接（`adb devices` 只有 emulator-5554），未执行真机安装；安装包已放桌面待手动/连线安装。

### 4. 遗留
- 反馈邮件附件依赖系统邮件客户端对 `EXTRA_STREAM` 的支持（Gmail/内置邮件正常）；个别客户端可能丢弃附件，已在正文注明「日志文件：见附件」并保留手动附加提示。
- 系统邮件客户端在后台发送失败时无回执，用户可能误以为已发送；后续可考虑改用后端 SMTP 直发（需在 NAS 配置发件账号）。

## 2026-11-24 · Batch40：意见反馈支持一键打开邮件客户端（build 4090）

### 1. 原因
- Batch39 只提供可复制模板，用户仍需手动打开邮箱、新建邮件、粘贴内容。

### 2. 改动
- `feedback_page.dart` 增加「打开邮件客户端」主按钮：拼接 `mailto:`（收件人 + 主题 + 正文预填，中文与换行做 percent-encoding）。
- `MainActivity.kt` 的 `cn.gdou.xiuhong/app` 通道新增 `openMailto`：`ACTION_SENDTO` + try/catch；无邮件应用时返回 `false`，Flutter 侧提示「未找到邮件客户端，请复制邮箱后手动发送」。
- 未引入 `url_launcher`：其 6.3.2 传递的 androidx.browser/core 1.17 强制要求 compileSdk 36（插件自身仍按 35 编译会直接失败），故改用原生通道，`compileSdk` 保持 35。
- `AppIcons` 新增 `mail` 图标。

### 3. 验证
- `flutter analyze` 无问题；`flutter test` 3/3 通过。
- 模拟器：点按钮成功拉起 Gmail（WelcomeTourActivity），应用进程存活、无 FATAL。
- 手机（23127PN0CC / arm64）：安装 4090 冷启动正常，无 FATAL。
- 构建：x64 24.0MB（模拟器）、arm64 22.6MB（`桌面\海畔_4090.apk`，已用 adb 推送手机）。

### 4. 遗留
- mailto 正文依赖客户端对长 URI 的处理，个别老客户端可能截断；已保留逐段复制作为兜底。

## 2026-11-24 · Batch39：意见反馈改为邮件（独立页面 + 可复制模板，build 4089）

### 1. 原因
- 公众号二维码反馈依赖扫码与人工转发，链路长；改为直接发邮件，反馈内容更完整、可追溯。

### 2. 改动
- 新增 `lib/ui/profile/feedback_page.dart`：独立「意见反馈」页，含
  - 反馈邮箱 `xiuhong0327@163.com`（可选中、支持「复制邮箱」）；
  - 邮件主题模板：`【海畔反馈】问题简述 - 学号`（可复制）；
  - 反馈内容模板：问题类型 / 发生时间 / 所在页面 / 操作步骤 / 预期与实际 / 补充说明 / 应用版本 / 机型系统（可复制，版本号自动取 `appVersion`）；
  - 顶部说明卡与底部隐私提示（勿发送密码、截图可打码）。
- `profile_page.dart`：删除公众号二维码弹窗 `_showFeedback`，入口改为进入 `FeedbackPage`。
- 移除不再使用的 `assets/feedback_qr.jpeg` 及 pubspec 资源声明；同步 `jw_app/INDEX.md`。

### 3. 验证
- `flutter analyze`：No issues found；`flutter test`：3/3 通过。
- 模拟器（x86_64）安装 4089 冷启动 → 我的 → 意见反馈：页面渲染正常，邮箱/主题/正文三段完整；点「复制邮箱」出现「邮箱已复制」提示；底部提示卡与留白正常，无闪退。
- arm64 release 4089 构建通过（22.6MB），产物 `桌面\海畔_4089.apk`。

### 4. 遗留
- 未提供「一键跳转邮件客户端」（需 url_launcher 与邮箱 app 适配），当前为复制后手动发送；如需可后续加 `mailto:` 按钮。（Batch40 已用原生 `openMailto` 补上）

## 2026-11-24 · Batch38：全链路回归 + 无效代码清理（build 4088）

### 1. 原因
- 连续几批改动（TLS 直连、共享源风控、云端默认通道、导入弹窗）后需要一次完整回环验证。
- 静态检查无法发现跨文件「声明了但全项目没人用」的公开符号，需人工/脚本复核后瘦身。

### 2. 清理项
- 客户端 `ServerConfig.loaded`：写入后全项目无读取，删除字段与赋值。
- 客户端 `InkContext.theme` 扩展 getter：全项目 0 处使用，删除（`scheme/ink/isDark/tabular` 保留）。
- `pubspec.yaml` 移除未使用的 `cupertino_icons`（无任何 import，`pub get` 后依赖链少一项）。
- `AndroidManifest.xml` 的 `android:label` 改为 `@string/app_name`，避免 `app_name` 字符串资源成为死资源。
- 复核结论：Dart 侧无未被导入的文件、模型字段全部有读取；Kotlin 侧无未调用函数/常量；服务端无未使用函数/常量；res 下 drawable/layout/xml 均有引用，无需删除。

### 3. 验证
- `flutter analyze`：No issues found。
- `flutter test`：3 项全部通过（课程色板/语义色/间距圆角）。
- 服务端端到端回归（临时目录 + 临时端口 18083/18446，独立数据卷，结束后清理）27/27 通过：
  - 健康检查、入口列表首位国内直连且 `default` 唯一；管理员可改云端默认入口并回读；
  - 设备登记（白名单外 403）、挑战码一次性、错误签名/重放 401、会话访问 `/gates`、`/permission`、学号上报与管理员名单、备注读写；
  - TLS 端口拒绝明文 HTTP、缺子协议被拒、坏令牌 401；
  - 共享源（127.0.0.1）在 12 次越权目标 + 35 次坏令牌后仍可正常握手（不被连坐封禁）；
  - mux 握手 101、OPEN/DATA 收到上游响应 444 字节、关闭日志含 `up/down`；同学号 1~4 条 101、第 5 条 429、释放后可重连；越权目标回 CLOSE 帧并计入 `rejected`。
- `flutter build apk --release --target-platform android-arm64 --build-number=4088` 通过（22.7MB），产物 `桌面\海畔_4088.apk`。
- 模拟器（x86_64）安装同版本 x64 包，冷启动进入课表主界面，无闪退/白屏，logcat 无 FATAL。

### 4. 遗留
- 通知在划掉后台后不触发（需真机按 `notifyStatus` 判断是否被 ROM 清闹钟）。
- 按学号加权分流（深圳 4/5、东莞 1/5）尚未实现。
- mux 字节统计以 MB 保留两位小数，小流量显示 0.00MB，如需精细观测可改为 KB 单位（不影响功能）。

## 2026-11-24 · Batch37：云端默认通道 / 首屏导入弹窗 / 教室状态标签修正（build 4087）

### 1. 原因
- 默认入口写死在客户端，换优质线路必须重新发版。
- 登录后只在角落转圈，等待过程不明确。
- 空教室列表把「教务标记不可借」误显示为「占用」，与收藏详情的「空闲」结论矛盾。

### 2. 改动
- 服务端 `tunnelEndpoints()` 每条返回 `default` 标记；`POST /tunnel/endpoints` 支持 `default` 字段并持久化到 `cfg.defaultTunnel`。
- 客户端 `ServerConfig` 增加 `cloudDefault`：未手动选过入口时采用云端默认；云端默认可达时自动选路不再切走；手动切换会写入 `server.user_choice` 长期优先。
- 通道页新增「设为云端默认」（右键菜单），列表条目显示「云端默认」；下发时一并提交默认入口。
- `HomeShell` 新增导入进度弹窗：登录后权限校验/课表拉取超过 400ms 才弹出，按「校验访问权限 → 导入课表 → 准备其他数据」逐项显示，完成自动关闭。
- 空教室列表标签改为「空闲 / 不可借」，收藏详情在 `sfkjy=否` 时补充「不可借但非占用」说明。
- 新增技术文档 `docs/tcp_tunnel.md`（TCP 隧道原理、CONNECT/mux、与 HTTP 反代差异、本地 80 端口复用、能否替代 CF）。

### 3. 验证
- `flutter analyze` 无问题；`flutter build apk --release --target-platform android-arm64 --build-number=4087` 通过（22.8MB），产物 `桌面\海畔_4087.apk`。
- 服务端已重建部署，`/tunnel/endpoints` 返回 `default` 标记（当前默认=国内直连，可在 App 通道页改）。

### 4. 遗留
- 通知在划掉后台后不触发：AlarmManager 与进程无关，需真机按 `notifyStatus` 诊断是否被 ROM 清闹钟/冻结；候选方案为前台服务或定期自愈。
- 按学号加权分流（深圳 4/5、东莞 1/5）尚未实现。

## 2026-11-24 · Batch36：通道实际带宽/容量实测 + 会话流量统计

### 1. 服务端
- `handleMux` 关闭日志增加 `up/down` 字节数（按会话统计真实隧道流量，用于评估 MeFrp 免费额度够多少人用）。
- 临时增加 `/bench` 测速接口（仅 `BENCH_TOKEN` 存在时可用）完成实测后已删除，当前访问返回 401。

### 2. 实测（本机 → 各通道，2026-11-24）
- 单流 8MB：深圳 34.7Mbps；东莞 12.1Mbps。
- 单流 4MB：深圳 84Mbps；2 并发合计 97Mbps；4 并发合计约 110Mbps。
- 东莞 4 并发合计 11.1Mbps（≈10Mbps 硬上限，多流只分摊不叠加）。
- 延迟（10 次）：东莞 0.092s、深圳 0.106s、阿里云 0.288s、CF 0.918s。
- 深圳节点首次 4 并发曾整体连不上（约 21s 超时），重测正常，判断为节点瞬时抖动/并发保护。

### 3. 结论
- 东莞 10GB 额度按每用户每日 5–10MB 估算，仅够 30 人用一个月（重度 10 人）；只适合分流/备用。
- 深圳 1TB 足够百人级长期使用。
- 当前客户端“选延迟最低”会让所有用户都落到延迟更低的东莞（0.092s < 0.106s），额度风险高；建议后续按学号哈希做加权分流（深圳 4/5、东莞 1/5），失败再回退。

## 2026-11-24 · Batch35：国内直连通道（阿里云 TCP 穿透 + 自签 TLS）全容器化（build 4086）

### 1. 原因
- 国内访问 Cloudflare 边缘（`172.67/104.21`）绕路且不稳定；阿里云未备案域名会拦截，HTTPS 报 525、HTTP 404，国内节点域名方案走不通。
- 目标：一条不依赖域名备案、不走境外边缘的直连通道，作为入口列表首选。

### 2. 服务端（`backend/server.js`）
- 新增 HTTPS 监听 `TLS_PORT`（默认 8443），与 8080 共用同一套 `handle` 与 WS 逻辑；证书从 `$DATA_DIR/tls/{cert,key}.pem` 读取，缺失时只告警、不影响 Cloudflare 主通道。
- 直连端口启用 `strict` 防护（仅该端口）：
  - 每 IP 每分钟新建连接上限 120（只防扫描洪水，正常使用远低于阈值）；
  - 并发隧道**按学号**限制 4 条，按 IP 只留 64 条总量上限——校园网/运营商 NAT 下多人共享同一公网 IP，按 IP 限并发会误伤；
  - 失败分两档：越权目标/子协议不符属扫描特征，8 次拉黑；未认证（令牌过期）、TLS 握手失败阈值 30 次；两档均在 10 分钟无新增失败后自动清零，避免弱网历史事件累计误封；
  - WS 必须带固定子协议 `haipan-v1`（普通浏览器与扫描器握手不成立）；5 秒内未发出 TLS 首字节、10 秒未完成头部一律断开；
  - 明文 HTTP 打到 8443 不返回任何 HTTP 响应（实测 `curl: (52) Empty reply`）。
  - **共享源识别**：所有公网用户都经隧道/Cloudflare → 宿主机端口 → docker-proxy 进容器，容器看到的源地址统一是回环/内网，无法区分个体。这类地址（`isSharedSource`）关闭失败封禁、连接限速放宽到 600/min、并发放宽到 256 条，只断超限的那一条；否则一个扫描器就能把全体用户连坐封禁 10 分钟。真实公网 IP 仍按原阈值处理。
- `/tunnel/endpoints` 首位固定下发 `DIRECT_TUNNEL`（默认 `https://203.0.113.10:48644`，名称「国内直连」），其余管理员配置按序去重后追加。
- 101 握手在客户端声明子协议时回显 `Sec-WebSocket-Protocol`（Dart 侧缺该响应头会判定握手失败）。

### 3. 部署（干净容器化）
- 证书用一次性容器生成并持久化到数据卷，不写入镜像（重建镜像不会改变指纹）：
  `docker run --rm -v .../data/tls:/tls docker.m.daocloud.io/alpine/openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 ... -days 3650`
  证书 `CN=haipan-tunnel`，SAN 含 `IP:203.0.113.10`，有效期至 2036-11-21。
- `docker-compose.yml` 增加 `18443:8443` 与 `TLS_PORT`/`DIRECT_TUNNEL`；`Dockerfile` `EXPOSE 8080 8443`。
- 阿里云 TCP 穿透 `203.0.113.10:48644` 指向 NAS `18443`；备份 `server.js.bak-before-tls`、`docker-compose.yml.bak-before-tls` 后 `docker compose up -d --build`。

### 4. 客户端
- 新增 `lib/util/tls_pin.dart`：只信任固定 SHA-256（DER）指纹，`TlsPin.check` 供 `badCertificateCallback`，`TlsPin.client()` 供一次性请求，`TlsPin.shared()` 供 WebSocket 长连接；系统 CA 正常证书不走该回调，Cloudflare 通道不受影响。
- `server_config.dart`：入口测速与配置同步改用固定指纹客户端，直连入口可正常 `GET /health`。
- `campus_tunnel.dart`：两处 `WebSocket.connect` 增加 `protocols: ['haipan-v1']` 与 `customClient: TlsPin.shared()`。
- `usage_api.dart`：`_plain` 改用 `IOHttpClientAdapter(createHttpClient: TlsPin.client)`，设备注册/挑战/验签与所有带令牌请求均可走直连。

### 5. 验证
- `node --check backend/server.js` 通过；`flutter analyze` No issues found；`flutter test` 3 项通过。
- 本机对全新 server.js 起沙箱（临时 `DATA_DIR` + 同证书）跑 8 项端到端：TLS `/health` 200、endpoints 首条为直连、EC 挑战签名换令牌、mux 101 且回显子协议、应用层 PING/PONG、缺子协议被拒、错误令牌 401、明文 HTTP 无响应 —— 全部 PASS。
- 线上：`curl -k https://203.0.113.10:48644/health` → 200（约 0.29s）；本地 `curl -k https://192.168.1.10:18443/health` → 200；公网取回证书指纹 `7392fdcb…57e877` 与生成值一致，`CN=haipan-tunnel` 说明中间无 TLS 卸载。
- 构建：`flutter build apk --release --target-platform android-arm64 --build-number=4086`。

### 6. 遗留
- 证书轮换（2036 前）必须同步改 `TlsPin.fingerprints` 并重新发版，否则旧包直连失效、自动回退 Cloudflare 通道。
- 阿里云穿透未绑定域名，直接暴露 IP:高位端口，靠上述限频/拉黑/子协议降低被扫描价值；如后续有备案域名，可改为域名 + 受信任证书并移除指纹固定。

## 2026-11-24 · Batch34：作息时间按课表校正 + versionCode 对齐构建号（build 4085）

### 1. 作息时间（按教务处课表原文逐节校正）
原先是「每两节合并成一个大节、只记大节起止」，其中 3-4 节起点 10:05、7-8 节起点 16:25、3-4 节终点 11:35、7-8 节终点 17:55 与课表不符。

校正后（逐节）：

| 节次 | 起止 | 节次 | 起止 |
|---|---|---|---|
| 1 | 08:10-08:55 | 6 | 15:20-16:05 |
| 2 | 09:00-09:45 | 7 | 16:30-17:15 |
| 3 | 10:15-11:00 | 8 | 17:20-18:05 |
| 4 | 11:05-11:50 | 9 | 19:30-20:15 |
| 5 | 14:30-15:15 | 10 | 20:25-21:10 |

- 课表左栏改为**逐节**显示（1~10 各占一行，各显示本节起止），与教务处课表排版一致；不再两节合并。
- 课程时间、下一门课提示改为按实际起止节取时间（跨大节的课不再被拉长）。
- 上课提醒、桌面小部件同步改为新的大节开始时间（3-4=10:15、7-8=16:30）。

涉及文件：`lib/ui/timetable/timetable_page.dart`、`lib/util/lesson_notifier.dart`、`android/.../ScheduleWidgetBase.kt`。

### 2. versionCode 与构建号不一致
- 现象：构建号 2083 的包装到真机后 `versionCode=4083`。
- 原因：Flutter 对单 ABI 构建默认追加 ABI 偏移（arm64 为 `2 * 1000`），即 `versionCode = 构建号 + 2000`。
- 处理：`android/gradle.properties` 增加 `force-version-code-ignoring-abi=true`，此后 `versionCode` 严格等于 `--build-number`。
- 构建号从 **4084** 起继续递增（大于真机已装的 4083，保证可覆盖升级），`aapt dump badging` 校验 `versionCode` 与构建号一致。

### 3. 验证
- `flutter analyze`：No issues found；`flutter test`：3 项通过。
- 构建：`flutter build apk --release --target-platform android-arm64 --build-number=4085`，产物 22.7MB，`versionCode='4085'`，已复制为桌面 `海畔_4085.apk`。
- 真机安装：USB 连接中断（`adb devices` 为空），待重连后安装验收；4084 已由用户自行安装，可见左栏两节合并的旧排版（本批已改为逐节）。

## 2026-11-24 · Batch33：学号验证失败文案分层 + 名单内自动重绑（build 2083）

### 1. 问题
- 名单内学号清空应用数据后，Keystore 生成新密钥，服务端 `/device/register` 返回 `409 device_mismatch`，客户端统一显示“校园通道连接失败”，看起来像网络问题。
- 实测确认：`2024********`（白名单内、已绑定旧公钥）用新公钥登记返回 409。

### 2. 改动
- 客户端 `usage_api._authenticate`：全部入口失败时保留服务端原始 `DioException` 上抛。
- 客户端 `sso_login_page`：设备认证与建隧道拆成两段错误处理；4xx 显示“学号验证失败（未加入白名单 / 已绑定其他设备）”，只有超时/断网才显示“校园通道连接失败”。
- 服务端 `/device/register`：公钥不一致不再 409，名单内学号直接覆盖旧绑定，并删除该学号全部旧会话（同一学号单设备生效）；管理页重置能力保留。

### 3. 部署与验证
- 上传 `backend/server.js` 到 NAS，`docker compose up -d --build` 重建容器；`/health` 正常。
- 用临时公钥登记 `2024********` 返回 200（旧会话失效），随后用原公钥登记恢复绑定，状态文件确认已还原。
- `flutter analyze` 无问题、`flutter test` 通过，构建 2083。
- 端到端（Pixel_7_API36，清空数据后安装 2083，仅移动数据 5G）：
  - 未白名单学号 `999999999999` → `[E] [通道] 学号验证失败`（403），界面文案「学号验证失败：该学号未加入白名单」，不再显示“连接失败”。
  - 白名单学号 `2024********` → 1 秒内 `设备认证成功`（说明 `/device/register` 走自动重绑返回 200）→ `复用隧道已连接` → 认证页完整渲染出账号密码表单；服务端日志同步出现 `device rebind 20********02`。
  - 结论：清空 App 后名单内学号可自动重绑并通过握手，无需管理员介入。

## 2026-11-24 · Batch32：代码瘦身清理 + 模拟器陌生网络烧机（build 2082）

### 1. 清理（行为不变）
- Dart 未用 API：`AppLog.preview/readAll`、`ServerConfig.tunnelUrl`、`SettingsNotifier.setLocale`、`RankResult.findMe`、`GradeComponent.scoreNum`、`AcademicCategory.inProgressCredit`、`AcademicCategoryStat.missingCredit`、`JwClient.hasCookie`、`InkNotice.dismiss`、`WebViewProxy.clear`、`InkNavSpacer`、`InkContext.textStyles`、`InkTextContext.tsMicro/tsNano/tsNumber/cardPadding`。
- `app_icons.dart`：删除 16 个从未引用的图标（expandLess/account/password/visibilityOn/visibilityOff/openInNew/history/calendar/play/textSize/darkMode/privacy/help/wifi/sync/grid）。
- Kotlin：删除 `NotificationHelper` 未使用的 id 区间常量（LESSON_BASE/MAX、EXAM_BASE/MAX）与 `MainActivity` 的 `HaipanWidget` 调试日志。
- `main.dart`：移除启动时的临时「提醒诊断」调用（调试页仍可手动诊断）。
- 工作区：删除根目录 4 张测试截图（deep_cold/deep_warm/deep_lesson2/pin_test）。
- 陈旧注释：`sso_login_page.dart` 中关于 wfw 的说明同步为当前方案。

### 2. 烧机（Pixel_7_API36，关 Wi-Fi / 开移动数据，状态栏 5G）
- 17:12:07 检测到移动数据 → 直接走校外通道；填学号完成设备认证。
- 17:13:16 设备认证完成 → 本地代理就绪；17:13:17 mux 连接成功；17:13:26 认证页开始加载，40s 内完整渲染，无错误遮罩。
- 游客态：课表/成绩/考试显示登录引导，我的页正常，五个页签无红屏、无崩溃。
- 17:22 提交账号密码 → 学校判「非可信客户端」，弹出多因子认证页（企业微信验证码）；完成该步后 17:23:19 `统一身份认证登录成功`，探针「已登录」。
- 登录后数据全部 200：课表 43 门、考试 8 场、学籍、统计上报；提醒排 55 条（含当天 19:20 的课）。
- 冷启动：复用本地会话（剩余 904s）、后台握手成功、首页直接进课表、准入在线校验 2ms。

### 3. 烧机发现并修复
- 检查更新 404：GitHub 仓库没有 Release 时 `releases/latest` 返回 404，原实现把英文 DioException 直接展示在页面上；现在 404 按「无更新」处理。
- 学业空缓存：游客态会把「无数据」写进 30 分钟缓存，登录成功后学业页仍显示“暂无学业数据”（需手动下拉）。现在登录成功时清掉 `cache_academic*` 再重建该 provider。

### 4. 验证
- `flutter analyze --no-fatal-infos`：No issues found。
- `flutter test`：3 项通过。
- `flutter build apk --release --split-per-abi --build-number=2082`；arm64 产物复制为 `桌面\海畔_2082.apk`，x86_64 安装到模拟器完成上述全链路。

### 5. 遗留
- 模拟器/新设备登录会触发学校多因子认证，需人工填企业微信验证码；App 内 WebView 已能正常承载，无客户端改动需求。

## 2026-11-24 · Batch31：按网络类型选路——移动数据直接走校外通道（build 2081）

### 1. 需求
- 检测到移动数据时直接走校外通道，不要先撞一次 jw 直连失败；有 Wi-Fi/有线时才尝试直连（可能是校园网）。

### 2. 改动
- 新增 `lib/util/network_info.dart`：`NetworkInfo.isCellularOnly()` 经 MethodChannel 读原生网络类型，取不到时按“可直连”处理。
- `MainActivity.kt`：新增 `cn.gdou.xiuhong/net` 通道，`networkType` 返回 `wifi / cellular / ethernet / other / none`（`ConnectivityManager.activeNetworkInfo`）。
- `AndroidManifest.xml`：新增 `ACCESS_NETWORK_STATE` 权限。
- `sso_login_page.dart`：`_prepare()` 先判断网络，`cellular` 时直接 `_enableTunnel()`；否则维持原逻辑（直连 jw，8s 无进展再切隧道）。

### 3. 登录方案定型（wfw 结论）
- wfw 反代页**只适合打开登录页**：GET 页面与静态资源能改写，但登录 POST 会被弹回登录页、页签仍是 authserver 绝对地址、且无错误提示。
- 因此 wfw 不作为登录入口；校外统一用「隧道 + authserver 原始登录页」，`jw` 与 `authserver` 都在反向 bypass 内。

### 4. 验证
- `flutter analyze --no-fatal-infos`：No issues found。
- build 2081（arm64）已产出；USB 未连接，未自动安装。

## 2026-11-23 · Batch30：校外登录真机打通，恢复「校内直连优先」正式流程（build 2080）

### 1. 真机验证（2079 日志）
- 22:58:57 隧道就绪 → 22:59:08 authserver 登录页开始加载（首包约 11s，40s 超时下不再被打断）；
- 23:05:37 CAS 回跳到 `jw.gdou.edu.cn/xtgl/index_initMenu.html`，`会话: 统一身份认证回填 Cookie：2 个`；
- 23:05:52 `会话: 统一身份认证登录成功`，登录态探针「已登录」；
- 23:06:01–18 数据全部 200：课表 43 门、考试 8 场、个人信息、统计上报。

### 2. 改动
- 删除临时的「强制先走隧道」开关：恢复 **校内直连 jw 优先，失败/超时（8s）再建隧道打开 authserver 登录页**。
- 隧道加载超时保持 40s；wfw 入口与其兜底逻辑已在 Batch29 移除。
- `MainActivity.kt` 反向 bypass 保持 `jw` + `authserver`。

### 3. 验证
- `flutter analyze --no-fatal-infos`：No issues found。
- build 2080（arm64）已产出；USB 未连接，未自动安装。

### 4. 遗留
- 检查更新接口返回 404（`更新: 检查更新失败 ... status code of 404`），与登录无关，后续单独处理。

## 2026-11-23 · Batch29：放宽隧道登录页超时到 40s，移除 wfw 兜底（build 2079）

### 1. 现象（2078 真机日志）
- 22:50:11 隧道就绪并 `loadRequest(authserver 登录页)`；
- 22:50:15 才建立第一条 authserver 隧道连接，22:50:22 才 `onPageStarted`（首包约 11s）；
- 22:50:22 同时建立 5 条 authserver 连接（页面静态资源）；
- 22:50:26 触发 15s 超时 → 自动切 wfw 网关，页面被中途替换；随后 wfw 页面上三次提交又都被弹回。

### 2. 诊断
- 从 NAS 直接 curl 三个域名：`authserver 200 / 67ms`、`jw 302 / 88ms`、`wfw 200 / 55ms`，隧道出口网络完全正常。
- 结论：不是通道不通，而是 WebView 经本地代理首次加载整页（几十个资源）耗时较长，15s 上限把还在加载的页面判了超时；wfw 反代页的登录提交又不可靠。

### 3. 改动（`sso_login_page.dart`）
- `_armTunnelTimeout`：15s → **40s**，避免登录页还在加载就被切走。
- 删除 wfw 入口与 wfw 兜底分支（`_wfwEntry`、`_wfwTried`），统一只用 authserver 原始页；超时/失败只做原地重试（最多 2 次）。
- 保留 `_logPageTip()`：页面加载完成后读取 `#formErrorTip2` 文案写日志，便于确认账号/密码/验证码错误。

### 4. 验证
- `flutter analyze --no-fatal-infos`：No issues found。
- build 2079（arm64）已产出，因 USB 断开未能自动安装。

## 2026-11-23 · Batch28：改用「隧道 + authserver 原始登录页」，并记录页面错误提示（build 2078）

### 1. 现象（2077 真机日志）
- 22:41:05 起连续 4 次加载 `wfw.gdou.edu.cn/authserver/login`（05/05/21/51），始终没有出现 `jw.gdou.edu.cn/sso/jziotlogin`；即账号密码提交后又被弹回登录页，反复循环。
- 隧道本身正常：设备认证成功、代理启动、jw 复用连接建立；离开登录页后接口 901 属未登录预期。

### 2. 结论：wfw 不适合承担登录提交
- `curl` 对比实测（同一假账号 POST）：
  - 直连 authserver：服务端正常处理，返回精简登录页（8.6KB，页签为相对路径 `/authserver/login?type=...`）。
  - 经 wfw：返回 11.4KB 的原样登录页，页签仍是 `https://authserver.gdou.edu.cn/...` 绝对地址，没有错误提示，无法区分“密码错”还是“POST 未被处理”。
- 判断：wfw 的 WebVPN 改写只覆盖 GET 静态资源，登录提交链路不可靠；继续在它上面调登录收益很低。

### 3. 改动
- `sso_login_page.dart`：
  - `_useDirectAuth = true`：认证页改用 authserver 原始页面（不再用 wfw 反代页）。
  - 新增 `_skipJwFirst = true`：校外流程直接「设备认证 → 建隧道 → 打开 authserver 登录页」，不再先撞一次 jw 直连失败。
  - 新增 `_logPageTip()`：每次页面加载完成读取 `#formErrorTip2` 文案并写入日志（如“密码错误/验证码错误”），便于定位。
- `MainActivity.kt`：沿用 Batch27，`jw` 与 `authserver` 都走隧道；wfw 直连（当前仅作兜底入口）。

### 4. 验证
- `flutter analyze --no-fatal-infos`：No issues found。
- build 2078（arm64）已安装到 23127PN0CC，待真机完整登录验证。

## 2026-11-23 · Batch27：wfw 登录页存在 authserver 绝对链接，authserver 重新纳入隧道（build 2077）

### 1. 真机日志确认（2076）
- 22:22/22:30 两次日志均出现 `登录方式：仅 wfw 网关（已跳过 jw/authserver 直连）`，只加载 `wfw.gdou.edu.cn/authserver/login`，不再有直连失败；隧道建立、jw 复用连接正常。
- 但两次尝试都没有出现 `会话: 统一身份认证回填 Cookie` / `统一身份认证登录成功`，即**登录未完成**；离开登录页后课表/考试请求返回 901（未登录）。

### 2. 根因（抓取 wfw 反代登录页 HTML 分析）
- 静态资源（encrypt.js、login.js、语言包等）都已被网关改写为 `https://wfw.gdou.edu.cn/https://authserver.gdou.edu.cn/...`，走 wfw 没问题。
- 但**页签链接仍是 authserver 绝对地址**：
  - `https://authserver.gdou.edu.cn/authserver/login?type=dynamicLogin`（手机验证码登录）
  - `https://authserver.gdou.edu.cn/authserver/login?type=userNameLogin`（账号密码登录）
- 用户在这台手机上直连 authserver 会被运营商拒连，因此切换登录方式时页面打不开，登录无法继续。
- 另外 `contextPath="/authserver"`、表单 `action="/authserver/login"` 都落在 wfw 上，提交本身正常（用假账号 POST 实测返回 200 登录页，非网关错误）。

### 3. 修复
- `MainActivity.kt`：把 `authserver.gdou.edu.cn` 重新加入反向 bypass（隧道）列表。
  - 这样 wfw 页面里任何未改写的 authserver 绝对链接（页签、后续跳转）都会经隧道到达，不再受运营商限制。
  - wfw 与第三方资源仍直连，只有 jw / authserver 走隧道。
- 登录入口保持 wfw 网关（`_useDirectAuth=false`），继续做对比验证。

### 4. 验证
- `flutter analyze --no-fatal-infos`：No issues found。
- build 2077（arm64）安装到 23127PN0CC，待真机完整输入账号密码登录，日志应出现 `会话: 统一身份认证登录成功`。

## 2026-11-23 · Batch26：临时只保留 wfw 网关登录通道（build 2075，验证用）

### 1. 目的
- 用户清空 App 数据后要验证「wfw 网关登录通道」是否真的生效；此前登录仍会先尝试 jw 直连（校内）或直连 authserver，容易看不出走的是哪条。

### 2. 改动（`lib/ui/login/sso_login_page.dart`）
- 新增开关 `static const bool _useDirectAuth = false;`：
  - `false`：校外入口固定为 `_wfwEntry`，且 `_prepare()` **跳过 jw 直连入口，直接建隧道后从 wfw 网关打开认证页**；
  - `true`：恢复「直连 authserver 优先、失败切 wfw」的正式逻辑。
- `_retryAfterTunnel()` 的 wfw 兜底分支加 `_useDirectAuth` 条件，避免 wfw 模式下原地切换同一 URL。
- 隧道 / bypass 不变，jw 回调与数据仍走隧道。

### 3. 验证
- `flutter analyze --no-fatal-infos`：No issues found。
- build 2075（arm64）通过 adb 安装到 23127PN0CC（versionCode 2075），供清空数据后真机验证。
- 验证通过后把 `_useDirectAuth` 改回 `true` 即恢复正式登录策略。

## 2026-11-23 · Batch25：复核 authserver 公网可达，恢复直连 + wfw 网关兜底（build 2074）

### 1. 用 edge-cdp 插件通道复核（用户已登录的 Edge）
- `https://authserver.gdou.edu.cn/` 在用户浏览器里**正常打开**，因已有 CAS 会话直接进入「个人中心」（`/personalInfo/personCenter/index.html#/authorization`），不是登录页。
- 个人中心可见应用列表，其中有「WEBVPN（网瑞达）」「零信任的代理通道」等入口。
- `wfw.gdou.edu.cn` 是学校的 **Web 网关（WebVPN 形态）**：根路径标题为「文件管理」，并支持前缀式反代
  （`https://wfw.gdou.edu.cn/https://authserver.gdou.edu.cn/...`），也能反代 jw。
- check-host TCP 443 复测：
  - `authserver.gdou.edu.cn:443`：DE/BR/HK/IT/US 节点**全部连通**（0.19s~2.3s）→ **确属公网可达**；
  - `wfw.gdou.edu.cn:443`：CA/IL/IR/SG 节点全部连通；
  - `jw.gdou.edu.cn:443`：DE/IS/PT/RU 节点全部 `Connection refused` → 只有 jw 需要隧道。
- 本机 `curl` 同时段：jw 302（0.07s）、authserver 302（0.05s）、wfw 登录页 200（0.05s）。
- 结论：Batch23 的“authserver 可直连”没错，Batch24 的“运营商 443 拒连”以偏概全；用户手机上个别运营商的拒连属于该网络特例。

### 2. 登录入口：直连优先 + wfw 兜底（`lib/ui/login/sso_login_page.dart`）
- `_authEntry` 恢复为 `https://authserver.gdou.edu.cn/authserver/login?service=…jw…`（主路径，直连最快）。
- 新增 `_wfwEntry`（同一登录页的 wfw 反代地址）与 `_wfwTried` 标记。
- `_retryAfterTunnel()`：直连 authserver 失败/超时时，**先切 wfw 网关**（遮罩文案「正在切换登录通道…」），再进入原有两次重试；仍失败才提示。
- 隧道 / bypass 不变：只有 `jw.gdou.edu.cn` 走隧道。

### 3. 验证
- `flutter analyze --no-fatal-infos`：No issues found；`flutter test`：3 项通过。
- build 2074（arm64）构建后复制到 `桌面\海畔_2074.apk`。
- 探针截图：`桌面\authserver_probe.png`（个人中心页面）。

## 2026-11-23 · Batch24：wfw 是公网网关，校外登录改走 wfw 反代的认证页（build 2073，判断已在 Batch25 更正）

### 1. 更正 Batch23 的判断
- 用户实测：**运营商流量下 `authserver.gdou.edu.cn` 是拒连的**（Batch25 更正：这只是该运营商网络的特例，443 在多国节点均可达，已恢复直连）。
- 复核 `wfw.gdou.edu.cn`：它是**公网可达的 Web 网关**，不只做跳转页：
  - `https://wfw.gdou.edu.cn/authserver/login?service=…` 返回**完整的统一认证登录页**（含验证码、表单），静态资源被网关改写为 `https://wfw.gdou.edu.cn/https://authserver.gdou.edu.cn/authserver/...`；
  - `https://wfw.gdou.edu.cn/https://jw.gdou.edu.cn/` 同样能代理 jw（被 jw 302 到认证页）。
- 因此“用 wfw 的登录认证登录教务”确实可行，但正确做法是**借 wfw 的反代访问 authserver**，而不是拿 wfw 自己的 service 票据。

### 2. 校外登录入口改为 wfw 反代（`lib/ui/login/sso_login_page.dart`）
- `_authEntry` 由 `https://authserver.gdou.edu.cn/authserver/login?service=…` 改为
  `https://wfw.gdou.edu.cn/authserver/login?service=https%3A%2F%2Fjw.gdou.edu.cn%2Fsso%2Fjziotlogin`。
- 登录页与验证码经 wfw 网关加载（公网可达，不依赖隧道）；service 仍指向 jw，登录成功后 CAS 302 回 jw，由已建立的隧道接管并写入 JSESSIONID。
- 隧道 / bypass 配置不变：仍只有 `jw.gdou.edu.cn` 走隧道，wfw 与第三方资源直连。

### 3. 验证
- `flutter analyze --no-fatal-infos`：No issues found；`flutter test`：3 项通过。
- build 2073（arm64）构建后复制到 `桌面\海畔_2073.apk`。
- 待真机（运营商流量）确认：wfw 认证页可打开、验证码可刷新、登录后能回跳 jw 并进入首页。

## 2026-11-23 · Batch23：wfw 公网探测、authserver 直连、成绩分项改为手动刷新失效（build 2072）

### 1. `wfw.gdou.edu.cn` 探测结论（check-host.net 多国节点）
- `wfw.gdou.edu.cn`：全球节点 200，**公网可达**；但返回的只是 2KB 跳转页，JS 再跳 `authserver.gdou.edu.cn/authserver/login?service=https://wfw.gdou.edu.cn/`。
- `authserver.gdou.edu.cn`：全球节点 302（**已在 Batch24 更正：该 302 来自 HTTP 层，运营商流量下 443 实际拒连**）。
- `jw.gdou.edu.cn`：Iran / Iceland / Japan 节点 `Connection refused`、NL 节点超时 → **非公网可达**（校园网/国内方向受限）。
- 结论：**不能用 wfw 自己的 service 票据**。CAS 的 service ticket 与 `service` 参数绑定，wfw 拿到的票只能换 `service=wfw` 的会话，无法用于 `jw`。（Batch24 更正：wfw 实为公网 Web 网关，`/authserver` 可反代统一认证，见 Batch24。）
- 可用发现：既然 authserver 公网可达，校外登录可以**先直连 authserver 登录页**（service 参数仍指向 jw），只有 jw 的回调与数据请求走校园隧道。（Batch24 更正：authserver 在运营商流量下拒连，已改为经 wfw 反代加载登录页。）

### 2. 校外登录改直连 authserver（`lib/ui/login/sso_login_page.dart`）
- 新增 `_authEntry`：`https://authserver.gdou.edu.cn/authserver/login?service=…jw…/sso/jziotlogin`。
- 新增 `_loadUrl` 记录当前入口：校内/默认用 `_entry`（jw 的 SSO 入口）；隧道就绪后切换为 `_authEntry`，登录页与验证码直连加载，不再经隧道中转。
- 加载失败重试、超时兜底统一改为重新加载 `_loadUrl`，避免隧道建立后又被重试逻辑拉回 jw 入口而再次失败。

### 3. WebView 代理只让 jw 走隧道（`MainActivity.kt`）
- `setProxy` 的反向 bypass 列表删除 `authserver.gdou.edu.cn`，只保留 `jw.gdou.edu.cn`。
- 原因：authserver 公网可达，让它直连可以显著加快登录页与验证码的加载；同时隧道只承担真正不可达的 jw 流量，减少多路复用通道上的并发。

### 4. 成绩分项：去掉「重新获取」，由手动刷新统一失效（`grade_page.dart`、`local_cache.dart`、`data_providers.dart`）
- 删除成绩弹窗标题的「重新获取」按钮与错误态「重试」按钮，弹窗只按缓存/首取展示，不额外增加界面元素。
- `LocalCache` 新增 `removeWhere`，按条件批量清理缓存及其时间戳。
- `GradesNotifier.refresh()`（即成绩页下拉刷新）成功后调用 `removeWhere((k) => k.startsWith('cache_grade_detail_'))`：手动刷新承担“全部重新拉取”，下次打开分项弹窗自然重新请求。
- 删除已无调用方的 `_reload({bool force})`。

### 5. 验证
- `flutter analyze --no-fatal-infos`：No issues found。
- `flutter test`：3 项全部通过。
- 本轮无后端改动，无需重新部署。
- build 2072（arm64）构建后复制到 `桌面\海畔_2072.apk`。

## 2026-11-23 · Batch22：成绩分项缓存、首屏懒加载、校园网提示（build 2071）

### 1. 成绩详细分数（`lib/api/jw_apis.dart`、`lib/ui/grade/grade_page.dart`）
- 原因确认：此前每次点开成绩弹窗都实时 POST `/cjcx/cjcx_cxCjxqGjh.html`，无任何缓存，公网高延迟下必然慢。
- 现改为**本地缓存优先**：以 `xnm/xqm/jxbId` 为键写入 `LocalCache`，命中直接展示（成绩发布后分项基本不再变化）。
- 弹窗标题新增「重新获取」按钮（`force` 强制在线）；失败提示改为友好文案 + 重试，不再拼接异常对象。
- 加载态改用 `InkLoadingView`（「正在获取成绩构成…」）。

### 2. 首屏加载优化（`lib/ui/widgets/ink_shell.dart`）
- 原 `InkAppShell` 用 `Offstage` 一次性构建全部 5 个页面，导致登录后课表/成绩/考试/学业（学业内部再并发 3 路）同时抢通道。
- 改为**访问过才构建**：首屏只挂载课表页（考试仍由桌面小组件 provider 拉取），其余 tab 首次点击时才请求，切回后保持原状态。
- 首次连接实际顺序：设备认证（register→challenge→verify）→ 隧道预热 → 课表 → 考试（小组件倒计时）→ 其余 tab 按需。

### 3. 登录页提示（`lib/ui/login/sso_login_page.dart`）
- 认证页顶部新增可关闭提示条：「校园网直连体验更佳，公网通道延迟较高。建议先在校园网内完成一次数据同步，之后校外使用会更快。」

### 4. 账号准入核验（2024********）
- `haipan.json`：`allow_app` 已含 `2024********`，`devices` 有其公钥记录（createdAt 1795437648718）。
- 容器日志：出现 `mux open 20********02`，说明设备认证握手通过并已使用复用通道。
- 同期日志 `mux open/tunnel open` 仅 6 条（此前单流模式 163 条），复用通道生效。

### 5. 验证
- `flutter analyze` 无问题；`flutter test` 3 项通过。
- 后端本轮无改动，无需重新部署。
- build 2071（arm64，22.7MB）构建成功，已复制 `桌面\海畔_2071.apk`。

## 2026-11-23 · Batch21：登录分步动画、首页首屏加载保护、小窗返回、隧道多路复用（build 2070）

### 1. 登录过程体验（`lib/ui/login/sso_login_page.dart`）
- 新增 `_StageCover` 全屏遮罩：呼吸光环 + 分步进度（验证设备身份 → 建立校园隧道 → 打开统一身份认证 / 同步登录状态）+ 提示语。
- 首帧就绪前（`_pageReady == false`）始终遮住 WebView，**不再把 Chromium 的 `ERR_TUNNEL_CONNECTION_FAILED` 错误页给用户看到**。
- 校外切通道时先单独调用 `UsageTracker.tokenFor()` 完成设备认证，遮罩文案会依次显示「正在验证设备身份…」「正在建立隧道连接到教务系统…」。
- 加载失败改为静默重试：隧道已就绪仍失败时自动重载 2 次（间隔 1.2s），并设 15s 加载超时兜底；重试仍失败才提示「校园通道连接超时，请检查网络后重试」。
- 认证成功 `loginWithSso` 后先 `showInkNotice(... '认证成功' ...)` 发灵动岛通知，再返回首页；失败提示不再拼接异常对象。

### 2. 首页首屏加载保护（`lib/ui/widgets/common.dart` + 课表/成绩/考试/学业四页）
- 新增 `InkLoadingView`：呼吸光晕 + 文案（如「正在获取课表…」），替代只有转圈圈。
- 新增 `RetryLoadView`：首次加载失败先继续显示加载动画并自动重试 2 次，仍失败才展示友好提示与「重试」按钮；**不再把 Dio/HTTP 异常码直接显示给用户**。
- `ErrorView` 同步改为友好文案（「暂时无法获取数据 / 网络或校园服务响应较慢」），详细原因看日志页。

### 3. 小窗模式返回（`lib/ui/widgets/ink_page.dart`）
- 原先二级页只靠左缘手势返回，自由窗口/分屏下系统返回手势可能被窗口管理器占用。
- 现在 `showBack` 的页面在标题左侧始终显示返回按钮，左缘手势保留；任何窗口形态都能返回。

### 4. 后端隧道多路复用（`backend/server.js` + `lib/util/campus_tunnel.dart`）
- 日志分析（容器重启以来 1200 行）：`tunnel open` 163 次 / `tunnel close` 160 次，几乎 1:1，全部为 `jw.gdou.edu.cn:443`（149）与 `authserver:80`；无 401/409/502。
- 结论：功能无错误，但**每个 CONNECT 都新建一条 WebSocket**，高延迟公网下每次都要重付 TCP+TLS+WS 握手。
- 新增 `/tunnel-mux`：一条长 WebSocket 用 `[type:1][streamId:4][payload]` 帧承载多条 TCP 流（1=OPEN / 2=DATA / 3=CLOSE / 4=PING / 5=PONG）。
- 客户端新增 `_MuxTunnel`：优先复用通道，20s 应用层心跳；若服务端不支持或建连失败，自动回退旧的「一条连接一条隧道」模式（3 分钟内不再尝试），不影响登录可用性。
- 复用协议已在本地起 Node 服务端 + 双并发子流端到端验证通过（两条流互不干扰）。

### 5. 验证与部署
- `flutter analyze` 无问题；`flutter test` 3 项通过；`node --check backend/server.js` 通过。
- 后端已上传 `/path/to/haipan-api/server.js`（备份 `server.js.bak-before-mux`），`docker compose up -d --build` 重建容器成功，启动日志正常。
- build 2070（arm64，22.7MB）构建成功，已复制 `桌面\海畔_2070.apk`；当前无 adb 设备，待真机验收。

### 6. 待验证
- 公网弱网下学业/课表总耗时对比（预期省掉每请求一次握手）。
- 真机确认：登录遮罩文案、认证成功灵动岛、小窗返回按钮、首屏加载动画。

## 2026-11-23 · Batch20：空教室标题固定、学业拉取加速、课程三态（build 2069）

### 1. 空教室页面标题固定
- 原先 `InkPageScaffold` 走 `children`（整页滚动），大标题会随内容滚走。
- 改为 `body: SingleChildScrollView(...)`：标题固定，仅内容滚动，底部用 `inkPagePadding(context).bottom` 避让胶囊。
- 文件：`lib/ui/profile/favorite_rooms_page.dart`。

### 2. 学业数据拉取加速（公网高延迟）
- 计划查询由「全串行」改为 **3 路有界并发**，并保留每个计划的 3 次重试与空结果转 FKcxx 逻辑；各 lane 错开 120ms 起步。
- 修复并发下的成功判定：`query` 原先用共享 `all.length > before`，会被其他 worker 的新增误判为成功；改为统计本次响应实际新增数 `added`。
- 自动刷新窗口由 10 分钟放宽到 **30 分钟**（学业口径变化慢，手动下拉仍强制在线）。
- 文件：`lib/api/jw_apis.dart`、`lib/providers/data_providers.dart`。

### 3. 今日课程三态
- 原先只找“未来开始的课”，上课时段内会误显示「今日课程已结束」。
- 改为按系统时间三态：
  - 上课前：`下节课 10:05 课程名 · X 分钟后`（≥60 分钟拆小时）；
  - 上课中：`正在上 课程名 · 地点 · 还有 X 分钟下课`（≤1 分钟显示「即将下课」）；
  - 下课后：`今日课程已结束`。
- 卡片每 30 秒重算一次，倒计时自动更新；`dispose` 取消 Timer。
- 文件：`lib/ui/timetable/timetable_page.dart`。

### 4. 验证
- `flutter analyze` 无问题；`flutter test` 3 项通过。
- build 2069（arm64）构建成功，已复制 `桌面\海畔_2069.apk`。
- 当前 `adb devices` 无设备连接，未自动安装；待真机连接后安装验收。

### 5. 待验证
- 弱网（3000ms）下学业总耗时对比：预期由 30–45s 降至 10–15s；若仍出现计划丢失，再降并发到 2 路。

## 2026-11-23 · Batch19：文档体系落实（架构 / 经验 / 改动规范）

### 1. 新增
- `docs/ARCHITECTURE.md`：客户端分层、设备认证与令牌、公网隧道、缓存、提醒、小部件、后端 API、NAS 部署、构建发布。
- `docs/LESSONS_LEARNED.md`：认证恢复、隧道高延迟、部署目录与镜像、小部件排版、数据口径、协作流程。

### 2. 更新
- `docs/PROJECT_SUMMARY.md`：后端描述改为 Node + Docker 现状；补充设备认证、公网访问、小部件、部署约定与遗留项。
- `docs/modification_log.md`：补 Batch14–Batch18；文件头新增「记录规范」，明确每批必填项、最新在前。
- `docs/INDEX.md`：新增两份文档条目、更新体量与维护约定。
- 根 `README.md`、`backend/README.md`、`backend/INDEX.md`：从 Cloudflare Worker 描述更正为 Node 20 + Docker + NAS。
- `.gitignore`：新增 `/.secrets/`，临时凭据不入库（结项销毁）。

### 3. 验证
- 文档链接均为相对路径；未写入任何口令/密钥；`.secrets/` 已被忽略。

## 2026-11-23 · Batch18：管理员设备重绑 + NAS 部署目录纠正

### 1. 问题
- 清空应用数据后，Android Keystore 重新生成密钥对，服务端仍保存旧公钥，`/device/register` 永久返回 `409 device_mismatch`。
- 管理员身份在令牌签发后才成立，同样被 409 拦住；客户端把该错误统一包装成「隧道建连失败」，容易误判为网络问题。

### 2. 修改（`backend/server.js`）
- `/device/register`：公钥不一致时，普通用户仍返回 409；**管理员学号允许覆盖旧绑定**并打印 `admin device rebind`（学号脱敏）。覆盖时更新 `publicKey/updatedAt` 并持久化。
- 客户端无需改动，也不需重新发包。

### 3. 部署（关键）
- 实际 compose 目录为 `/path/to/haipan-api`（不是 `/vol1/1000/docker/haipan`，后者是旧副本）。
- 覆盖前备份 `server.js.bak-before-admin-rebind`；`docker compose up -d --build` 重建容器。
- 验证：容器内 `grep -c 'admin device rebind' /app/server.js` = 1；`ADMIN` 环境变量正确；未白名单学号探测返回 403，服务正常。

### 4. 教训
- `build: .` 的镜像只 `docker restart` 不会更新代码，必须 `up -d --build`；目录以 `docker inspect` 的 compose label 为准。

## 2026-11-23 · Batch17：小组件字号统一 + 空余信息（build 2068）

### 1. 字号统一
- 原先字号按「宽 + 高」分档，4×2 与 4×3 同为 4 列却字号不同。
- 改为**只按宽度**分档：<210dp 14/10.5sp；≥420dp 18.5/13.5sp；其余 15.5/12sp。同宽组件字号完全一致，高度只决定行数。

### 2. 排版与空余信息
- 高度预算重算：最多 8 行；课程超出显示「还有 N 门」。
- 剩余高度依次补充：明天第一门课（无课显示「明天无课」）→ 第二场考试。
- 布局新增 `tv_tomorrow`、`tv_exam2`；点击分别跳课表页、考试页。
- 「今日课表」默认尺寸改为 **4×2**（`widget_info_only.xml`：minHeight 110dp / targetCellHeight 2），与 4×3 的「课表 + 考试」区分。

### 3. 涉及文件
- `android/.../ScheduleWidgetBase.kt`、`res/layout/widget_today.xml`、`res/xml/widget_info_only.xml`。

### 4. 验证
- `flutter build apk --release --target-platform android-arm64 --build-number=2068` 通过，已安装真机，桌面 `海畔_2068.apk`。

## 2026-11-23 · Batch16：桌面小组件重做（build 2067）

### 1. 排版与可读性
- 重写布局：课程名 14→18.5sp、地点/时间 10.5→13.5sp、考试 13→17sp 三档；行距、内边距同步放大。
- 课程从顶部紧凑排列；窄组件把时间并入地点行；最多 8 行；超出显示「还有 N 门 · 点开查看」。

### 2. 两种组件
- 新增 `ScheduleWidgetBase.kt`（共用渲染/尺寸判断）与 `ScheduleOnlyWidgetProvider.kt`（今日课表，仅课程）。
- `TodayWidgetProvider.kt` 改为「课表 + 考试」，考试区块独立，仅该组件显示。
- 两个 Provider 共用数据与刷新通道；App 内刷新会同时更新。
- 新增 `widget_info_only.xml`、`widget_label_only` 等配置与预览图，补充首启/设置引导文案。

### 3. 验证
- `flutter analyze` / `flutter test` 通过；build 2067 构建并安装真机，完整组件确认显示课程 + 考试。

## 2026-11-23 · Batch15：导航玻璃、首启权限、隧道高延迟优化（build 2066）

### 1. 导航栏
- 调整水墨玻璃参数（`ink_tokens` / `ink_panel`），降低灰感、提高透明度与亮度。

### 2. 首启权限
- 新增一次性权限引导（通知、精确闹钟、电池优化等），首启集中申请，跳过可在设置内重新授权。
- 原生侧新增统一申请入口（`MainActivity`），避免逐个弹窗。

### 3. 公网隧道
- 针对 1000ms+ 高延迟：连接池复用、预热、令牌/入口刷新闸门，减少重复建连与并发风暴。
- 认证失败快速返回，避免无意义重试。

### 4. 验证
- `flutter analyze` / `flutter test` 通过；build 2066 安装真机并交付。

## 2026-11-23 · Batch14：缓存优先启动、页面缓存、提醒增强（build 2063）

### 1. 页面缓存
- 统一缓存优先 + 10 分钟新鲜期；手动刷新强制在线；排名等筛选查询加缓存。

### 2. 提醒
- 上课提醒改用 `setAlarmClock`，提高 Doze 下可靠性；增加电池优化白名单引导与 60 秒闹钟自测入口（`lesson_notifier.dart` / 原生通道）。

### 3. 启动
- 启动改为缓存优先：先进主页，握手与数据拉取在后台进行，失败再提示，避免白屏等待。

### 4. 验证
- `flutter analyze` / `flutter test` 通过；build 2063 构建并输出到桌面。

## 2026-11-23 · Batch13：全链学号脱敏 / 拒绝页去敏 / 空教室极端收紧

### 1. 学号脱敏（客户端）
- `lib/util/app_log.dart`：新增 `mask()`（6–20 位连续数字保留前 2 后 2，中间 `*`）与 `_maskLine()`；`_add` 落盘前强制脱敏，启动读取历史日志时也统一脱敏一次，旧明文日志在下次写入后即被覆盖。
- 日志页展示、导出、复制均取自脱敏后的条目，无需逐处修改。
- 管理员页面（用户统计 / 名单管理）保留**完整学号**（按用户要求，仅靠首尾位无法区分），但日志仍全局脱敏；新增学号备注，见第 6 节。

### 2. 拒绝页去敏
- `lib/ui/home/access_denied_page.dart`：删除「学号 xxx」与「管理员：学号」展示，仅保留「拒绝原因：当前账号不在使用名单内」。

### 3. 公网传输减少学号暴露
- `lib/api/usage_api.dart`：`/gates` 不再用 `?xh=` 查询参数（会话已绑定学号）；登录上报不再在请求体重复学号（服务端从会话取）。
- `backend/server.js`：
  - 新增 `maskId()`；`/permission`、`/perm` 响应不再回显学号；管理员专属的统计接口仍返回完整 ids（仅在加密会话内、`no-store`）；
  - 所有响应加 `cache-control: no-store`；
  - 隧道打开/关闭与入口配置日志均脱敏学号。

### 4. 空教室查询极端情况收紧
- `lib/api/jw_apis.dart`：`EmptyRoomApi.query` 新增 `maxPages` 与整次查询 `budget`（默认 25 秒）上限。
- `lib/ui/profile/favorite_rooms_page.dart`：
  - 查询加入代数（generation）校验，连续改条件时旧结果直接丢弃；
  - 「任一时段合并」从 30 组收紧为最多 12 组、周次最多 2 个、每组只取 1 页（100 间）、单组 8 秒、总预算 20 秒、间隔 320ms；组合按均匀抽样，避免只查前几个时段；
  - 收藏教室使用情况查询限制 3 页 / 12 秒。

### 5. 备用入口 haipan-api1 排查（已定位）
- NAS（Plexus / 192.168.1.10）上运行两套穿透：fnOS 的 Cloudflare Tunnel（主站）与 **ME Frp 客户端**（备用）。
- ME Frp 日志显示 `haipan` 隧道启动成功，公网地址 `https://api.example.com`，但该隧道协议被设为 **https**，而本地服务是 `127.0.0.1:18080` 的**明文 HTTP**：
  `转发请求到本地服务 [127.0.0.1:18080] 失败: tls: first record does not look like a TLS handshake`。
- 因此 Cloudflare 收到的是 ME Frp 边缘返回的 502。修复：在 ME Frp 控制台把该隧道协议改为 **HTTP**（本地端口 18080 不变），或保留 HTTPS 隧道但在前面加一层带证书的 nginx/Caddy。
- 已修复并验证（2026-11-23 14:0x）：`https://api.example.com/health` → 200（约 0.43s）；云端 `/tunnel/endpoints` 已同时返回主通道与备用通道，客户端故障切换会自动尝试。

### 6. 学号备注（管理员）
- `backend/server.js`：新增 `state.notes`（随 `haipan.json` 持久化）；`GET /notes` 返回全部备注，`POST /notes {xh,note}` 写入/清空（空串删除），均仅管理员会话可读；备注最长 40 字。
- `lib/api/usage_api.dart`：新增 `fetchNotes()` / `setNote()`。
- `lib/ui/profile/usage_page.dart`：用户统计、APP 准入名单、更新黑名单每行显示「备注：xxx」，点击弹出输入框编辑；未填写时显示「点击添加备注」。学号恢复完整展示。

### 7. 公网通道智能选路
- `lib/util/server_config.dart`：新增 `autoSelect()`，启动时并行测速全部入口并自动切到最快；仅在「当前不可达、快 200ms 以上或快过 1.5 倍」时切换，避免抖动；10 分钟内不重复测速；云端入口列表同步后会强制重选一次。
- 手动切换仍会持久化，自动选路只在差异明显时覆盖。

### 8. 提醒与运维增强
- `lib/util/lesson_notifier.dart`：考试当天在自定义提前提醒之外，若提前量 ≥20 分钟，再补一条「即将开考 · 课程」的 10 分钟提醒；两者过近时不重复打扰。提醒 id 仍复用 1000–1499 区间。
- NAS 运维脚本（`/path/to/haipan-api/ops/`）：
  - `backup.sh`：每天 03:30 备份 `data/haipan.json` 到 `backups/`，保留 14 天；
  - `healthcheck.sh`：每 5 分钟探测主入口、备用入口、本地 18080 与 mefrpc 进程，仅在状态变化时写 `ops/health.log`，日志超 2000 行自动截断；
  - 已写入 `lime` 用户 crontab（带 `# haipan-ops` 标记，便于移除）。
- 首次执行结果：`main=200 backup=200 local=200 mefrp=up`，备份文件已生成。

### 9. 验证与部署
- `flutter analyze`：No issues found；`flutter test`：3 passed；`node --check backend/server.js`：通过。
- `flutter build apk --release --target-platform android-arm64 --build-number=2048`：通过（22.6MB），已安装到真机并复制到桌面 `haipan-2048.apk`。
- `flutter build apk --release --target-platform android-arm64 --build-number=2049`：在 2048 基础上加入智能选路，构建通过并安装到真机。
- `flutter build apk --release --target-platform android-arm64 --build-number=2050`：加入考试多段提醒，构建通过并安装到真机。
- 后端已部署到 NAS（`/path/to/haipan-api`，旧文件备份 `server.js.bak-2048`，`docker compose up -d --build` 重建成功）：
  - `http://127.0.0.1:18080/health` → 200
  - `https://api.example.com/health` → 200，响应头已带 `cache-control: no-store`
  - `/gates` 未带会话 → 401
  - `/notes` 未带会话 → 401；`https://api.example.com/health` → 200

## 2026-11-23 · Batch12：公网通道可配置 / 上课提醒诊断 / 标题间距

### 1. 公网入口不再硬编码（多通道 + 故障切换）
- 新增 `lib/util/server_config.dart`：维护入口列表（默认 `https://api.example.com`），启动先读 SharedPreferences 缓存、后台再向任意可达入口拉取 `/tunnel/endpoints`；提供 `ping()` 延迟探测、`setActive()` 切换、`parseBase()` 输入归一化。
- `lib/util/campus_tunnel.dart`：删除 `_backend` 常量，建隧道时按「当前入口 → 备用入口」依次尝试 WSS；可用则自动切换并持久化，任一入口可达即可用。
- `lib/api/usage_api.dart`：`_backendUrl` / `_postUrl` 改为读 `ServerConfig.apiBase`；设备认证也按入口列表逐个尝试，成功后切到可达入口；新增 `saveTunnelEndpoints()` 供管理员下发配置。
- 新增 `lib/ui/profile/tunnel_page.dart`：入口列表（使用中/延迟标签）、全部测速、切换、添加/编辑/删除、保存到云端、从云端同步。
- `debug_page.dart`：管理员可见「公网通道」入口。
- `backend/server.js`：新增公共 `GET /health`（测速用）、`GET /tunnel/endpoints`（客户端同步），管理员 `POST /tunnel/endpoints` 写入 `cfg.tunnelEndpoints`；仍只允许 https 地址、最多 6 条。

### 2. 上课提醒排查
- `lesson_notifier.dart` 新增 `status()`（通知权限 / 精确闹钟 / 已排条数 / 下次触发）、`requestExactAlarm()`、`scheduleFromCache()`。
- `main.dart` 启动时 `ServerConfig.load()`，并在设置加载后按缓存课表重排提醒——不再依赖用户是否打开课表页。
- `MainActivity.kt` 新增 `notifyStatus` / `requestExactAlarm` 通道；`NotificationHelper.kt` 新增 `pendingCount()` / `nextAt()`。
- `debug_page.dart` 新增「提醒诊断」卡片：权限未开、精确闹钟未授权、0 条待触发都会给出对应操作；「重新排程」会重新申请权限并按缓存重排。

### 3. 大标题与内容间距
- `ink_page.dart`：`_Header` 底部间距 `s(8) → l(16)`，副标题与标题间距 `xs(4) → s(8)`，页面标题不再贴着内容。

### 4. 验证与部署
- `flutter analyze`：No issues found；`flutter test`：3 passed。
- `node --check backend/server.js`：通过。
- `flutter build apk --release --target-platform android-arm64 --build-number=2043`：通过，22.9MB；已复制到桌面 `haipan-2043.apk`；`adb devices` 为空，未安装。
- **后端已部署（2026-11-23 11:20）**：`server.js` 上传到 `/path/to/haipan-api/`，旧文件备份为 `server.js.bak-2043`，`docker compose up -d --build` 重建成功。
  - `http://127.0.0.1:18080/health` → `{"ok":true,...}`
  - `https://api.example.com/health` → `ok=true`
  - `GET /tunnel/endpoints` → 1 条主通道；无会话 `POST` → 401（符合预期）
  - 重建后内存会话清空，客户端会按需自动重新认证。
- **清理 tailscale**：删除未使用的 `tailscale` 容器、镜像及 `/vol1/1000/docker/tailscale` 目录；剩余容器为 haipan-api、ikuuu-hub、qq-napcat、qinglong、homeassistant。

## 2026-11-23 · Batch11：功能栏标题 / 教室查询定位当前周 / 非对称挑战认证

### 1. 功能栏标题放大
- `lib/ui/widgets/ink_page.dart`：`InkSectionHeader` 标题由 `tsLabel`（11px）改为 `tsSection`（17px 半粗），「功能」「学籍」等分区标题更清晰。

### 2. 空教室查询默认定位当前周
- `lib/ui/profile/favorite_rooms_page.dart`：记住当前周（`estimatedCurrentWeek`），周次横向列表在页面进场后自动滚动到当前周并居中，选中项直接可见，无需手动翻找。

### 3. 公网认证改为非对称挑战应答（移除硬编码密钥）
- Android：`MainActivity.kt` 新增 `cn.gdou.xiuhong/auth` 通道，在 Android Keystore 生成 P-256（secp256r1）密钥对；私钥不可导出，只暴露 `publicKey` 与 `sign`。
- 客户端 `lib/api/usage_api.dart`：
  - 新增 `DeviceAuth`（取公钥、挑战签名）；
  - `UsageTracker` 启动时幂等注册设备 → 取一次性挑战码 → 签名换取 30 分钟会话令牌；
  - 所有云端请求带 `Authorization: Bearer`，401 自动清会话并重试一次；
  - 删除 `apiToken` / `_permSecret`，`/perm` 管理权限改由「会话学号 == 管理员」判定。
- 服务端 `backend/server.js`：
  - 新增 `POST /device/register`（仅 APP 白名单内学号可登记公钥，同号换钥返回 409）；
  - 新增 `POST /auth/challenge`（2 分钟一次性挑战码）与 `POST /auth/verify`（SHA256withECDSA 验签，换取 30 分钟会话）；
  - 除三条引导接口外均需会话；`/gates`、`/permission` 只能查本人（管理员除外）；`GET /` 统计与 `/perm` 仅管理员；
  - 设备公钥随 `haipan.json` 持久化，会话/挑战只驻内存；移出 APP 白名单时自动清除该学号设备公钥；
  - 删除 `PERM_SECRET` / `API_TOKEN`，CORS 允许 `authorization`。
- `backend/docker-compose.yml`、`.env.example`：移除全部预共享密钥配置；`worker.js` 顶部标注仅旧版可用。
- 复测：本机 Node 起服务跑完整流程（注册/挑战/验签/gates/权限/一次性挑战/管理端），11 项全部通过。

### 飞牛主机部署记录
- 主机：`192.168.1.10`，用户 `admin`，系统 Debian 12 + Docker Compose v2.40.3。
- 目录：`/path/to/haipan-api`（`data/` 为持久化卷，容器内 `node` uid 1000 可写）。
- 端口：宿主机 **18080** → 容器 8080，避开已有服务的 8080。
- Dockerfile 基础镜像改为 `docker.m.daocloud.io/library/node:20-alpine`：飞牛默认镜像源 `docker.fnnas.com` 对 Docker Hub 返回 401。
- 启动：`cd /path/to/haipan-api && sudo docker compose up -d --build`，容器 `haipan-api`，`restart: unless-stopped`。
- 本机验证：`/gates` 返回 401、`/device/register` 空请求返回 400、日志 `haipan api listening on :8080`。
- 公网：改用新域名 `api.example.com`（原 `api.example.com` 仍绑定旧 Worker 白名单，保留不动）。飞牛隧道应用 `com.dustinky.tunnel` 把新域名指向 `http://127.0.0.1:18080`。

### 验证
- `flutter analyze` 无问题、`flutter test` 通过、build 2033 / 2034 / 2035 打包成功（22.8MB）。
- build 2034 把云端地址改为 `https://api.example.com`。
- build 2035 修复日志导出把级别写成 `Instance of '_LogEntry'` 的插值错误（`[$e.level]` → `[${e.level}]`）。
- build 2036 二级页去掉只有按钮的空 AppBar，大标题回到左上角，清空/导出与标题同一行右侧。
- 真机 `d4b532b4` 未连接，未安装；APK 已复制到桌面 `haipan-2036.apk`。
- 注意：新认证与旧版不兼容，需先部署新版 `backend/server.js`；旧版 APP 会被 401 拒绝，需同步升级。

## 2026-11-23 · Batch10：tab 页面动效复刻 esplock

- 参考 `D:\Lime\Documents\ESP LOCK\app\lib\ui\shell.dart` 的 tab 动效：
  - 新页按切换方向横滑 6%（`Offset(0.06 * direction, 0)` → 0）；
  - 透明度 0.2 → 1；
  - 缩放 0.985 → 1；
  - 时长 320ms，标准曲线 `easeOutCubic`、位移/缩放 `fastOutSlowIn`。
- `lib/ui/widgets/ink_shell.dart`：移除原先「旧页淡出 160ms → 换页 → 新页淡入上移」的两段式过渡；点击后直接切页并让新页进场，导航指示器与内容同步朝点击方向移动；连续快速点击可直接打断重启动画。
- 验证：`flutter analyze` 无问题、`flutter test` 通过、build 2032 打包成功（22.8MB）。真机 `d4b532b4` 未连接，未安装。

## 2026-11-23 · Batch9：课表周次修正 / 日志细分 / 通识学分 / 动效与背景整理 / Token 门禁

### 1. 旧学期课表按周次显示
- `lib/ui/timetable/timetable_page.dart`：去掉 `!termIsCurrent ||` 分支，历史学期同样按所选周次过滤课程，不再把全部课程堆到同一周。

### 2. 运行日志细分
- `lib/ui/profile/log_page.dart`：清空/导出按钮移到右上角 `actions`；去掉「筛选」小标题与冗长提示；新增按模块（tag）的横向筛选 chips，级别筛选保留；搜索框提示缩短为「搜索模块或内容」。
- 更多运行信息接入 `AppLog`：导航切换（`ink_shell.dart`）、设置项变更（主题/字体/语言/提醒/开学日/背景，`settings_provider.dart`）、从「我的」打开二级页（`profile_page.dart`）。

### 3. 通识教育拓展学分统计
- `lib/models/models.dart`：`AcademicCourse` 新增 `kcgsmc`（解析 `KCGSMC`，例如「人文艺术类」）。
- `lib/providers/data_providers.dart`、`lib/api/jw_apis.dart`：缓存编解码与课程重建同步保留 `kcgsmc`。
- 新增 `lib/ui/profile/ge_credit_page.dart`：按 `KCGSMC` 分组统计已修/在修学分，每个分类可单独设置最低学分要求（默认 2.0，本地持久化）；显示达标状态与缺口，课程明细可展开。
- `lib/ui/profile/profile_page.dart`：在「空教室查询」下新增「通识拓展学分」入口。

### 4. 导航点击反馈液体滑动
- `lib/ui/widgets/ink_shell.dart`：导航选中底色改为独立滑动指示器，点击即刻用 `TweenAnimationBuilder` + `easeOutBack` 滑向目标 tab，移动途中轻微横向拉伸形成液体流动感；每个 tab 不再各自绘制选中底色。

### 5. 二级页白屏优化
- `lib/theme/ink_page_transition.dart`：移除路由内容层的 `FadeTransition`，只保留上移 + 回弹缩放；不透明背景立即铺满，消除进入/退出时约 1 秒的白屏淡入。

### 6. 背景图片只保留本地选择
- `lib/ui/profile/settings_page.dart`：删除图片 URL 输入与暗化滑条，仅保留「选择图片 / 重新选择」调用原生文件选择器。
- `lib/ui/widgets/ink_panel.dart`：`_ImageBackdrop` 仅支持本地文件，删除网络图片与灰色暗化遮罩。
- `lib/providers/settings_provider.dart`：删除 `backgroundDim`；启动时丢弃旧版本遗留的 http(s) 链接。

### 7. 首页上课提醒卡片展开动画
- `lib/ui/timetable/timetable_page.dart`：展开内容包进 `AnimatedSize`，箭头用 `AnimatedRotation` 同步翻转。

### 8. 公网访问 Token 门禁（fnOS GUI 隧道）
- `backend/server.js`：新增 `API_TOKEN`（默认 `HAIPAN_API_2026`），校验 `x-api-token` 头或 `?token=`，不匹配返回 401；CORS 允许该头。
- `lib/api/usage_api.dart`：新增 `UsageTracker.apiToken`，所有云端请求统一通过带 Token 头的 Dio 发出。
- `backend/docker-compose.yml`：去掉内置 cloudflared，映射 `8080:8080`，由飞牛 fnOS 的 Cloudflare Tunnel GUI 指向本服务。
- `backend/.env.example`：改为 `API_TOKEN` 配置；`backend/worker.js` 支持可选 `API_TOKEN`（未配置时行为不变）。

### 验证
- `flutter analyze`：无问题；`flutter test`：通过。
- `flutter build apk --release --target-platform android-arm64 --build-number=2031`：通过（22.8MB）。
- 真机 `d4b532b4` 本次未连接，`adb install` 未能执行。

## 2026-11-23 · Batch8：液体玻璃导航 / 自定义背景 / 动效补齐 / 默认准入

### 1. 导航栏改为透明液体玻璃
- `lib/theme/ink_tokens.dart`：`glassNavFill` 亮 30%、暗 34%；`InkGlass.navBlur = 0`，不再做毛玻璃。
- `lib/ui/widgets/ink_panel.dart`：`InkGlassPanel` 新增 `liquid` 模式（斜向白色高光 + 白色内描边 + 顶边高光），导航胶囊启用，背景直接透出。
- 导航选中底色改为 72% 的 `secondaryContainer`，保持通透。

### 2. 自定义背景
- `lib/providers/settings_provider.dart`：新增 `backgroundStyle / backgroundSeed / backgroundImage / backgroundBlur / backgroundDim` 及持久化键。
- `lib/ui/widgets/ink_panel.dart`：`InkBackground` 改为读取设置的 Consumer，支持：
  - 宣纸默认、晨雾、暮色、竹影、暖阳、夜墨 6 套渐变；
  - 纯色（8 色色板）；
  - 自定义图片：支持从相册选择（原生压缩到最长边 1920 后存入私有目录）或填写 URL；支持 0–24 模糊、0–60% 暗化，失败回退底色。
- `lib/ui/profile/settings_page.dart`：新增「背景」卡片，含风格缩略图、纯色色板、图片链接弹窗与模糊/暗化滑条。

### 3. tab 切换动画 + 二级页残影
- `lib/ui/widgets/ink_shell.dart`：新增 `_tabAnim`，切换时旧页 160ms 淡出 → 换页 → 新页 240ms 淡入并从 1.2% 下方回位；非当前页仍 Offstage 保留状态。
- `lib/theme/ink_page_transition.dart`：新增静态 `backdropBuilder`，推入二级页时铺一层不透明全局背景，内容层再做淡入/上移/缩放，避免与底页交叉淡入产生残影。
- `lib/main.dart`：启动时注入 `InkBackground(animate:false)` 作为二级路由背景。

### 4. 考试提醒自定义时间
- `lib/providers/settings_provider.dart`：新增 `examRemindMinutes`（默认 30，5–120 分钟）并同步到通知模块。
- `lib/util/lesson_notifier.dart`：考试当天提醒改为「开考时间 − 自定义分钟数」，排程 key 纳入分钟数；前一天 20:00 预提醒保留。
- `lib/ui/profile/settings_page.dart`：提醒区新增「考试提前提醒」滑条。

### 5. 溢出菜单过渡动画
- `lib/ui/widgets/common.dart`：`TermPickerButton` 的 `PopupMenuButton` 增加 `popUpAnimationStyle`（280ms 减速淡入、160ms 收起）。

### 6. 刷新反馈通知
- `lib/ui/widgets/common.dart`：`InkRefresh` 统一包裹 `onRefresh`，成功弹顶部灵动岛「已刷新」，失败弹「刷新失败，请稍后重试」。

### 7. Docker + Cloudflare Tunnel 部署
- 新增 `backend/server.js`：零依赖 Node 服务，接口与 `worker.js` 对齐，数据持久化到 `$DATA_DIR/haipan.json`。
- 新增 `backend/Dockerfile`、`backend/docker-compose.yml`、`backend/.env.example`：API 容器不映射端口，仅与 `cloudflared` 同网络；隧道 Token 走 `.env`。
- 本地已用 `node --check` 与接口回归验证准入/黑名单语义。

### 8. 抢课白名单改黑名单 + APP 默认禁止
- `backend/worker.js` 与 `backend/server.js`：`/gates` 改为
  - `select = 不在 block_select`（黑名单默认可用）；
  - `updateBlock = 在 block_update`；
  - `app = 管理员或 allow_app 名单内`（新用户默认禁止）。
- `lib/api/usage_api.dart`：新增 `featureApp / gateApp`，`fetchGates` 解析 app 并缓存上次结果（离线回退，默认禁止）。
- `lib/providers/data_providers.dart`：新增 `appAccessProvider`。
- `lib/ui/home/home_shell.dart` + 新增 `lib/ui/home/access_denied_page.dart`：未开通用户整页显示「使用权限未开放」，可重新校验或退出登录。
- `lib/ui/profile/usage_page.dart`：名单管理新增「APP 准入名单」，抢课区块改为「抢课黑名单」。

### 验证
- `flutter analyze`：无问题；`flutter test`：通过。
- `flutter build apk --release --target-platform android-arm64 --build-number=2030`：通过并安装到真机（`d4b532b4`）。

## 2026-11-23 · Batch7：课表固定大节时间 / 撤掉 tab 动画 / 通知通道重做

### 1. 课表左侧时间固定为大节区间
- 用户明确要求不要推算单节开始时间。删除 Batch6 的 10 个单节时间标签。
- `lib/ui/timetable/timetable_page.dart` 改为按两节合并：
  - 1-2 `08:10 / 09:45`、3-4 `10:05 / 11:35`、5-6 `14:30 / 16:05`、7-8 `16:25 / 17:55`、9-10 `19:30 / 21:10`。
  - 大节标签高度 = 2 行（`rowH * 2`），左侧宽度与网格行高不变；11-12 节无对应作息，不显示时间标签。
  - 课程详情与「下节课」倒计时也统一按大节开始时间。
- 真机截图确认左侧栏显示 `1-2 / 08:10 / 09:45` 等 5 组固定区间；课程详情显示「第9-10节 · 19:30-21:10」。

### 2. 彻底删除 tab 切换动画
- `lib/ui/widgets/ink_shell.dart`：删除 `_switch` AnimationController、`_prevIndex`、`_AnimatedTab` 与 fade-through/缩放逻辑。
- 切换 tab 直接 `setState`，非当前页仅 `Offstage + TickerMode(enabled:false)`，不再出现两页叠加的残影。

### 3. 系统通知通道重做（上课 / 考试）
- Dart `lib/util/lesson_notifier.dart`
  - 节次映射改为大节开始：1-2 08:10、3-4 10:05、5-6 14:30、7-8 16:25、9-10 19:30。
  - 上课提醒从「只排今天」改为排未来 28 天（按日期计算周次、过滤单双周，id 1..500）。
  - 考试提醒从固定 998/999 改为覆盖全部未来考试：前一天 20:00 + 当天 08:00（早场为开考前一小时），id 1000..1499。
  - 关闭提醒时下发空列表清空已排闹钟；新增 `openNotificationSettings()`。
- Kotlin
  - `NotificationHelper.kt`：通道升级为 `lesson_v2`（删除旧的 `lesson` 通道，恢复高优先级）；`setExactAndAllowWhileIdle` 优先，无精确闹钟权限时降级 `setAndAllowWhileIdle`；排程清单写入 SharedPreferences；新增 `rescheduleAll()`；小图标改用 `R.drawable.ic_notify`。
  - 新增 `BootReceiver.kt`：开机 / 应用更新 / 改时间后按持久化清单重建闹钟。
  - `MainActivity.kt`：新增 `scheduleExams`、`openNotifySettings`；`requestPerm` 同时确保通道存在；`getLaunchPage` 读取后清除 `page`，避免重复跳 tab。
  - `AndroidManifest.xml`：声明 `SCHEDULE_EXACT_ALARM`，注册 `BootReceiver`。
  - 新增 `res/drawable/ic_notify.xml` 单色通知小图标。
- `lib/ui/profile/settings_page.dart`：提醒开关打开时请求通知权限；新增「系统通知设置」入口。

### 验证
- `flutter analyze` 无问题；`flutter test` 3 项通过。
- release APK 构建通过（最终 build 2023），已安装到 `d4b532b4`。
- 真机：课表左侧固定区间正确；tab 直接切换无残影；`lesson_v2` 通道 importance=4 且未删除；系统已排 58 条提醒闹钟；测试通知成功出现在通知栏。

---

## 2026-11-23 · Batch6：课表作息与已结束考试置灰
### 课表时间轴
- 旧映射把「大节开始时间」当成每节开始时间，导致 1/2 节都是 08:10、3/4 节都是 09:45 等重复且错误的标签。
- 按学校现行作息重写：
  - 1-2 节 08:10~09:45；3-4 节 10:05~11:35；5-6 节 14:30~16:05；7-8 节 16:25~17:55；9-10 节 19:30~21:10。
  - 单节开始时间按大节内均分推算：08:10 / 09:00 / 10:05 / 10:50 / 14:30 / 15:20 / 16:25 / 17:10 / 19:30 / 20:20。
  - 课程详情/时间文案仍按整段展示，如 1-2 节 `08:10-09:45`。
- 真机截图确认左侧标签连续、无重复，卡片尺寸保持回退后的原样。

### 考试卡
- 已结束（`daysLeft < 0`）的考试卡整卡 `Opacity 0.55` 置灰，标签保持「已结束」neutral。真机截图确认。

### 验证
- `flutter analyze` 无问题、`flutter test` 3 项通过、release APK 构建通过（build 2020，已安装到 `d4b532b4`）。

---

## 2026-11-23 · Batch5：回归修复（页面不可点击 / 课表卡片 / 入口行高）
### 页面无法点击（严重回归）
- 根因：Batch4 的 fade-through 给当前页包了 `IgnorePointer`，而 `ignoring` 默认是 `true`，整个内容区手势被拦截，只有底部导航（在页面外层）还能点。
- 修复：当前页去掉 `IgnorePointer`，仅退场页保留 `ignoring: true`，见 `lib/ui/widgets/ink_shell.dart` 的 `_AnimatedTab`。

### 课表卡片
- 回退 Batch4 的尺寸改动：行高 `68 → 58`、卡片内边距 `6 → 5`、课程名 `11 → 10px`（3 行）、教室 `10 → 9px`（2 行）、卡片宽度恢复 `dayW - 4`。
- 保留时间栏可读性修复：节次 13px、时间 11px、颜色 `ink.secondaryLabel`。

### 入口行高
- 回退 `InkSettingTile` 内层 `minHeight: 60`（它叠加 12px 上下内边距后把行高撑到 84）。入口行恢复到约 60 的原始高度。
- 保留图标统一（`InkIconBadge` 36×36 + 学籍/功能同一色调）。

### 登录
- 只保留统一身份认证入口，删除学号密码 / 滑块 UI 与 `slider_captcha.dart`，`auth_api.dart` 精简为登出。
- 会话持久化：Cookie 显式写入 30 天有效期；WebView 不再清除认证中心 Cookie；上次 SSO 登录过时，冷启动会自动打开认证页静默续期。

### 验证
- `flutter analyze` 无问题、`flutter test` 3 项通过、release APK 构建通过（build 2019，已安装到 `d4b532b4`）。

---

## 2026-11-22 · Batch4：视觉收口（课表/小字/图标/等高/动画）
### 课表
- 网格行高 `58 → 68`，课程卡左右间隙 `4 → 2`、内边距 `5 → 6`，课程名 `10 → 11px`、教室 `9 → 10px`，课程名限 2 行、教室 1 行。
- 时间栏：节次 `9 → 13px`、上课时间 `9 → 11px`，颜色由 `colorScheme.outline`（浅灰白）改为 `ink.secondaryLabel`，不再与背景融合。
- 全站排查：UI 层已无 `colorScheme.outline` / `InkTextStyles.nano` 作为正文色的用法。

### 小字清理
- 删除所有页面 `InkPageScaffold.subtitle`（成绩/考试/学业/设置/关于/更新/存储/日志/统计/排名/抢课/空教室/调试）。
- 删除设置项冗余状态小字（上课提醒/考试提醒「已开启/已关闭」、开学周「校准课表周数显示」、详细日志说明）、关于页免责声明与「调试入口已开启」、我的页 `Powered By XIUHONG`。
- 登录/引导页删除「广东海洋大学教务系统（非官方）」「在学校认证页完成登录」「账号密码仅保存在本机…」等说明；引导页功能卡片只保留图标 + 名称。
- 课表今日卡文案去掉情绪化尾巴：「今天没课，好好休息」→「今天没课」，「今日课程已结束，明天见」→「今日课程已结束」。

### 图标统一
- 新增 `InkIconBadge`（36×36、圆角 10、10% 色调底、20px 图标），`InkSettingTile`、我的页学籍/功能入口、登录 SSO 卡、抢课状态卡、空教室卡、更新结果卡全部改用同一徽标。
- 我的页学籍图标补 `iconTone: InkTone.info`，与功能入口一致。

### 等高与排版
- `InkSettingTile` 内容区 `minHeight: 60`，我的页学籍值改单行省略，入口行高度一致。
- 设置页明暗主题 `SegmentedButton`：`expandedInsets: EdgeInsets.zero`、13px/1.2 字重 500、紧凑内边距、隐藏选中勾，文字不再挤在按钮里。

### 切换动画
- 移除 iOS 视差横滑（两页半透明叠加导致残影），改为 fade-through：旧页 0–35% 退净，新页 25% 起淡入并 0.97→1 放大；`tabSwitch` 320 → 240ms。

### 验证
- `flutter analyze` 无问题、`flutter test` 3 项通过、release APK 构建通过（build 2016，已安装到 `d4b532b4`）。
- build 2015 真机截图确认：课表时间栏可读、课程卡变高；成绩/考试/学业/我的 四页无页面副标题；我的页学籍与功能图标风格一致、行高一致。build 2016 仅再调整今日卡文案，安装后设备进入息屏，未再截图。

---

## 2026-11-22 · 旧版滑块登录优雅停用（学校已切统一身份认证）
### 事实
- 真机 `curl -L` 实测：`https://jw.gdou.edu.cn/xtgl/login_slogin.html` 现 `302 → /sso/jziotlogin → http://authserver.gdou.edu.cn/authserver/login?service=...`（最终 200）。
- 因此旧版滑块链路拿到的不是登录页表单，`GET /zfcaptchaLogin` 直接抛 `DioException [unknown]: null`（真机日志 22:37:47），验证码图片永远加载不出来。

### 改动
- `lib/api/auth_api.dart`：`_fetchLoginPage()` 检查 `resp.realUri` 与返回 HTML，命中 `authserver` / `/sso/` 或空页时抛 `AuthException('学校已启用统一身份认证，旧版「学号密码 + 滑块」入口已停用，请切换到「统一身份认证」登录')`，不再把裸网络异常抛给 UI。
- `lib/ui/login/login_page.dart`：
  - 新增 `_captchaError`；验证码加载失败时在输入框下方常驻 `_CaptchaUnavailable` 卡片（说明 + 「改用统一身份认证」+「重试」），`AuthException` 不再额外弹顶部提示。
  - `_login()` 在验证码不可用且无会话时直接提示该原因，避免落到「请先拖动滑块」的死循环。

### 验证
- `flutter analyze --no-pub`：**No issues found**；`flutter test`：**3 passed**。
- `flutter build apk --release --target-platform android-arm64 --build-number=2014`：通过，22.8MB；已 `adb install -r` 到 `d4b532b4` 并启动，默认停在「统一身份认证」入口、无报错提示。
- **待用户验收**：切到「学号密码」应看到常驻引导卡片而非 DioException。

---

## 2026-11-22 · Batch3：对比度、真悬浮导航、iOS 视差切换、二级页收尾
### 对比度（文字不再糊进背景）
- `lightOnSurfaceVariant` `#61727E → #4C5E6A`、`light.secondaryLabel` `#7B8B96 → #566975`；深色同步提亮（`#B4C5CF` / `#9EB0BC`）。
- 语义色整体加深：`success #2F7A5C`、`warning #99661C`、`danger #A5443E`、`info #35708F`，保证 10-11px 的 `InkTag`/说明文字在宣纸底上可读。
- `EmptyView` / `ErrorView` / `GuestEmptyView` 不再用 `scheme.outline` 当正文色，统一改 `secondaryLabel` / `onSurfaceVariant`；`TermPickerButton` 改用令牌与 `AppIcons`。

### 真悬浮胶囊导航
- 毛玻璃：`InkGlass.navBlur 0 → 24`，浅色底 `0x9EFFFFFF`、深色 `0x8F152026`。
- 投影：新增 `InkGlass.navShadows()`（两层柔和阴影），并修正 `InkGlassPanel` —— 阴影必须画在 `ClipRRect` 外层，否则会被裁掉。
- 真悬浮的关键：`InkPageScaffold` 的 `body` 分支不再把底部导航高度算进外层 Padding，页面列表铺到手势条，滚动时从胶囊底下穿过，毛玻璃才有内容可透、投影才可见；各页列表自行用 `inkPagePadding(context).bottom` 做底部避让（成绩/考试/学业/我的/日志/用量/抢课/排名）。
- 独立路由（无胶囊）时 `inkPagePadding` 只避让系统手势条，不再凭空多留 88px。

### tab 切换动画（iOS 视差）
- `_AnimatedTab` 由「淡入 + 2% 上浮」改为横向视差：新页从侧边整屏滑入，旧页反向位移 28% 并轻微变淡（0.88），`easeOutCubic`；方向由 `_direction` 决定（向后切从右进、向前切从左进）。仍然只画「当前页 + 上一页」，动画结束清空上一页。

### 二级页收尾（全部迁移到水墨骨架）
- 排名、设置、关于、调试、存储、更新、用量、日志、空教室、选课共 10 页：`Scaffold+AppBar` → `InkPageScaffold(showBack: true)`，`Card/ListTile` → `InkCard/InkSettingTile/InkSectionHeader/InkTag`，`Icons.*` → `AppIcons.*`，`scheme.outline` 正文色 → 语义令牌，`AppNotification` → `showInkToast`，简单确认 → `showInkDialog`。
- 清理死代码：删除不再被引用的 `app_notification.dart` 与 `RefreshButton`（统一用 `BusyRefreshButton`）。

### 验证
- `flutter analyze --no-pub`：**No issues found**；`flutter test`：**3 passed**。
- `flutter build apk --release --target-platform android-arm64 --build-number=2013`：通过，22.7MB。
- `InkPageScaffold` 在带 `bottom:` 操作条时关闭 `extendBody`，避免列表末尾被按钮压住。
- 导航外观已用临时 golden 快照（`InkAppShell` + 彩色内容）确认毛玻璃透出与投影生效，临时文件已删除。
- **未完成真机验收**：本轮构建后真机 ADB 断开，且设备上的教务会话已失效停在登录页；需要在真机登录一次后，用 `--es page 1/2/3/4` 复查 4 个 tab 和二级页。

---

## 2026-11-22 · Batch2：成绩 / 考试 / 学业 / 我的 迁移水墨骨架
- **页面迁移**：4 个 tab 全部去掉自带 `Scaffold`+`AppBar`，改用 `InkPageScaffold` 大标题（副标题 + 右侧刷新/学期胶囊），由外壳统一绘制宣纸底与胶囊导航避让；`home_shell.dart` 删除 `_LegacyPage` 过渡包装。
- **成绩**：统计卡改为 `InkStatsRow`（GPA / 加权平均 / 学分 / 门数）；分数分布改 `InkCard` + 柱状图（`<60` 用朱砂色）；课程列表改 `InkCard` 行式布局，分数按 ≥90 绿 / 60-89 墨蓝 / <60 朱砂着色；成绩构成弹窗同步换成令牌与 `AppIcons`。
- **考试**：卡片改 `InkCard` + `InkTag` 倒计时（今天=danger、7 天内=warning、更远=info、已结束/未公布=neutral），信息行统一 `AppIcons`（时间/考试名称/地点/教学地点/考试方式），禁止散落 `Icons.*`。
- **学业**：修读进度卡（百分比 + 进度条 + 5 格统计，`InkStatsRow` 等高）；预警改用 `InkBanner(warning)`；课程分类改 `InkCard` + `ExpansionTile`，课程行状态用 `InkTag`（已修 success / 在修 warning / 未修 neutral）。
- **我的**：个人信息卡（头像/姓名/性别标签/学号/班级/校徽）、学籍卡与功能入口均改 `InkCard` + `InkSettingTile`；所有入口行等高（统一无副标题、统一 12px 上下内边距）；退出登录改 `showInkDialog(danger: true)`，标题与图标统一朱砂色；意见反馈弹窗改用令牌。
- **新增组件**：`ink_page.dart` 增加 `body` 槽位（标题下填充剩余高度，异步页面用）、`InkStatsRow`/`InkStat`（IntrinsicHeight + stretch，保证同一行统计卡等高）、`InkTag`、`InkSettingTile.titleTone`。
- **修复（真机验收发现）**：多 tab 同时存活时，各页 `ListView` 默认 `primary: true` 会共用根 `PrimaryScrollController`，切换 tab 后新页继承旧页滚动偏移（考试页首卡被截掉一截）。4 个 tab 的列表、课表滚动区与 `InkPageScaffold` 内置滚动统一改为 `primary: false`，各自持有独立滚动位置。

### 验证
- `flutter analyze`：**No issues found**。
- `flutter test`：**3 passed**。
- `flutter build apk --release --target-platform android-arm64 --build-number=2009`：通过，22.8MB。
- 真机 `d4b532b4`：覆盖安装 2009；用 `--es page 1/2/3/4` 冷启动逐页截图检查：成绩统计四格等高、考试首卡完整、学业 5 格统计等高、我的入口行等高且顶部无裁切；课表页无回归，logcat 无 FATAL。
- **未验证**：Batch2 未做深色模式与字体放大截图（结构与 Batch1 共用令牌）；二级页（设置/关于/更新/日志/用量/空教室/选课/排名）仍为旧布局，但已继承新主题。

---

## 2026-11-22 · Batch1：水墨骨架 + 双登录入口（统一身份认证 / 学号密码）
- **视觉层（自建，不引外部路径依赖）**：新增 `lib/theme/ink_tokens.dart`（宣纸白 `#F7F9FA`、淡墨夜色 `#0F171D`、墨蓝 `#35678F`/`#8FB9D6`、hairline `0.6`、圆角 16/12/999、动效 160/280/320ms、课程色板 `InkCourseTints`）；重写 `lib/theme/app_theme.dart` 按令牌生成 Material 3 主题，Scaffold 保持透明；新增 `ink_page_transition.dart`（淡入 + 2% 上移）。
- **组件**：`ui/widgets/ink_panel.dart`（宣纸底 + 光晕、半透明面板，blur=0）、`ink_shell.dart`（悬浮胶囊导航 + 内容避让 `InkNavMetrics`）、`ink_page.dart`（大标题骨架 / 卡片 / 设置项 / 分区标题 / 底部弹层）、`ink_notice.dart`（顶部灵动岛，替代 SnackBar）、`ink_dialog.dart`（仿 iOS 确认弹窗）、`app_icons.dart`（语义图标表）。
- **全局外壳**：`main.dart` 的 `builder` 补 `Material` + `InkBackground`（修复 TextField 双下划线坑）；开屏与会话失效弹窗改为水墨样式；`home_shell.dart` 换成 5 项胶囊导航，保留原生通知跳转；未迁移的 4 个 tab 暂加底部避让。
- **双登录**：`login_page.dart` 改为「统一身份认证（默认）/ 学号密码」两段切换，旧滑块流程完整保留，验证码改为按需加载；新增 `ui/login/sso_login_page.dart`：`webview_flutter 4.14.1` 打开 `/sso/jziotlogin`，回跳教务后轮询 `WebViewCookieManager` 读取 `JSESSIONID`，经 `JwClient.saveCookies` 注入 `PersistCookieJar`，再由 `SessionNotifier.loginWithSso` 探针确认并复用原有登录后处理。
- **Android**：新增 `res/xml/network_security_config.xml`，仅对 `authserver.gdou.edu.cn` 放行明文（认证服务器仍是 http），其余域名强制 https。
- **课表（Batch1 范围内）**：去 AppBar，改大标题 + 学期胶囊；课程色板迁到 `InkCourseTints`；实践课卡、课程详情、周次选择统一水墨组件；滚动区补胶囊导航避让。
- **修复（真机验收发现）**：首版 `_TabLayer` 把 `TickerMode` 包在淡入淡出外侧，切 tab 时淡出动画的 ticker 被立刻停掉，旧页停在 `opacity=1`；加上页面底色透明，真机出现「课表/成绩/学业/我的」多页叠影。改为壳层自持 `AnimationController`，只在「当前页 + 上一页」两页之间做 320ms 交叉淡化，其余页 `Offstage`，动画结束即销毁上一页，保证同时最多画两页。

### 验证
- `flutter analyze`：**No issues found**（0 error / 0 info）。
- `flutter test`：**3 passed**（新增 `test/ink_tokens_test.dart`，覆盖浅/深课程色板一一对应、语义色独立、间距圆角约束）。
- `flutter gen-l10n`：项目无 `l10n.yaml` 与 ARB，**不适用**。
- `flutter build apk --release --target-platform android-arm64 --build-number=2007`：通过；APK 22.8MB（与 2004 同量级），产物 mtime `2026-11-22 22:04`。
- 模拟器 `emulator-5554`：卸载旧签名包后安装，启动无 FATAL；开屏、引导、双登录页、学号密码页、深色模式截图检查通过，通知权限弹窗与顶部灵动岛提示正常。模拟器无外网（`ping` 全丢包），验证码报错属环境限制。
- 真机 `d4b532b4`（Xiaomi 23127PN0CC）：`versionCode=2007`、`lastUpdateTime=22:04:50` 覆盖安装成功；冷启动课表第 12 周、实践课与胶囊导航正常，重影消失；用通知参数 `--es page 1/4` 冷启动复验成绩页、我的页均只显示单页且导航高亮正确；`am force-stop` 重开会话恢复；logcat 无 FATAL / `E/flutter`。
- **未验证 / 已知限制**：
  - SSO 端到端登录未实测（需注销或清数据后操作，本轮不触碰真机输入）；仅完成编译、页面加载与 Cookie 注入链路。
  - 旧滑块登录仍依赖被 SSO 接管的匿名入口，清数据后是否可用存在风险，保留为第二入口。
  - 成绩/考试/学业/我的 4 个 tab 仍是旧布局（已自动继承新主题底色与卡片），大标题/卡片结构留待 Batch2 迁移。

---

## 2026-11-22 · 全量重抓 + 以网页为准的数据一致性修复
- **重抓方式**：用本机 Edge 已登录会话导出 `jw.gdou.edu.cn` Cookie，在 Node 里按正方表单/Referer 规则重放接口，样本全部落到 `api-captures/`（索引见 `api-captures/INDEX.md`）。
- **重抓结果**（2026-2027-1，账号 2024********）：
  - 课表 **43 条排课 + 5 条实践课**。早期基准只有 41 条，是因为学校把「机械制造技术」「标准化管理」拆成了多段（如 `9-11周,13-16周` + `第17周`），并非抓取遗漏。
  - 成绩：当前学期 0 条；历史 2025-2/2025-1/2024-2 分别 13/16/16 条，字段与 App 解析一致。
  - 考试 8 条；绩点排名 GPA 3.51、班级第 12；学业 109 门（通过 59 / 在读 31 / 未修 19）、已获 100.5/156 学分，与学业页文案完全一致。
- **修复 1（实践课字段）**：`sjkList` 的字段名与 `kbList` 不同——教师是 `jsxm`、周次是 `qsjsz`、地点是 `jxdd`。原 `CourseEntry.fromSjk` 按 `xm/zcd/cdmc` 取值，导致实践课卡片只剩课程名。已改为按真实字段解析（`models.dart`）。
- **修复 2（空教室查询必失败）**：`/cdjy/cdjy_cxKxcdlb.html` 的 `zcd/jcd` 是**位掩码**（第 n 项 = `2^(n-1)`），不是逗号列表；原实现传 `"9,10"` 会让服务端直接返回「错误提示」HTML，解析抛错后页面永远为空。新增 `_bitmask()`，并按实抓的 `totalResult/totalPage` 修正分页终止条件；使用部门字段实际为 `sydxmc`，补进 `sybm` 回退链（`jw_apis.dart`）。
- **修复 3（考试字段标签）**：`jxdd` 在网页表头是「教学地点」，App 原写作「就座」，已改正（`exam_page.dart`）。
- **修复 4（成绩构成名称）**：总评行的名称原样带出 `【 总评 】`，与网页的「总评」不一致；解析时统一去掉【】与首尾空白（`jw_apis.dart`）。
- **修复 5（性别）**：登录补全学院时顺带解析 `col_xbm`（男/女），写入 `StudentInfo.xb`；旧缓存会话需重新登录后生效。
- **旧登录页探测结论**：匿名 GET/POST `/xtgl/login_slogin.html` 均 **302 → `/sso/jziotlogin` → authserver**；带有效会话 Cookie 时 302 → 菜单页（看起来像"旧页面还能登录"，实际是复用已有会话）。旧滑块验证码 JS（`zfcaptchaLogin`，仍下发 rtk）和 RSA 公钥接口（`login_getPublicKey.html`）仍在线，说明正方本地登录模块没有被移除，只是入口被 SSO 接管。

### 验证
- `flutter analyze`：0 error（8 条既有 info）。
- `flutter build apk --release --target-platform android-arm64 --build-number=2004`：通过，22.5MB。
- 真机 `d4b532b4`（Xiaomi 23127PN0CC）`adb install -r` 覆盖安装保留登录态（2003 → 2004）；课表第 12 周正常，「实践课程」5 门均已显示教师与周次：劳动教育3/谢景福/4-6周、运筹学课程设计/郭淑婷/第17周、机械制造技术课程设计/刘焕牢/第17周、现代物流设施与规划课程设计/徐晓鸣/第17周、社会调查与思想政治课社会实践/闫竟豪/10-14周。
- 空教室：用位掩码请求已实测返回 JSON（全周次/全星期/1-10 节共 10 间），逗号列表对照组返回错误页。

---

## 2026-11-22 · 课表准确性修复（周次分段单/双 + 实践课缓存）
- **依据**：新版教务入口 `netcheck.gdou.edu.cn/go.php?code=jw` → `jw/sso/jziotlogin` → 统一身份认证；旧接口 `POST /kbcx/xskbcx_cxXsgrkb.html` 在 SSO 会话下仍返回完整数据。抓包与打印件存于 `api-captures/2026-11-22_kbcx_official.{json,pdf}`。
- **Bug 1**：`TermUtils.parseWeeks` 把"单/双"当作整串条件，导致 `2周,7周,11-13周(单)` 丢掉第 2 周、`10-12周(双),13周` 丢掉第 13 周。改为按逗号分段各自判定单/双。
- **Bug 2**：`Timetable.fromJson` 固定 `sjk: const []`，从缓存恢复后 5 门实践课消失。`toJson/fromJson` 补齐 `sjk` 持久化（旧缓存缺字段时回退空列表）。
- 文件：`jw_app/lib/util/term_utils.dart`、`jw_app/lib/models/models.dart`。

### 验证
- 用官方抓包 41 条排课回归：修正前周次差异 2 条，修正后 **0 条**；缓存往返后 41 排课 / 5 实践课完整保留。
- `flutter analyze`：0 error（仍是 8 条既有 info）。
- `flutter build apk --debug` 31.9s 通过；模拟器 `emulator-5554` 安装启动无 FATAL。
- 真机 `d4b532b4`（Xiaomi 23127PN0CC）：`flutter build apk --release --target-platform android-arm64 --build-number=2002` 构建通过，覆盖安装保留登录态。
  - 第 13 周（11/23-11/29）周一 9-10 已显示「形势与政策教育5 / 明德楼」（修复前会被丢掉）。
  - 第 2 周（9/7-9/13）周六 5-6 已显示「(网络课)能源中国 / 钟海楼04025」（修复前会被丢掉）。
  - 第 12 周正常显示「形势与政策教育5」，下拉刷新后数据与官方一致。

---

## 2026-11-22 · 重启项目：修复构建链路（NDK 版本对齐）
- **现象**：`flutter build apk --debug` 长时间无输出，Gradle 日志停在 `Downloading Android CLI...`，`jw_app/build` 始终未生成。
- **根因**：`android/app/build.gradle.kts` 中 `ndkVersion = "25.2.9519653"` 在本机未安装（当前只有 `28.2.13676358`），AGP 9 触发 SDK 自动安装，进而调用新版 `sdkmanager.bat` → `android.exe` 引导下载 Android CLI，下载卡死。
- **修改**：`ndkVersion` 改为本机已安装的 `28.2.13676358`（本项目无 NDK 原生代码，不影响产物）。
- 首次构建另遇 `com.android.tools.build:builder:8.5.0` 从 `dl.google.com` 拉取读超时（阿里云/腾讯镜像单文件均正常），Gradle 自动重试后通过，未改仓库配置。
- 文件：`jw_app/android/app/build.gradle.kts`。

### 验证
- `flutter pub get`：依赖恢复成功。
- `flutter analyze`：0 error（8 条既有 info）。
- `flutter build apk --debug`：构建通过，产物 `jw_app/build/app/outputs/flutter-apk/app-debug.apk`。
- 模拟器 `emulator-5554`（Android 16 / API 36）：`adb install -r` 成功，启动无 FATAL，正常进入登录页（学号/密码 + 滑块验证 + 游客浏览）。

---

## 2026-09-01 · 学业数据准确性收敛 / 收藏输入框简化 / 灵动岛单例防连点 / 更新页同版本日志 / 缓存兼容
- **学业数据按权威口径收敛**：修读状态判读（已修59/未修4/在读31/未通过0/总94/GPA3.51）与真实 XDZT 规则一致；学业**缓存键升级 `cache_academic_v2_`**（`data_providers.dart`），新版本不会再读到旧(错误状态)缓存，确保首启即按新口径重新拉取。
- **空教室「我的收藏」输入框极简再设计**（`favorite_rooms_page.dart`）：去掉背景卡片/图标，改为"普通搜索框（圆角描边）+ 右侧『添加』按钮"，简洁突出功能。
- **灵动岛通知改单例 + 加长入场延迟**（`app_notification.dart`）：`AppNotification` 增加 `_active` 单例引用，快速连点时先撤掉上一条再插入新一条，避免多条灵动岛叠加卡顿；入场延迟由 240ms 提到 320ms，等按钮自身动画结束再浮现。
- **更新页：同版本展示当前版本更新日志**：`update_api.dart` 的 `checkLatest` 在同版本时返回其 release 说明（downloadUrl 置空）；`update_page.dart` 新增"同版本"分支——展示当前版本更新日志，按钮置灰并显示「已是最新版」，不再仅显示"无更新"。
- 文件：`data_providers.dart`、`favorite_rooms_page.dart`、`app_notification.dart`、`update_api.dart`、`update_page.dart`。

### 验证
- `flutter analyze`：无 error（仅既有 info）；`flutter build apk --debug`：构建通过。
- 待真机：核对学业 GPA/通过/未修/在读稳定；收藏输入框简洁性；连点开关时灵动岛不叠加卡顿；更新页同版本显示日志+置灰按钮。

---

## 2026-09-01 · GPA/通过数抖动修复 / 空教室收藏输入与加载反馈 / 灵动岛防卡顿
- **GPA 与"通过课程"偶发变化（59↔49）修复**（`jw_apis.dart` `AcademicApi.fetch`）：逐计划请求由"全部并行 + 静默吞失败"改为**限量并发 3 + 单计划失败重试 2 次**（Kcxx 无数据再查 FKcxx），避免个别计划偶发丢失（约 10 门已修课程）导致 GPA/通过数在两次拉取间跳动；失败计划记录 W 级日志便于排查。判定口径沿用上一节的真实 XDZT 规则。
- **空教室「我的收藏」输入框改简洁美观**（`favorite_rooms_page.dart`）：输入区改为圆角边框容器，前置添加图标 + 「输入教室名」+ 底部整排「添加到收藏」按钮（tonal 圆角），功能更清晰。
- **收藏"查看使用情况"加加载反馈**：查询需 1~2s，先弹出**转圈 + 文案占位对话框**（`_LoadingOverlay`），完成后关闭并弹结果显示，避免"点了没反应"。
- **灵动岛通知延迟浮现防卡顿**（`app_notification.dart`）：入场延迟 240ms，等触发它的开关/按钮自身动画结束再滑入，入场完成后再计时 2.4s 自动收起，避免动画并行导致的卡顿。
- 文件：`jw_apis.dart`、`favorite_rooms_page.dart`、`app_notification.dart`。

### 验证
- `flutter analyze`：无 error（仅既有 info）；`flutter build apk --debug`：构建通过。
- 待真机验证：反复进出学业页/切换学期观察 GPA 与通过数是否稳定；收藏输入框与加载反馈、灵动岛时序。

---

## 2026-09-01 · 学业在读/未修判定按真实 XDZT 修正（经 CDP 抓取实证）
- **重新抓取并实证**：通过本机 Edge CDP（57184 端口）在已登录教务页内直接 fetch 学业接口，共取 94 条真实字段。分布：`XDZT=4`（有成绩，59 条）、`XDZT=1`（无成绩，31 条）、`XDZT=3`（无成绩，4 条）。
- **关键结论**：未修/在读课程在服务端 **XNMC/XQMMC 为空**，无法用"当前学期"匹配（此前该方向必然失败）；唯一权威区分是 `XDZT`。
- **判断口径修正**：
  - 逐课程比对：`XDZT=1`＝运筹学/生产管理/机械制造技术/采购供应链/工程经济学/形势与政策5 等（本学期在读）→ **在读**；
  - `XDZT=3`＝AutoCAD绘图/决策理论与方法/职业就业指导2/形势与政策6（后续学期）→ **未修**；
  - `XDZT=4 + 有成绩` → **已修**。
- **代码**：
  - `models.dart`：`AcademicCourse` 新增 `xdz` 字段（保留修读状态原始值），`fromJson` 改为 `有成绩或XDZT=4→已修；XDZT=1→在读；其余→未修`。
  - `jw_apis.dart` `AcademicApi.fetch`：`infer` 改按 `xdz` 判定（去掉失效的"当前学期匹配"），并把 `xdz` 透传给分组结果；调试级日志记录 `课程 CJ XDZT 判定` 采样。
- 文件：`models.dart`、`jw_apis.dart`。

### 验证
- `flutter analyze`：无 error；`flutter build apk --debug`：构建通过。

---

## 2026-09-01 · 日志开关改开关形式 / 空教室分页与收藏UI / 提醒设置改完再生效
- **输出详细日志改开关**（`debug_page.dart`）：由分段按钮改为 `SwitchListTile`——关闭=查看级（仅 W/E），打开=调试级（含 D 级细节）；提示文字精简为「关闭为查看级，打开为调试级」。功能沿用 `AppLog.debugDetail`（非空壳）。
- **空教室结果分页**（`favorite_rooms_page.dart`）：结果列表改为**每页 20 条 + 换页**（上一页/下一页 + `当前页/总页数`）。底部新增 `_pager` 控件；日志与空态逻辑不变。
- **空教室收藏栏 UI 优化**：头部改为「图标容器 + 我的收藏 + 数量徽标」；添加输入框换成描边卡片（加号图标 + 输入 + 收藏按钮，支持回车提交）；空态改成居中占位卡（提示在查询结果点书签或手动添加）。
- **删去查询教室卡片下方的提示文字**（对用户无意义的说明段落）。
- **提醒栏三功能改「修改完再生效」+ 灵动岛提示**（`settings_page.dart`，页面由 ConsumerWidget 改 ConsumerStatefulWidget）：
  - 上课提前提醒、字体大小两处滑块：拖动仅更新本地显示（`_dragRemind`/`_dragFont`），**松手（onChangeEnd）才真正持久化并重排提醒**，消除拖动时反复 reschedule 的卡顿；松手后弹出灵动岛提示。
  - 上课提醒/考试提醒开关、明暗模式：切换即时生效，并弹出灵动岛提示。
- **学业诊断日志增强**（`jw_apis.dart`）：调试级日志补记采样课程的 `XDZT` 原始值，并汇总输出 `XNMC/XQMMC/XDZT/成绩是否存在` 组合分布（最多前 30 种），用于核查修读状态判定口径是否仍需修正（待真实数据）。
- 文件：`favorite_rooms_page.dart`、`debug_page.dart`、`settings_page.dart`、`jw_apis.dart`。

### 验证
- `flutter analyze`：无 error，仅既有 info 提示。
- `flutter build apk --debug`：构建通过。
- 注：`flutter install` 至 `23127PN0CC` 被设备拒绝（INSTALL_FAILED_USER_RESTRICTED），需在手机上放行 USB 安装后重装。

---

## 2026-09-01 · 学业在读/未修纠错 / 日志分级全覆盖 / 空教室分页与收藏优化
- **学业页在读/未修反序修复（改判定口径）**：不再依赖 `XDZT` 字段语义，改为「有成绩→已修；无成绩且属于本学期→在读；其余无成绩→未修」，在 `jw_apis.dart` `AcademicApi.fetch` 中统一套用；`overview.notStarted/inProgress` 来自同一份课程状态，与列表天然一致。
  - 说明：此前按 `XDZT=1已修/2在修/3未修` 推断，但服务端该码与实际相反导致未修/在读倒置；现改为数据驱动判定，并在「调试级」日志中采样输出 `课程 CJ XN XQ → 状态`（最多前 12 门），便于抽查是否仍反序。
- **日志系统接入更多模块 + 新增“输出详细日志”开关**：
  - `app_log.dart`：新增 `debugDetail`（true=调试级打印全部 D/W/E；false=查看级仅 W/E，过滤细节 D）与 `setDetail()` 持久化。
  - `debug_page.dart`：新增「输出详细日志」分段开关（调试级/查看级），位于「日志保留天数」下方。
  - 新接入日志点：`jw_client.dart`（网络 请求 GET/POST 状态码、失败、会话过期、登录态探针）、`session_provider.dart`（会话 登录开始/成功、恢复在线/离线、退出）、`lesson_notifier.dart`（提醒 上课/考试提醒排条数）、`jw_apis.dart`（学业 状态采样）。
  - 至此日志覆盖：课表/成绩/考试/学业/缓存/网络/会话/提醒/统计/风控/自动抢课/更新/空教室/学期回退。
- **空教室：分页拉全修复“只 20 个/扩大筛选无数据”根因**：
  - `EmptyRoomApi.query` 原固定 `showCount=20` 且不翻页 → 无论条件都只返回前 20 个；改为按 jqGrid `records/total` 自动翻页（每页 100，上限 10 页）并按 `cdbh` 去重，一次返回全部可达房间。
  - 排序字段 `sortName` 由 `'cdbh '`（尾随空格）改为 `'cdbh'`，避免服务端排序异常。
  - 多选（周/星期/节次任一项 >1）直接查询为空时，自动按「单时段分别查询后合并(OR)」回退；只要任一所选时段空闲即返回，界面上标注「已按任一时段合并」。合并限定至多 60 次请求、周数取前 3，避免过量。
- **空教室交互**：
  - 收藏按钮：点一次收藏、**再点一次取消**（成功点时高亮、可再点取消，不再置灰禁用）。
  - 收藏列表：由 InputChip（tag）改为**卡片**展示；**点击卡片**弹层查看该教室“使用情况”（按当前所选周/星期/节次查询是否空闲 + 基本信息）；**左滑删除**（Dismissible，红底删除）。
  - 收藏持久化从纯字符串升级为 JSON 对象（含场地编号/类别/教学楼/座位/校区），旧版数据自动迁移。
  - 场地类别 / 楼号下拉：设置 `menuMaxHeight` 约 5 项高度，超出部分**上下滑动**浏览。
- 文件：`jw_apis.dart`、`favorite_rooms_page.dart`、`debug_page.dart`、`app_log.dart`、`jw_client.dart`、`session_provider.dart`、`lesson_notifier.dart`。

### 验证
- `flutter analyze`：无 error，仅少量既有 info 提示。
- `flutter build apk --debug`：构建通过。

---

## 2026-08-31 · 我的页入口重构 / 反馈改弹窗 / 空教室交互优化
- **作者卡**：左侧靠左并上下居中，头像与名称间距加大（16）。
- **入口名**：「查询空教室」改为「空教室查询」。
- **我的页入口重排与权限**：
  - 顺序：设置 - 空教室查询 -（选课/抢课，白名单授权时显示，否则隐藏）- 检查更新 - 意见反馈 -（调试，需连点版本号手动打开）- 关于。
  - 「用户统计」从我的页移出，收纳进**调试**页内（仅管理员可见）；「调试」入口移出设置页、移到我的页（任何用户可开）。
- **意见反馈**：由独立页改为**弹窗**（公众号二维码 + 引导截图→微信扫一扫→关注公众号→提交截图+描述），删除原 `feedback_page.dart`。
- **加速镜像**：默认改为 `https://v6.gh-proxy.org/`，失败回退直连。
- **空教室多选交互**：周次/星期/节次 chips 改为**横向滚动**（一屏约 5 个，其余滑动），避免铺满页面；空结果时提示扩大选择（说明 APP 默认组合与网页最近选择不同是常见原因）。
- 文件：`profile_page.dart`、`about_page.dart`、`debug_page.dart`、`settings_page.dart`、`favorite_rooms_page.dart`、`update_api.dart`；删除 `feedback_page.dart`。

### 验证
- `flutter analyze`：无 error/warning。
- `flutter build apk --debug`：构建通过。

---

## 2026-08-31 · 反馈入口 / 空教室增强 / 镜像优化 / 关于页清理
- **意见反馈**：新增 `feedback_page.dart`（展示公众号二维码 → 扫码反馈），二维码取自根目录 `mmexport…jpeg` → `assets/feedback_qr.jpeg`；「我的 → 意见反馈」入口。
- **空教室增强**：入口改名「查询空教室」；页面重抓教务下拉（校区4/楼号32/类别22）改为下拉选择；周次/星期/节次均支持**多选**（chip 点选/再点取消）；默认学年学期为当前（新学期）；教室按「可借/占用」标记（依据 是否可借 sfkjy / 使用部门 sybm / 备注 bz），可借优先排序。
- **镜像**：删除内置多个镜像，改为默认 `https://proxy.gitwarp.top/`，下载失败自动回退直连；波浪进度条去掉深色椭圆背景（只留波浪）。
- **关于页**：删除院徽图片（assets/college_logo.jpg 及 pubspec 声明）与「@机械工程学院」，作者头像+名字居中。
- **修复**：空教室下拉「第1周」1.7px 溢出（加宽+居中）；日志无红色 overflow。
- 文件：`feedback_page.dart`、`favorite_rooms_page.dart`、`jw_apis.dart`(EmptyRoomApi 多选/新字段)、`update_page.dart`、`update_api.dart`、`about_page.dart`、`profile_page.dart`、`pubspec.yaml`。

### 验证
- `flutter analyze`：无 error/warning。
- `flutter build apk --debug`：构建通过。

---

## 2026-08-31 · A3 空教室查询上线
- 用 CDP 抓取已验证的空教室接口，整理为 `docs/empty_classroom_api.md`。
- `jw_apis.dart`：新增 `EmptyRoomApi`（POST `cdjy_cxKxcdlb.html?doType=query&gnmkdm=N2155`）与 `EmptyRoom` 模型、`emptyRoomApiProvider`；参数含 周次(zcd)/星期(xqj)/节次(jcd)/校区/类别/楼号/名称。
- `favorite_rooms_page.dart`：改为「空教室查询 + 收藏」综合页 —— 周次/节次下拉、星期多选、类别分段、楼号/名称筛选、查询列表（名称/类别/楼/座位/备注，可一键收藏），保留“我的收藏”（chips 可删、手动添加）。
- 入口不变：「我的 → 常用教室」。

### 验证
- `flutter analyze`：无 error/warning。
- `flutter build apk --debug`：构建通过。

---

## 2026-08-31 · 更新下载体验 / 概览卡排版 / 抢课空态提示
- `update_api.dart`：新增国内加速镜像前缀 `ghMirrors`/`ghMirrorLabels`（直连、ghfast.top、ghfast.net、ghproxy）。
- `apk_installer.dart`：`downloadAndInstall` 支持 `CancelToken`，新增 `cancel()`。
- `update_page.dart`：
  - 下载可中途「取消下载」（CancelToken，取消后不拉起安装）。
  - 新增谷歌商店风格的不规则波浪进度条 `_WaveProgressBar`（CustomPainter 流动动效）。
  - 下载前可选「下载镜像」（直连/多个加速源），网络差时加速。
- `timetable_page.dart`：今日概览卡课程行时间列加宽至 74px、与课程名间距加大（课程名右移留出时间空间）。
- `select_page.dart`：抢课列表为空时给出更明确的排查提示（批次未开放/未缴费/未开始等）。

*说明（抢课列表为空）：若已通过白名单且选课已开放仍无列表，多半是该选课批次未对此学号开放或学费未缴清；可在教务系统核实。*

### 验证
- `flutter analyze`：无 error/warning。
- `flutter build apk --debug`：构建通过。

---

## 2026-08-31 · 功能增强 A/B 批落地（一）

### A 批
- A1 今日概览卡片（课表页顶部）：日期/周几/周次、今日节数、下节课倒计时、距考试天数；点击展开课程列表与考试提醒；并优化了课程行的排版（时间列加宽、字号/行距调整）。
- A2 成绩可视化：成绩页新增「分数分布」直方图（<60 / 60-69 / 70-79 / 80-89 / 90+），底部汇总“共 N 门”；GPA 仍由汇总卡大数字展示。
- A3 常用教室收藏：新增 `favorite_rooms_page.dart`（本地增删收藏教室），「我的→常用教室」入口；说明实时“空教室查询”依赖教务接口，待接入。
- A4 挂科预警/学分缺口：学业页新增 `_WarnCard`（有挂科 / 距最低修读还差 X 学分才显示）。
- 文件：`timetable_page.dart`、`grade_page.dart`、`academic_page.dart`、`favorite_rooms_page.dart`、`profile_page.dart`。

### B 批
- B1 记住账号加密：新增 `util/secure_store.dart` + 原生 `MainActivity` 的 `cn.gdou.xiuhong/secure` 通道（Android Keystore AES-256-GCM）；`session_provider` 保存密码由明文 `_kKeepPass` 改为 `SecureStore.put`；`login_page` 回填改从 SecureStore 读取；logout 时清除密文。
- B3 会话过期一键续期：`main.dart` 会话失效弹窗新增「立即续期」→ 跳登录页（密码已自动回填，仅需再滑一次滑块；教务登录强制滑块，无法完全无人重登）。
- B2 二次确认提醒：考试提醒升级为“前一天 20:00 + 当天 08:00”两条（原生 id 998/999），`NotificationHelper.scheduleExam` 支持 id 参数，`scheduleExams` 同时安排明日预提醒。

### 待推进（受环境/后端依赖）
- C1 桌面小组件：需原生 AppWidgetProvider + 布局 XML + Manifest 广播，真机需添加桌面快捷方式验证。
- D1 即时推送：需后端推送子服务（FCM/自建）与推送配置，无法纯客户端完成“即时”推送；建议单独立项。

### 验证
- `flutter analyze`：无 error/warning。
- `flutter build apk --debug`：构建通过（含原生 Kotlin 改动）。

---

## 2026-08-31 · 功能增强批次启动 · A1 首页聚合卡片 / 关于页标题外移

### 0. 总体计划（用户确认全做，按简→难分轮，第9项采用“加密会话＋记住密码自动重登”）
- A 批（前端高价值）：A1 首页聚合卡片 ⏳ → A2 成绩可视化 → A3 空教室/收藏（需验证接口）→ A4 挂科预警/学分缺口
- B 批（账号/提醒/会话）：B1 记住账号(Keystore 加密) → B2 选课/考试二次提醒 → B3 会话过期一键续期＋记住密码自动重登
- C 批：桌面小组件；D 批：即时推送（需后端推送子服务）

### 1. 关于页「开发者」标题移到卡片外
- `lib/ui/profile/about_page.dart`：作者卡上方新增 `_sectionLabel('开发者')`（与应用信息/技术栈一致），卡片左列恢复为「睡醒的夜猫子」+「@机械工程学院」，移除卡片内的小字标题。

### 2. A1 首页聚合卡片（已实现）
- `lib/ui/timetable/timetable_page.dart`
  - 新增 `_TodayOverview` 聚合卡（课表页顶部）：
    - 顶行：日期 + 周几 + 当前周 + “今日 N 节”。
    - 摘要行：下节课（时间/课程/剩余分钟）或“课余/没课”，并附“距考试 N 天”。
    - 点击展开：今日课程列表（时间+课程名+教室）与最近一场考试提醒。
  - 数据源：`timetableProvider`（今日课程）、`examsProvider`（考试倒计时）；未登录/负载失败时自动隐藏。

### 验证
- `flutter analyze`：无 error/warning。
- `flutter build apk --debug`：构建通过。

---

## 2026-08-31 · 关于页排版 / 抢课入口白名单化 / 功能接入审查

### 1. 关于页排版
- `lib/ui/profile/about_page.dart`
  - 作者卡左列：顶部新增小字「开发者」（primary 标签）→「睡醒的夜猫子」→「@机械工程学院」（原“开发者”行删除，@ 信息上移）。
  - 「应用信息」卡上方新增「应用信息」小标题；「技术栈」卡上方新增「技术栈」小标题（新增 `_sectionLabel` 辅助）。

### 2. 抢课入口弃用隐藏机制，改为纯白名单
- `lib/ui/profile/profile_page.dart`
  - 抢课入口由 `showSelect && gates[select]` 改为仅 `gates[select]`（白名单通过即直接展示入口，管理员恒 true）；移除对 `settings.showSelect` 的依赖及无用 import/变量。
  - 「调试」入口依旧由连点版本号 5 次（`settings.showSelect`）控制。
- `lib/ui/profile/about_page.dart`：版本连点提示文字由「选课/抢课入口」改为「调试入口」；「选课入口已开启」改为「调试入口已开启」。旧 showSelect 语义收敛为“仅控制调试”。

### 3. 白名单/黑名单提示精简
- `lib/ui/profile/usage_page.dart`：「抢课白名单」=“仅名单内学号可抢课”；「更新黑名单」=“名单内学号屏蔽更新”。

### 4. 功能接入审查（非空壳确认）
逐一核对输入→接口→展示链路均为真实调用：
- 课表/成绩/考试/学业：各页面 `watch(timetable/grades/exams/academicProvider)` → 对应 Api.fetch → `JwClient`(Dio 真实请求) + 离线缓存。
- 抢课：手动 `_grab` 与自动 `_runAutoGrab → _tryGrabCourse` → `queryJxbDetail/submitChoose`（真实 HTTP，含重试）。
- 云控：profile 抢课入口、select_page 门禁共用 `featureGatesProvider → /gates`；更新黑名单在 `update_page` 读取同一门控。
- 通知：课表加载 `scheduleLessons`、考试页 `scheduleExams`、设置变更 `reschedule` → 原生 AlarmManager/Notification；点击携带 page 跳 tab。
- 调试：日志(AppLog) / 测试通知(原生 testNotify) / 保留天数。
- 更新：`UpdateApi.checkLatest`(GitHub) + 黑名单拦截 + 下载安装(原生 install)+装后清包。
用户统计/白名单：`usageCountProvider`、`fetchPermList/managePermList → /perm`。
结论：功能均已接入真实接口，存在相互依赖关系（门控、通知、缓存、黑名单联动），无空壳。

### 验证
- `flutter analyze`：无 error/warning。
- `flutter build apk --debug`：构建通过。

---

## 2026-08-31 · 云控模型调整（白名单/黑名单）/ 作者卡片换行

### 1. 关于页作者卡片
- `lib/ui/profile/about_page.dart`：作者信息拆为两行 —— 第一行「开发者」，第二行「@机械工程学院」，右对齐顶部一致（左对齐）。

### 2. 云控模型调整：抢课白名单 + 更新黑名单，调试/统计去云端化
策略变化：云端只管理「抢课白名单」与「更新黑名单」；「调试」改回「连点版本号 5 次」本地开关；「用户统计」仅管理员账号（2024********）可见。
- 后端 `cf-worker/worker.js`
  - `FEATURES` 缩减为 `select`(抢课白名单)、`update`(更新黑名单)。
  - `ALLOW` KV 的 cfg 同时存白名单 `{"select":[...]}` 与黑名单 `{"block_update":[...]}`。
  - `GET /gates?xh=` 返回 `{select, updateBlock}`。
  - `GET/POST /perm` 增加 `type=allow|block`（默认 allow），管理白/黑名单。
- `lib/api/usage_api.dart`
  - 常量收敛为 `featureSelect/featureUpdate` 与 `gateSelect/gateUpdateBlock`。
  - `fetchGates` 返回 `{select, updateBlock}`；`fetchPermList(feature,{block})`、`managePermList({feature,block,action,xh})`。
  - `canAccessSelect` 改读 `/gates`。
- 入口逻辑
  - `lib/ui/profile/profile_page.dart`：用户统计仅 `ownerXh` 显示；抢课= `showSelect && gates[select]`；检查更新人人可见（黑名单用户在更新页被拦截）。
  - `lib/ui/profile/settings_page.dart`：「调试」入口恢复为 `showSelect`（连点版本号开关），移除云端 debug 门控。
  - `lib/ui/profile/update_page.dart`：检查更新前先读 `gates[updateBlock]`，命中黑名单则直接显示「已是最新」。
- 管理页 `lib/ui/profile/usage_page.dart`
  - 原单选功能 SegmentedButton 区改为两个独立 Card：**抢课白名单**（仅白名单内学号可用，管理员恒可用）与**更新黑名单**（命中即屏蔽更新）；各自输入学号增删、刷新。
  - 复用组件 `_PermListSection(title,hint,feature,block)` 与 `_PermTile(badge)`。

*验证：对同一学号 add 白名单 select → gates.select:true；add 黑名单 update(type=block) → gates.updateBlock:true；两名单独立，移除后恢复全 false。*

### 验证
- `flutter analyze`：无 error/warning。
- Worker 已部署（Version a77ebbf5...）。
- `flutter build apk --debug`：构建通过。

---

## 2026-08-31 · 功能级云控 / 通知跳转 / 作者卡片

### 1. 云控升级为功能模块级白名单
目标：管理员在 APP 内可按功能模块（抢课/调试/用户统计/更新）对单个用户下放/收回授权，白名单用户显式展示入口。开发者本人恒放行。

- 后端 `cf-worker/worker.js`
  - 白名单存储改为 `ALLOW` KV 的 key="cfg"，值为 JSON：`{"select":[...],"debug":[...],"stats":[...],"update":[...]}`。
  - 新增 `GET /gates?xh=..`：一次返回该学号全部功能授权（{feature: bool}）。
  - `GET /permission?feature=&xh=`：单功能授权查询（默认 select，兼容旧调用）。
  - `GET/POST /perm`：管理接口增加 `feature` 字段（默认 select），返回 `{ok, feature, list:[...]}`。
- `lib/api/usage_api.dart`
  - 新增受控功能 key 常量：`featureSelect/Debug/Stats/Update` 与 `features` 列表。
  - `canAccessSelect` → `canAccess(feature, xh)`。
  - 新增 `fetchGates(xh)`：一次拉取全部功能授权。
  - `fetchPerm(feature)`、`managePerm({feature, action, xh})`，返回字段 `whitelist`→`list`。
- `lib/providers/data_providers.dart`
  - `selectGateProvider` → `featureGatesProvider`（返回 `Map<feature, bool>`）。
- 入口门控
  - `lib/ui/select/select_page.dart`：抢课门禁用 `featureGatesProvider` 的 `select`。
  - `lib/ui/profile/profile_page.dart`：入口按门控显示 —— 用户统计=stats、抢课=showSelect&&select、更新=update；关于与设置恒显。
  - `lib/ui/profile/settings_page.dart`：「调试」入口由 `showSelect` 改为 `debug` 门控。
- `lib/ui/profile/usage_page.dart`：白名单管理页新增功能模块 SegmentedButton（抢课/调试/用户统计/更新），切换后增删对应功能的授权学号。

*验证：`/gates` 初始全 false；对该学号仅下放 stats → gates 中 stats:true 其余 false；移除后恢复全 false。*

### 2. 关于页作者卡片
- `lib/ui/profile/about_page.dart`：「开发者」改为「开发者@机械工程学院」；右侧院徽仅保留图片（40px，随卡片上下居中），移除下方小字。

### 3. 通知栏点击跳转对应页面
- 原生
  - `android/.../NotificationHelper.kt`：上课提醒 PendingIntent 带 `page=0`(课表)，考试 `page=2`(考试)；`show()` 的通知点击 Intent 改用 `MainActivity` 并携带 `page` extra。
  - `android/.../NotifyReceiver.kt`：透传 `page` 到通知。
  - `android/.../MainActivity.kt`：新增 `onNewIntent`（更新 intent）+ `cn.gdou.xiuhong/nav` 通道的 `getLaunchPage`。
- `lib/ui/home/home_shell.dart`：作为 `WidgetsBindingObserver`，应用 resumed 或冷启动时调用 `getLaunchPage` 读取页码并切换底部 tab（0课表/1成绩/2考试/3学业/4我的）。

### 验证
- `flutter analyze`：无 error/warning。
- Worker 已重新部署（Version ID 576f...）。
- `flutter build apk --debug`：构建通过。

---

## 2026-08-31 · 六项 UI / 功能 / 瘦身调整

### 1. 建立修改记录文档
- 新增 `docs/modification_log.md`（本文件）。约定：每次变更后在此追加一节，写明日期、涉及文件、改动内容与原因。

### 2. 关于页
- `lib/ui/profile/about_page.dart`
  - 技术栈卡片删去「统计后端 Cloudflare Workers + KV」一行（后端细节不再展示在主技术栈）。
  - 开发者卡片右侧院徽由 72px 缩小为 40px（略小于开发者头像 52px），并在其下方增加一行灰色小字「机械工程学院」。

### 3. 检查更新页
- `lib/ui/profile/update_page.dart`
  - 移除「前往发布页查看」按钮及其 `launchUrl` 方法；`checkLatest` 返回的 url 用 `_` 忽略。

### 4. 测试通知改为最新通知权限通道
- `android/.../MainActivity.kt`
  - notify MethodChannel 的 `requestAlarmPerm`（精确闹钟引导）分支替换为 `testNotify`：仅需通知权限，用 `NotificationHelper.show` 即时发一条测试通知。
  - 删除不再使用的 `import android.app.AlarmManager`。
- `lib/util/lesson_notifier.dart`
  - 删除 `requestAlarmPerm()`；新增 `requestPerm()`（仅通知权限）。
  - `triggerTest()` 改为调用原生 `testNotify`，不再依赖闹钟排程 / 精确闹钟权限。
- `lib/ui/profile/debug_page.dart`
  - 「发送测试通知」改调 `requestPerm()` + `triggerTest()`，提示文案更新。

### 5. 日志系统接入新增功能
- `lib/ui/select/select_page.dart`：`_runAutoGrab` 记录触发、轮次、结束；`_tryGrabCourse` 记录成功 / 满员 / 失败 / 异常（tag「自动抢课」）。
- `lib/ui/select/auto_grab.dart`：`AutoGrabStorage.load/save` 记录计划加载 / 保存 / 清除（tag「自动抢课」）。
- `lib/ui/profile/update_page.dart`：`_check`、`_download` 记录检查结果与下载（tag「更新」）。
- `lib/api/usage_api.dart`：`managePerm` 写操作成功时记录白名单增删（tag「风控」，计人数）。

### 6. 代码瘦身（清理弃用 / 无用代码）
- `lib/api/auth_api.dart`：删除未使用常量 `_imageW`。
- `lib/api/jw_apis.dart`：
  - 删除 `_parseOverview(html)` 调用及其整个方法（旧页面口径解析，已由「学分完成情况」页逻辑取代）。
  - 删除无调用者的 `CourseSelectApi.quickSelect`（旧批量快选，已由 `submitChoose` 取代）。
- 移除精确闹钟相关代码（见第 4 项），`flutter analyze` 由 5 项下降至 2 项 info（均为 `prefer_interpolation`，不影响编译）。

### 验证
- `flutter analyze`：无 error / warning。
- `flutter build apk --debug`：构建通过。

## 2026-11-23 · 动效重做 / 手动刷新 / 课表吸顶等八项

### 1. 页面与弹层动效（参考 Android 17）
- `lib/theme/ink_page_transition.dart`
  - 新页面：淡入 + 自下 3% 上移 + 0.96→1 回弹缩放（`Curves.easeOutBack` 只驱动缩放，避免透明度越界）。
  - 被覆盖页面：缩小至 0.94 + 压暗至 0.70，模拟系统「容器后退」；首屏不做入场，但被二级页覆盖时同样后退。
  - 退出沿用反向曲线，快速收回、不回弹。
  - `AndroidManifest.xml` 增加 `android:enableOnBackInvokedCallback="true"`。
- `lib/ui/widgets/ink_page.dart`
  - `showInkSheet` 增加 `sheetAnimationStyle`（320ms 长尾减速，收起 160ms）。
- `lib/ui/widgets/ink_dialog.dart`
  - 改用 `showGeneralDialog`，淡入 + 0.92→1 弹性缩放，遮罩 32% 黑。
- `lib/theme/ink_tokens.dart`
  - 新增 `InkMotion.sheet/spring/decelerate`。

### 2. 去掉刷新按钮，统一下拉刷新
- `lib/ui/widgets/common.dart`：新增 `InkRefresh`（支持空态/错误态 fill 撑满一屏），删除 `BusyRefreshButton`。
- 成绩、考试、学业、抢课、用户统计、日志页移除刷新按钮，改为下拉刷新；用户统计下拉时同步重建两份名单区块；抢课空态文案改为「下拉刷新」。

### 3. 去掉返回小三角 + 边缘手势返回
- `lib/ui/widgets/ink_page.dart`
  - `InkPageScaffold` 不再渲染返回箭头；二级页无操作按钮时直接使用大标题，不再留空 AppBar。
  - 新增 `_EdgeBackSwipe`：屏幕左缘 32dp 内起手右滑超过 22% 屏宽或快速甩动即返回，拖动时页面轻微跟手。

### 4. 导航栏更通透
- `lib/theme/ink_tokens.dart`：`glassNavFill` 亮色 62%→47%、暗色 56%→42%；`navBlur` 24→28 保证文字可读。

### 5. 课表星期表头吸顶
- `lib/ui/timetable/timetable_page.dart`
  - 拆分 `_buildTimetable` / `_buildDayHeader` / `_buildGrid`：星期与日期表头移出滚动区，周次栏原本即固定在滚动区外，上下滑动只滚动课程网格与实践课程。

### 6. 课表卡片与字号放大
- 行高 58→66、左侧时间列 44→48；课程名字号 10→11.5（最多 4 行，行高 1.18），教室字号 10，卡片内边距 5→6，日期圆点 radius 13→14；大节时间字号 11.5/10.5。
- 课表主体补下拉刷新（`RefreshIndicator`），与横向切周手势互不影响。

### 7. 绩点结果卡片重做
- `lib/ui/grade/grade_page.dart`：`_SummaryCard` 改为渐变信息底色卡片，学分绩点 38sp 主数字、右侧加权平均 24sp，底部分隔后横排「获得学分 / 课程门数」。

### 8. 我的页学籍与功能区分
- `lib/ui/profile/profile_page.dart`：学籍卡叠加极淡信息色底；院系/专业/年级/班级图标分别用 info/success/warning/neutral 色调，功能入口保持统一主色。

### 9. 关于页技术栈与许可
- `lib/ui/profile/about_page.dart`：技术栈更新为 Flutter·Dart / Riverpod / Dio·Cookie / SharedPreferences / PointyCastle·UUID / Kotlin 原生通道·WebView；新增「开源许可」：项目 GPL-3.0，并列出 Flutter·Dart、Riverpod、Dio·cookie_jar、PointyCastle、SharedPreferences·PathProvider、uuid·Cupertino Icons、WebView Flutter 及其许可证。

### 验证
- `flutter analyze`：无 error / warning。
- `flutter test`：通过。
- `flutter build apk --release --target-platform android-arm64 --build-number=2025`：构建通过并安装至真机验证（课表吸顶/卡片、学籍区分、绩点卡、关于页、边缘返回、导航透明度）。

## 2026-11-23 · 校外通道：APP 自带隧道（无需额外软件）

### 背景
校园教务只在校内网可达，其他同学不可能都装 Tailscale/aTrust。改为 APP 内自带通道：
WebView / Dio → 手机本地 CONNECT 代理 → WSS → 飞牛（校园网内）→ 原样转发到教务。
统一身份认证的滑块、短信验证码、JS 加密与 SSO 跳转全部保持真实流程，服务端不代登录。

### 1. 后端隧道（`backend/server.js`）
- 新增 `const net = require('net')`、`TUNNEL_TARGETS`（仅 `jw/authserver` 的 80/443）、RFC6455 握手与帧编解码（客户端帧校验掩码、126/127 长度、Ping/Pong/Close、分片合并）。
- `server.on('upgrade')` 路由 `/tunnel?host=&port=`：先用现有 `Authorization: Bearer` 校验会话（无效 401），再查目标白名单（越界 403），通过后回 101 并 `net.connect` 双向转发。
- `tcp.setNoDelay(true)`；关闭时改为「写 Close 帧 → `socket.end()`」，修复原先 `destroy()` 丢掉「响应后立即断开」的末尾数据（教务 302 会整包丢失）。

### 2. APP 本地代理（`lib/util/campus_tunnel.dart` 新增）
- `ServerSocket.bind(127.0.0.1, 0)` 起本地 CONNECT 代理，解析目标 host:port 并与后端同白名单。
- 每个连接先 `UsageTracker.tokenFor(xh)` 取会话，`WebSocket.connect(wss://api.example.com/tunnel?... , headers: authorization)`；首次失败作废会话并重认证一次。
- WebSocket 与本地 Socket 双向转发；对方关闭时 `flush()` 后再断开，避免末尾响应被丢弃。
- 兼容 WebView 的明文请求：绝对 URI（`GET http://host/path`）会还原成源站请求行再转发，覆盖认证页 302 到 `http://authserver` 的回跳。

### 3. WebView 走隧道（`lib/util/webview_proxy.dart` 新增 + `MainActivity.kt`）
- `androidx.webkit` 的 `ProxyController.setProxyOverride(127.0.0.1:port)` / `clearProxyOverride`，经 MethodChannel `cn.gdou.xiuhong/proxy` 调用；只影响本应用 WebView。
- 反向 bypass：只有 `jw.gdou.edu.cn` / `authserver.gdou.edu.cn` 走隧道，页面引用的第三方 CDN 等资源保持直连，避免被代理拒绝。
- `MainActivity.kt` 新增 `setProxy` / `clearProxy` 分支；`build.gradle.kts` 增加 `androidx.webkit:webkit:1.11.0`。

### 4. 教务 Dio 走隧道
- `lib/api/jw_client.dart` 新增 `setProxyPort(port)`：`IOHttpClientAdapter` + `HttpClient.findProxy = PROXY 127.0.0.1:port`。
- `lib/api/usage_api.dart` 新增 `tokenFor(xh)` / `invalidateSession()`。

### 5. 登录页自动切换（`lib/ui/login/sso_login_page.dart`）
- 主框架加载失败，或 8 秒仍无进展时，自动启动本地代理、接管 WebView 与 Dio 代理后重载认证入口；只尝试一次，再失败才显示错误页。
- 校外首次登录（本地还没有学号）会先弹窗填写学号，仅用于隧道设备认证，之后仍走学校真实登录页。

### 验证
- 云端（公网 WSS，有效会话）实测：`authserver:80` 返回 200 认证页；`jw:80` 返回 302；`jw:443` 完成 TLSv1.2 握手并返回 302 到认证中心；非白名单目标被拒。
- 测试用临时学号与设备公钥已从线上数据移除，`haipan.json` 恢复原状（仅管理员设备）。
- `flutter analyze`：No issues found；`flutter test`：通过。
- build 2037 首次打包；补齐关闭时序、明文请求、学号补录与反向 bypass 后，build 2040 重新打包；通道全局自适应后 build 2041 为当前交付包（22.9MB，桌面 `haipan-2041.apk`）。

### 2041：通道改为全局自适应
真机在移动数据下仍报 `jw.gdou.edu.cn` 连接被拒：通道原先只在统一认证页失败后启动，
已登录用户直接进「抢课」等页面不会经过登录页，Dio 仍是直连。
- `CampusTunnel.adapt(client, xh:)`：先探测 `jw:443`，校内直连可用则什么都不做；不可用则启动本地代理并同时接管 Dio 与 WebView。启动期由 `SessionNotifier._restore` 调用（不反读会话，避免构建期循环依赖）。
- `JwClient.onConnectionError`：教务请求出现 `connectionError/connectionTimeout` 时启用通道并自动重试一次（请求带 `tunnelRetry` 标记防死循环），覆盖「校内启动后切到移动数据」。
- 启动流程在 `main._warmup` 注入上述回调。
- build 2041 打包（22.9MB），analyze/test 通过。

### 2042：修复隧道连接全部失败（单订阅 Socket）
真机日志（10:11:05 / 10:11:14）出现 `Bad state: Stream has already been listened to`
（`_Socket.listen`）：本地代理先用 `socket.listen` 读请求头，取消后再 `listen` 转发，
而 Socket 流只能订阅一次，导致每条隧道连接都在建连后立即异常，认证页依旧打不开。
- `_accept` 改为**单一监听器**贯穿整个连接：未建好隧道前解析请求头，建连期间 `pause()`，
  WebSocket 就绪后 `resume()`，后续数据直接写入 WebSocket。
- 建连期间收到的数据暂存 `pending`，就绪后补发，避免 DNS/TLS 等慢建连时丢首包。
- 失败路径统一 `sub.cancel()` + flush 关闭，并清理连接集合。
- build 2042 打包（22.9MB），analyze/test 通过。
## 2026-11-23 · 体验优化：缓存优先、动画提速、关于页改版

### 1. 缓存优先（stale-while-revalidate）
- `lib/providers/data_providers.dart`：`timetableProvider` / `gradesProvider` / `examsProvider`
  由 `FutureProvider` 改为 `AsyncNotifierProvider`。
  - `build()` 先读 `LocalCache`（key：`cache_timetable_/cache_grade_/cache_exam_{xnm}_{xqm}`），
    命中则立即返回缓存并 `unawaited(_silentRefresh())` 后台静默拉取；未命中才在线请求。
  - 新增 `refresh()`：下拉刷新强制在线，成功后 `state = AsyncValue.data(...)`；
    失败且当前无数据时才置 error，并 `rethrow` 保留原有的错误提示。
- 页面侧 `onRefresh` / `onRetry` 改为调用各 Notifier 的 `refresh()`：
  `timetable_page.dart`、`grade_page.dart`、`exam_page.dart`。
- 冷启动/切学期先看到上次数据，随后自动替换为最新数据。

### 2. 登录保持时长与认证方式（说明）
- 登录走学校统一身份认证 `authserver.gdou.edu.cn`（WebView，滑块/短信/JS 加密均由学校页面完成），
  成功后把教务域 Cookie 注入 Dio。
- 学校下发的是会话 Cookie（无 expires），APP 显式按 30 天写入 `PersistCookieJar`；
  实际是否仍有效以教务系统服务端会话为准，失效后探针会引导重新登录。
- 云端 API 另用 ECDSA 挑战应答换取会话，内存态 30 分钟，过期自动重认证。

### 3. 关于页改版（`lib/ui/profile/about_page.dart`）
- 删除「数据来源」项。
- 「当前版本」显示 `v1.0.0 · build 2044`（构建号来自原生通道）。
- 应用图标卡下方新增 4 个彩色小标签：课表同步 / 成绩查询 / 考试提醒 / 离线可用。
- 末尾新增「免责声明」：不存储账号密码与成绩到服务器、仅提供统一认证登录入口、
  数据以学校官方为准。

### 4. 原生 appInfo（`MainActivity.kt`）
- 新增 MethodChannel `cn.gdou.xiuhong/app` 的 `appInfo`：返回 `version`（versionName）与
  `build`（longVersionCode，API<28 回退 versionCode）。

### 5. 页面退场动画提速（`lib/theme/ink_page_transition.dart`）
- `InkPageRoute` 覆写 `transitionDuration = 200ms`、`reverseTransitionDuration = 120ms`；
  全部 `MaterialPageRoute` 已替换为 `InkPageRoute`，返回上一页更干脆。

### 6. 其他交互
- 退出登录卡下方恢复灰色小字 `Powered By XIUHONG`（`profile_page.dart`）。
- 通识课固定 7 类：人文艺术类、大数据及信息技术类、外语拓展类、科研与创新教育类、
  科技文明与海洋科学类、农业发展与生态文明类、道德法律与经济管理类；按
  `kcgsmc + kclbmc + kcmc` 归一化匹配，空分类保留，其余归入「其他」（`ge_credit_page.dart`）。
- 选课抢课页打开即弹「功能暂停开发」，关闭后退回上一页（`select_page.dart`）。
- 成绩详情弹窗数据到达后用 `TweenAnimationBuilder` 做 260ms 淡入+上移动画（`grade_page.dart`）。

### 验证
- `flutter analyze`：No issues found。
- `flutter test`：All tests passed。
- APK：build 2044 构建并复制至桌面。

## 2026-11-23 · 清理抢课、通识在修、通知卡顿与浏览体验

### 1. 彻底移除选课/抢课与抢课黑名单
- 删除 `lib/ui/select/select_page.dart`、`lib/ui/select/auto_grab.dart`。
- `jw_apis.dart` 删除 `CourseSelectApi` 与 `courseSelectApiProvider`；`models.dart` 删除
  `CourseSelectStatus`；`data_providers.dart` 删除 `selectStatusProvider`。
- `profile_page.dart` 移除「选课 / 抢课」入口与门控查询；`session_provider.dart` 移除失效。
- `usage_api.dart` 移除 `featureSelect / gateSelect / canAccessSelect`，`fetchGates` 只保留
  更新黑名单与 APP 准入；`usage_page.dart` 移除「抢课黑名单」管理区。
- `settingsProvider` 的 `showSelect` 重命名为 `showDebug`（持久化 key 不变），
  关于页连点 5 次版本仍可开关调试入口。

### 2. 通识拓展学分补全「在修」
- `ge_credit_page.dart`：
  - `_isGe` 放宽：`KCLBMC` 含通识/拓展，或 `KCGSMC` 能匹配七类之一（在修课程类别常为空）。
  - 结合本学期 `timetableProvider` 的课程名，把学业接口仍标为「未修」的同名课程校正为
    「在修」，使在修学分与分类计数正确。
  - 仍按 `kcgsmc + kclbmc + kcmc` 归类，七类固定展示。

### 3. 通知排程卡顿
- `MainActivity.kt`：`scheduleLessons / scheduleExams` 改到单线程 `notifyExecutor` 后台执行，
  Flutter 主线程不再等待。
- `NotificationHelper.kt`：取消闹钟从遍历 1..500 改为只取消上次持久化清单中的 id。
- `lesson_notifier.dart`：`scheduleFromCache` 不再清空去重 key，避免冷启动与课表页重复排程。
- `ink_notice.dart`：Toast 的文本测量从每帧执行改为 `didChangeDependencies` 计算一次缓存，
  修复通知浮层掉帧。

### 4. 关于页
- 彩色标签移入应用图标卡内；应用版本（v1.0.0）与构建版本（如 2045）分两行展示；
  应用信息页也拆成「应用版本 / 构建版本」两行。

### 5. 调试页排版
- 「日志保留」行使用紧凑 SegmentedButton（最小高度 32、字号 12），不再换行。
- 移除「公网通道」卡片的副标题小字。

### 6. 空教室浏览体验
- 结果区新增本地「筛选教室名 / 楼栋」输入框与「只看可借」开关，不重复请求教务。
- 结果按教学楼分组为可折叠卡片，默认只展开第一栋；组内按教室名自然排序。
- 移除每页 20 条的分页，改为按需展开，减少一次渲染数量。

### 验证
- `flutter analyze`：No issues found；`flutter test`：All tests passed。
- 构建 build 2045 并覆盖安装到真机。

## 2026-11-23 · 定稿前全量审计（数据获取 / 提醒 / 缓存隔离）

### 1. 考试时间解析（P1，功能实际失效）
- 教务 `kssj` 实为 `2026-12-30(10:10-12:10)`，`DateTime.tryParse` 全部返回 null，
  导致考试倒计时不显示、考试提醒永远 0 条。
- `models.dart` 新增 `parseJwDateTime()` 与 `Exam.startAt`；`lesson_notifier.dart`、
  `timetable_page.dart`（今日卡倒计时、考试日期）统一改用该解析。

### 2. 跨学期 / 跨账号错排提醒（P1）
- 课表页可浏览历史学期，但提醒按“当前学期”估算周次：历史课表会被当成本周课程排提醒。
  → 仅当课表所选学期 == 当前学期时才 `scheduleLessons`，且“今日”卡片只在当前学期展示。
- 考试页无数据会自动回退上一学期，原逻辑会把该学期考试当全局提醒并清空本学期提醒。
  → `scheduleExams` 仅在考试页学期 == 当前学期时调用。
- 退出登录后旧账号提醒仍会弹出。→ `LessonNotifier.setSessionActive(false)`：
  原生 `cancelAll` 取消全部闹钟并清空持久化清单；登录/恢复会话时置 true。
- 冷启动 `scheduleFromCache` 增加登录态判断，并按本学期待考试缓存补齐考试提醒。
- 课表提醒去重 key 由“课程数”改为课程内容指纹，避免同小时内课表刷新（换教室/时间）漏更新。

### 3. 账号切换数据隔离（P1）
- 本地缓存（课表/成绩/考试/学业）不区分学号，A 退出后 B 登录会先看到 A 的缓存。
  → `_completeLogin` 以课表实际学号为准（不再用上一个账号的 savedUsername），
  检测到 `prevUser != effectiveUser` 时清空 `cache_*` 并取消旧提醒。
- APP 准入离线回退缓存改为按学号隔离（`usage.app_allowed.<xh>`），
  避免 A 有权限、B 无权限时离线继承 A 的准入。
- 门控查询加 6s 超时，后端不可达时回退本学号上次结果，避免长时间卡在“正在校验”。

### 4. 学分口径修正（P1）
- 不及格课程原先同时计入“已通过”与“未通过”，且“获得学分”把不及格学分也算了。
- `Grade.isPassed`、`AcademicCourse.passed/failed`；成绩汇总“获得学分”、
  学业总览 passed/failed、通识分类与总已修学分均只统计真正通过的课程。
- 学业接口去重 key 补上 `kclbmc/kcgsmc/xdz/xf/cj`，避免不同类别同名课程被误合并漏计。

### 5. 其他
- 通识页改用 `currentTimetableProvider`（固定当前学期），不再受课表页所选历史学期影响；
  不及格课程状态标签显示为「未通过」。
- 修改开学日后 `setSemesterStart` 自动重排提醒（原来周次变了提醒不更新）；
  修复 `copyWith(semesterStart: null)` 无法清除自定义开学日的问题。
- 空教室按楼分组增加 `ValueKey`，筛选模式下“全部展开”能立即生效。
- 移除使用记录页残留的“抢课”文案。

### 验证
- `flutter analyze`：No issues found；`flutter test`：All tests passed。
- `flutter build apk --release --target-platform android-arm64 --build-number=2046`：通过（22.6MB），
  已复制到桌面 `haipan-2046.apk`；`adb devices` 为空，未安装。

### 定稿前仍需确认
- GitHub 更新接口 `QingYu327/GDOU-APP`（代码内配置）`/releases/latest` 返回 404，
  “检查更新”不可用；需确认仓库地址并发布 Release。
- APP 准入为默认拒绝（`allow_app` 白名单）：未在名单内的学号登录后会被拦截，
  且未登录时后端不可达会一直显示“正在校验/无权限”；公测前需确认是否改为默认放行。
- 拒绝页展示管理员学号，公测前建议换成联系方式/群号。

