# 项目总结 · 海畔（GDOU 教务客户端）

> 面向下一次类似项目的经验 / 教训 / 流程沉淀。**开工前先读这一份。**
> 现状架构与部署细节见 [ARCHITECTURE.md](ARCHITECTURE.md)；踩坑清单见 [LESSONS_LEARNED.md](LESSONS_LEARNED.md)。

## 1. 项目是什么

- 广东海洋大学教务系统的第三方 Android 客户端「海畔」，Flutter + Riverpod。
- 功能：课表 / 成绩 / 考试 / 学业 / 绩点排名 / 空教室 / 选课(抢课) / 检查更新 / 桌面小部件。
- 额外含一个自托管云端服务（`backend/server.js`，Node 20 + Docker，跑在飞牛 NAS）：设备认证、会话令牌、准入白名单、使用统计、公网入口下发与 WebSocket 隧道。早期 Cloudflare Worker 方案（`worker.js`）保留作历史。

## 2. 架构与关键决策

- **客户端**：`jw_app/`。Riverpod 做状态（`session / settings / data_providers`），`Dio + PersistCookieJar` 走正方教务**纯 Cookie 鉴权**（无 token，靠会话）+ 本地持久化 Cookie。
- **登录**：必须先 zfdun 滑块验证，再提交账号密码；密码用 RSA（Keystore 存），登录成功拉课表取学籍。
- **后端**：`backend/`（Node 20 + Docker）。负责设备公钥登记、挑战签名换 30 分钟令牌、APP 准入名单与更新黑名单、学号备注、入口下发，以及 WebSocket 隧道；数据持久化在 `$DATA_DIR/haipan.json`。支持 APP 内 `POST /perm` 免发版增删名单。
- **设备认证**：Android Keystore 生成 EC P-256 密钥对，私钥不出安全硬件；服务端按学号绑定公钥。管理员学号在公钥不一致时允许覆盖，普通用户需管理端重置。
- **公网访问**：校内直连；校外走「本地 CONNECT 代理 → WSS 隧道 → NAS → 校园网」。主通道 Cloudflare Tunnel、备用 ME Frp，客户端按延迟自动选路。
- **桌面小部件**：两个原生 Provider——「今日课表」4×2、「课表 + 考试」4×3，共用 `ScheduleWidgetBase` 渲染。
- **数据源与校准**：所有接口均从已登录网页抓包还原（见 `api-captures/` 与 `docs/api-handoff/`），不走私有文档。
- **包名** `cn.gdou.xiuhong`，应用名「海畔」。

## 3. 实测得出的重要经验（务必记住）

### 3.1 正方教务数据结构陷阱
- **学业「未修/在读」判定**：接口返回里，未修/在读课程的 `XNMC/XQMMC`（学年学期）字段**是空的**，无法用"当前学期"匹配去区分；真正权威的是 `XDZT` 字段：
  - `XDZT=4`（且有成绩）→ 已修 / 通过
  - `XDZT=1` → 在读（本学期）
  - `XDZT=3` → 未修（后续学期）
  - 教训：判断口径一定要先用真实抓包数据实证，别依赖对字段名的猜测。

### 3.2 GPA / 通过数会"跳变"的根因
- 学业数据由多个"学分要求计划"分接口拼装。**并发请求时，服务端会偶发丢弃整组计划**，导致通过数/GPA 在正确值（如 59/3.51）与残缺值（49/3.17）之间跳变。
- 修复：**改为串行逐计划请求 + 失败重试**，稳定复现抓包时"逐计划"的可靠路径。
- 教训：聚合型数据接口，宁可慢也要求准；并发要克制、要带重试和限速。

### 3.3 离线缓存的心智模型
- 先在线加载过一次 → 缓存 → 断网可看。
- 改动数据结构/判读口径后，**务必升级缓存键**（如学业 `cache_academic_v2_...`），否则旧错误数据会一直被读到，用户会以为没修好。
- "进页面秒开"：用 Notifier 做"磁盘缓存优先返回 + 后台静默刷新"，而非每次都等全量串行拉取。

### 3.4 分页与"服务端只返回前 N 条"
- jqGrid 接口默认 `showCount=20` 不翻页 → 看起来"无论条件都只有 20 条"。需要读 `records/total` 自动翻页 + 按主键去重。
- 空教室多选按服务器语义是 **AND**（须同时空闲），多选会让结果变空 → 客户端按"单时段逐查后合并(OR)"做用户体验兜底，但要**限速**（上限 30、间隔 200ms）避免短时间连发被判异常。

### 3.5 会话与通知
- 教务会话依赖服务端超时，无法永久保持；会话失效时要保留本地学籍与离线缓存，减少重登成本。
- 通知走原生 MethodChannel（AlarmManager/Notification），**不引入第三方插件**（本项目 compileSdk/NDK 固定）。
- Flutter 动画控制器注意 "multiple tickers"：`State` 用 `TickerProviderStateMixin`，需要多个动画才用 `TickerProviderStateMixin`（用 `SingleTickerProvider` 建多个控制器会黄屏）。
- 文本溢出避免依赖 `Transform.scale` 合成；用单个 `RichText` + WidgetSpan 嵌入图标，从排版层面杜绝溢出。

