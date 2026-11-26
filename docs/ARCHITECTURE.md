# 技术架构 · 海畔

> 面向开发与运维的现状说明书。版本基线：`1.0.1+4144`（2026-11-26）。
> 开工前先读 [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md)；踩坑与决策依据见 [LESSONS_LEARNED.md](LESSONS_LEARNED.md)。

## 1. 系统组成

| 组件 | 位置 | 职责 |
|---|---|---|
| Android 客户端 | `jw_app/` | 教务功能、离线缓存、桌面小部件、通知提醒 |
| 云端 API | `backend/server.js`（Node 20） | 设备认证、会话令牌、准入白名单、使用统计、隧道入口下发、WebSocket 隧道 |
| 部署机 | 飞牛 NAS `192.168.6.137` | Docker `haipan-api`，数据卷 `./data`；对外多路：国内直连 TLS、Cloudflare、东莞/深圳 FRP |
| 教务系统 | `jw.gdou.edu.cn` / `authserver.gdou.edu.cn` | 统一身份认证、课表/成绩/考试/学业等数据源 |
| 静态官网 | `site/`、`QingYu327/haipan-website` | 首页 / 使用文档 / 注意事项；Netlify 自动部署，Gitee 镜像同步 |

客户端不在校内时，`jw.gdou.edu.cn` 的请求经「本地 CONNECT 代理 → WebSocket 隧道 → NAS → 校园网」转发；登录页也经同一隧道加载 `authserver.gdou.edu.cn` 的原始页面（部分运营商直连 authserver 会被拒）。

## 2. 客户端分层

```
lib/
├── api/          网络层：jw_client(Dio+Cookie)、jw_apis、auth_api、usage_api、update_api
├── models/       数据模型（课表、成绩、考试、学业、排名…）
├── providers/    Riverpod 状态：session / settings / data_providers（在线优先 + 离线缓存）
├── theme/        水墨视觉体系（ink_tokens / ink_panel 等）
├── ui/           home / login / timetable / grade / exam / academic / rank / profile / onboarding / widgets
└── util/         隧道、代理、设备认证、缓存、日志、提醒、刷新闸门、服务器选路、build_info
```

原生侧（`android/.../cn/gdou/xiuhong/`）：

| 文件 | 作用 |
|---|---|
| `MainActivity.kt` | 设备认证（Keystore EC P-256）、通知通道、权限、WebView 代理、小部件刷新通道 |
| `ScheduleWidgetBase.kt` | 小部件共用渲染：尺寸/字号/行数/考试区块 |
| `TodayWidgetProvider.kt` | 「课表 + 考试」组件（默认 4×3） |
| `ScheduleOnlyWidgetProvider.kt` | 「今日课表」仅课表组件（默认 4×2） |
| `NotificationHelper.kt` / `NotifyReceiver.kt` / `BootReceiver.kt` | 闹钟提醒、开机恢复 |

MethodChannel：`cn.gdou.xiuhong/auth`（设备密钥）、`cn.gdou.xiuhong/proxy`（WebView 代理）、`cn.gdou.xiuhong/widget`（刷新小部件）。

## 3. 认证体系

### 3.1 教务会话

- 正方教务为**纯 Cookie 鉴权**，`Dio + PersistCookieJar` 持久化；密码只在提交时经原生 AES 加密，不上传。
- 登录页优先走原生统一身份认证表单（学号 + 密码 + 验证码 / 多因子）；失败时可切 WebView 认证页兜底。
- 校外登录页经隧道加载 `authserver.gdou.edu.cn`，登录成功后 CAS 按 `service` 回跳 jw；成功拉课表后取学籍。

### 3.2 设备认证与云端令牌

公网隧道和云端接口都需要令牌，流程如下：

```
App                         云端 /device/register        Keystore
 │ 1. publicKey（首次生成 P-256）──▶ 幂等登记（公钥不一致=覆盖旧绑定）
 │ 2. POST /auth/challenge ─────▶ 返回一次性挑战码（2 分钟）
 │ 3. 私钥签名挑战码（签名不出安全硬件）
 │ 4. POST /auth/verify ────────▶ 校验公钥签名 → 30 分钟令牌
 │ 5. 令牌用于 /tunnel、/gates、/permission、/perm、/notes
```