### 3.6 风控 / 合规（严肃对待）
- 抢课类高频自动化提交最易被判异常（每计划并发、每 3 秒一轮提交）。本项目用**云端白名单门禁**收敛暴露面，但无法消除"抢课即抢并发"的固有风险。
- 对外请求总体原则：有界、串行、限速、失败重试退避；用户无感的后台请求尽量低频。

### 3.7 设备绑定与恢复路径（2026-11）
- 清空应用数据会销毁 Keystore 私钥，服务端旧公钥与新公钥不一致。
- 结论：密钥绑定必须预留恢复路径。现行做法：名单内学号公钥不一致时自动覆盖绑定，并作废该学号旧会话（单设备生效）；管理页仍可手动重置。客户端已把 4xx 翻译成“学号验证失败”，不再混同网络问题。

### 3.8 后端部署的两个坑（2026-11）
- `build: .` 的镜像，`docker restart` 不会更新 `server.js`，必须 `docker compose up -d --build`。
- 实际 compose 目录以 `docker inspect` 的 `com.docker.compose.project.working_dir` 为准；同级旧副本目录会让人误以为“重建了却没生效”。

### 3.9 小部件排版（2026-11）
- 字号只按宽度（列数）分档，高度只决定行数；否则同为 4 列的 4×2 与 4×3 字号会不一致。
- 行数按高度估算并留余量，超出显示「还有 N 门」；空余高度优先补「明天第一门课」「下一场考试」，不要留白。
- 默认尺寸用 `targetCellWidth/Height` + `minWidth/minHeight` 声明；新增组件后桌面需刷新一次才会出现在面板。

### 3.10 高延迟隧道（2026-11）
- 免费/公网隧道往返常超 1000ms：连接池复用、预热、刷新闸门比“每次重建”更有效；永久错误应快速失败，避免重试风暴。
- 关闭时序必须 flush → Close 帧 → `end()`，否则会丢教务 302 的末尾数据。

## 4. 开发流程（本项目跑通的一套）

1. **抓包实证**：Web 端登录 → DevTools/CDP 抓接口 → 记录参数、响应结构 → 落盘 `api-captures/`。
2. **建模型/API**：在 `lib/api` 封装 Dio 请求，`lib/models` 定义模型；解析先覆盖真实字段再兜底。
3. **State 层**：`providers/` 用 Riverpod Provider/Notifier 串联；读接口统一走 `data_providers` 的"在线优先 + 离线缓存"。
4. **UI 层**：`ui/<模块>/页面`，注意统一用 `AppNotification` 做顶部灵动岛提示、`FadeUpwardsPageTransitionsBuilder` 过渡。
5. **构建验证**：每次改动 `flutter analyze` → `flutter test` → `flutter build apk --release --target-platform android-arm64 --build-number=<递增>` → 装真机验证；同批改动记入 `docs/modification_log.md`。
6. **后端部署**：先备份远端 `server.js` → 上传 → `docker compose up -d --build` → 容器内 grep 校验 → 探测关键接口。
7. **发布**：把 `jw_app/RELEASE_NOTES.md` 内容贴到 GitHub Release，附 APK。

## 5. 环境 / 约定备忘

- 构建受外网限制，`pub.dev`/Gradle 用腾讯/阿里云镜像；`path_provider_android` 锁 2.2.17。
- 签名：正式版 `jw_app/android/upload-keystore.jks`（RSA2048，CN=XIUHONG）；alias/口令见 gitignore 的 `android/key.properties`（勿外泄，自行备份）以保证后续更新签名一致。
- 更新下载走 GitHub Release APK，镜像加速 + 直连回退；校验名称 `海畔_update_v<版本>.apk`。
- 日志系统按模块/页面打标签（tag），支持按关键词过滤 + 按保留天数自动清理；级别分 查看级/调试级。
- 后端部署：NAS `/vol1/1000/docker/haipan-api`（容器 `haipan-api`，宿主 18080 → 容器 8080，数据卷 `./data`）；管理员由 compose 的 `ADMIN` 环境变量指定。
- 临时凭据放 `.secrets/`（已 gitignore，结项删除），禁止写入文档/提交记录。
- 真机 arm64 包不能装进 x86 模拟器；模拟器验证需 `--target-platform android-x64`。

## 6. 遗留 / 后续可做

- 学业服务端权威统计（修读进度/已通过）部分依赖页面文本解析，可进一步接入接口返回的权威字段，减少兜底口径。
- 抢课的自动循环若用于正式场景，需评估节奏与风控权衡。
- 通知权限在严格管控的设备上已降级为普通通知，仍需在真机机型上回归。
- 设备认证失败文案已分层：服务端 4xx 显示“学号验证失败”，超时/断网才显示“通道连接失败”。
- 名单内学号换设备默认自动重绑（旧会话失效，单设备生效）；管理员可在 APP「用户统计」页关闭该开关，关闭后换绑需 `resetDevice`，管理端重置始终保留。