- 私钥常驻 Android Keystore，Flutter 只能取公钥与请求签名；反编译拿不到私钥。
- 名单内学号换机或清空应用数据后生成新密钥，`/device/register` 直接覆盖旧绑定，并让该学号的旧会话全部失效（同一学号同时只有一台设备可用）；管理页仍可手动重置设备。
- 客户端本地对 `ownerXh` 有 APP 门控例外，但**不能绕过**设备认证。

### 3.3 更新检查与版本源

- 更新源是 GitHub `releases/latest`，取 assets 中第一个 `.apk`；镜像前缀 `v6.gh-proxy.org`，失败回退直连。
- 运行版本不再手写：`lib/util/build_info.dart` 通过 `cn.gdou.xiuhong/app` 读取安装包 `versionName` / `versionCode`。
- `UpdateCheckResult` 显式返回 `hasUpdate` / `isCurrent`：首页只在 `hasUpdate && downloadUrl` 时弹窗，更新页用 `isCurrent` 展示发布说明。
- 发布前用 `tool/check_version.ps1 -Tag v<版本>+<构建号>` 校验 pubspec 与 tag；Release 资产名固定 `haipan-app-release.apk`。

### 3.4 准入白名单

- 名单只存在云端 `cfg.allow_app`（`$DATA_DIR/haipan.json`），从不下发。
- 客户端本地仅缓存判定结果 `usage.app_allowed.<学号>`（按学号隔离），清空数据即失效。
- 管理页增删名单走 `/perm`；把学号移出名单会同时删除其设备绑定。

## 4. 公网隧道

### 4.1 入口与选路

- 入口列表可由云端 `/tunnel/endpoints` 下发并本地缓存，换域名无需发版。
- `ServerConfig.autoSelect()` 启动时并行测速，仅在「当前不可达 / 快 200ms 以上 / 快过 1.5 倍」时切换，10 分钟内不重复测速，避免抖动。
- 当前下发入口：国内直连（阿里云 TCP 穿透 `8.148.27.215:48644` → NAS `18443` TLS）、Cloudflare `haipan-api.cjhong.top`、东莞 `frp-ski.com:38169`、深圳 `120.79.176.77:59192`；客户端按延迟自动选路，换域名只需管理员下发。
- **国内直连**（Batch35）：阿里云 TCP 穿透 `8.148.27.215:48644` → NAS `18443` → 容器 `8443`，只跑自签 TLS。没有域名可用（未备案会被阿里云拦截），因此客户端用证书指纹固定（`lib/util/tls_pin.dart`）代替 CA 校验；该端口不响应任何明文 HTTP，另有限频、并发上限、失败拉黑和固定子协议 `haipan-v1` 四项防护。证书持久化在 `data/tls/`，轮换时必须同步更新指纹并发版。

### 4.2 隧道与本地代理

- `CampusTunnel` 在本机 `127.0.0.1:随机端口` 起 CONNECT 代理。
- **默认走复用通道**：一条 `wss://<host>/tunnel-mux` 长连接承载多条教务 TCP 流，帧格式 `[type:1][streamId:4][payload]`（1=OPEN / 2=DATA / 3=CLOSE / 4=PING / 5=PONG），20 秒应用层心跳保活。
  - 每条 CONNECT 只需发一个 OPEN 帧，不再重复 TCP+TLS+WS 握手；这是公网高延迟下最主要的提速点。
  - 服务端 `/tunnel-mux` 维护 `streamId → TCP` 映射，目标域名仍受白名单限制。
- **回退**：若 `/tunnel-mux` 不可用（旧服务端/建连失败），自动回退旧的 `wss://<host>/tunnel?host=...` 单连接模式，并在 3 分钟内不再尝试复用，确保登录链路可用。
- **`jw.gdou.edu.cn` 与 `authserver.gdou.edu.cn` 走隧道**。校外登录页加载 `https://authserver.gdou.edu.cn/authserver/login?service=…jw…` 的原始页面（经隧道，40s 加载超时）；登录成功后 CAS 按 service 回跳 jw，同样由隧道接管。
- wfw（`https://wfw.gdou.edu.cn/authserver/login`）虽然能反代出登录页，但登录 POST 会被弹回且页签是 authserver 绝对地址，**不作为登录入口**（Batch29 已移除）。
- 实现方式为反向 bypass：`ProxyController.setProxyOverride` 的 bypass 列表放 `jw.gdou.edu.cn` 与 `authserver.gdou.edu.cn`（列表内域名走本地代理，其余直连）；Dio 通过 `findProxy` 走同一代理。
- 注意 CAS 的 service ticket 与 `service` 参数绑定，登录入口的 `service` 必须始终指向 `https://jw.gdou.edu.cn/sso/jziotlogin`，不能借用 `wfw.gdou.edu.cn` 等其他服务的票据。
- 可达性实测：authserver 从 NAS/宽带可达（200，约 67ms），但部分手机运营商直连会被拒；jw 境外节点全部 `Connection refused`。
- 关闭顺序：先 flush 再 `socket.end()`，避免 302 响应末尾数据丢失。

### 4.3 高延迟优化

- 隧道复用：多条教务流共用一条 WSS，省掉每次 CONNECT 的握手（日志中 open/close 曾接近 1:1）。
- 自动刷新闸门：令牌/入口刷新串行化并限频，防止并发风暴。
- 认证失败**快速失败**，不做无意义重试；服务端明确拒绝（403/4xx）直接提示“学号验证失败”，只有超时/断网才归为“通道连接失败”。
- 登录页/首页在数据未就绪时展示加载动画遮罩，失败先自动重试，避免把底层错误码当界面内容。

## 5. 数据、缓存与刷新

- 统一走 `data_providers`：**磁盘缓存优先返回 + 后台静默刷新**，进页面秒开。
- 新鲜期 10 分钟（学业放宽到 30 分钟）；手动下拉刷新强制在线。
- 学业是「1 个索引页 + N 个计划 + 其他课程」的多请求流程：采用 **3 路有界并发**，每个计划失败/空结果再串行重试，兼顾高延迟吞吐与数据完整性。
- 缓存键按账号与版本隔离（如 `cache_academic_v2_<xh>_...`）；换账号清空 `cache_*`。
- 断网时读缓存；会话失效保留本地学籍与缓存，减少重登成本。
- 排名/空教室等筛选型查询带缓存，避免重复全量拉取。

## 6. 提醒与权限

- 上课/考试提醒走原生 `AlarmManager.setAlarmClock`，Doze 下更可靠；开机由 `BootReceiver` 恢复。
- 权限：首启一次性申请通知、精确闹钟、电池优化白名单等；跳过后可在设置内重新授权。
- 退出登录会取消全部提醒并清空持久化清单，避免旧账号提醒残留。

## 7. 桌面小组件

| 组件 | Provider | 默认尺寸 | 内容 |
|---|---|---|---|
| 今日课表 | `ScheduleOnlyWidgetProvider` | 4×2（250×110dp） | 今日课程 |
| 课表 + 考试 | `TodayWidgetProvider` | 4×3（250×180dp） | 今日课程 + 考试倒计时 |

渲染规则（`ScheduleWidgetBase`）：

- **字号只看宽度**：<210dp 用 14/10.5sp，≥420dp 用 18.5/13.5sp，其余 15.5/12sp；保证同宽组件字号一致。
- **高度只决定行数**：按可用高度估算，最多 8 行；课程超出显示「还有 N 门 · 点开查看」。
- 空余高度依次补充：明天第一门课（或「明天无课」）→ 第二场考试。
- 窄组件把时间并入地点行；两组件共用数据与刷新通道，App 内刷新同时更新。
- `previewImage` + `previewLayout` 提高在小组件面板中的可见性；桌面需刷新一次才能看到新尺寸。

## 8. 后端 API

| 方法 | 路径 | 鉴权 | 说明 |
|---|---|---|---|
| POST | `/device/register` | 无（白名单校验） | 登记设备公钥；管理员可覆盖旧绑定 |
| POST | `/auth/challenge` | 无 | 一次性挑战码（2 分钟） |
| POST | `/auth/verify` | 无 | 验签并签发 30 分钟令牌 |
| GET | `/health` | 无 | 健康检查 |
| GET/POST | `/tunnel/endpoints` | 令牌 | 读取/更新公网入口列表 |
| GET | `/gates` | 令牌 | APP 准入与更新黑名单 |
| GET | `/permission` | 令牌 | 当前账号权限 |
| GET/POST | `/notes` | 管理员令牌 | 学号备注 |
| POST | `/perm` | 管理员令牌 | 名单增删、重置设备等 |
| GET/POST | `/settings` | 管理员令牌 | 运行开关（设备自动换绑，默认开启） |
| WS | `/tunnel` | 令牌 | 单流隧道转发（回退模式） |
| WS | `/tunnel-mux` | 令牌 | 多路复用隧道（默认，一条连接承载多条 TCP 流） |

数据文件：`$DATA_DIR/haipan.json`（设备公钥、名单、备注、入口配置），容器内 `/data`，宿主机 `./data`。

## 9. 部署与运维（NAS）

- 实际 compose 目录：`/vol1/1000/docker/haipan-api`（以 `docker inspect` 的 `com.docker.compose.project.working_dir` 为准）。
- 代码是**构建进镜像**的（`build: .`）：改 `server.js` 后必须 `docker compose up -d --build`，`docker restart` 不生效。
- 校验：`docker exec haipan-api grep -c "<改动标记>" /app/server.js`。
- 端口：容器 8080 → 宿主 18080；对外由国内直连 TLS、Cloudflare、东莞/深圳 FRP 多路转发，入口由 `/tunnel/endpoints` 下发。
- 运维脚本在 NAS `ops/`：每日备份 `haipan.json`（保留 14 天）、5 分钟健康检查（状态变化才写日志）。
- 部署前先备份远端 `server.js`（如 `server.js.bak-<说明>`）。

## 10. 构建与发布

1. `cd jw_app && flutter analyze`（应无 issue）。
2. `flutter test`。
3. `.\tool\check_version.ps1`（发布前加 `-Tag v<版本>+<构建号>` 校验 tag）。
4. `flutter build apk --release --target-platform android-arm64 --build-number=<递增>`。
   - `android/gradle.properties` 已设 `force-version-code-ignoring-abi=true`：Flutter 默认会给单 ABI 包加偏移（arm64 +2000，2083 → 4083），这里强制 `versionCode` 等于构建号；升级安装时构建号需要大于手机上已有的 versionCode。
5. 安装真机验收：`adb install -r`；模拟器需 `--target-platform android-x64`。
6. 复制到桌面 `海畔_<版本>.apk`，交付链接用 `computer://`。
7. 后端有改动时同步部署 NAS 并验证 `/health` 与关键接口。

发布：Release 标签形如 `v1.0.1+<构建号>`，APK 资产名固定 `haipan-app-release.apk`，并标记 latest；官网下载直链与客户端更新都依赖该命名。

签名：`jw_app/android/upload-keystore.jks`，口令在 `jw_app/android/key.properties`（已 gitignore），务必备份以保证升级签名一致。

## 11. 目录速查

| 路径 | 内容 |
|---|---|
| `jw_app/lib/api` | 网络与接口封装 |
| `jw_app/lib/util/build_info.dart` | 安装包 versionName / versionCode 读取 |
| `jw_app/tool/check_version.ps1` | 发布前 pubspec / tag 一致性检查 |
| `site/` | 官网三页与共享样式脚本 |
| `jw_app/lib/util/campus_tunnel.dart` | 隧道 + 本地 CONNECT 代理 |
| `jw_app/lib/util/server_config.dart` | 入口列表、测速、自动选路 |
| `jw_app/lib/util/home_widget.dart` | Flutter 侧小部件数据刷新 |
| `jw_app/android/.../ScheduleWidgetBase.kt` | 小部件渲染核心 |
| `backend/server.js` | 云端 API + 隧道服务 |
| `backend/docker-compose.yml` | NAS 部署定义 |
| `docs/api-handoff/` | 教务接口权威契约与抓包校准 |
