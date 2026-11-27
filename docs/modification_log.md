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

## 2026-11-27 · Batch91：发布 1.0.2+10（情侣课表 Beta、本地占用、登录提示）

### 范围
- 客户端版本：`pubspec.yaml` → `1.0.2+10`；`build_info.dart` 兜底值同步。
- 登录提示精炼：顶部横幅、登录被拒、通道 403 三段文案统一为校园网 / 管理员引导；`usage_api.dart` 的服务端拒绝文案同步。
- 本地占用：扫描应用私有目录全部数据，圆环不足 1 MB 时按 KB 显示。
- 情侣课表：入口增加 Beta 标签，页内新增可关闭的稳定性提示（本机持久化）。
- README：根与客户端 README 重写为技术文档结构，移除具体学校名称等敏感表述；移交说明标题脱敏。
- 官网：下载卡片移除版本 / 平台 / 体积标签，改为左右分栏布局（≤700px 纵向居中）。
- 更新日志：`docs/release_notes_v1.0.2.md` 仅保留 APP 内容，移除官网章节与对比首段，改为正式说明语气。

### 决策
- 正式线由 `1.0.1` 调整为 `1.0.2`，构建号重置为 10，tag 使用 `v1.0.2+10`，不复用旧 tag。
- 情侣课表以 Beta 形式发布；稳定性提示关闭后写入本机 `couple.beta_closed`，不再重复打扰。

### 验证
- `flutter analyze` 无 issue；`check_version.ps1 -Tag v1.0.2+10` 通过。
- APK：versionName `1.0.2`、versionCode `10`，24,131,557 字节，SHA-256 `7D62056D2C28E322056CDBB478CC3562E5FD1912D0D3D93406AD057D7EA940E8`。
- 官网桌面 1617px 实测：下载卡片左右分栏，标签已移除。

### 部署
- 客户端提交 `0cd68dd`；Release `v1.0.2+10`（latest），资产 `haipan-app-release.apk`。
- 官网 GitHub `45442ba`（Netlify 自动部署）；Gitee `45442ba`（强制同步镜像）。

## 2026-11-27 · Batch90：情侣课表首版（4147，模拟器验证）

### 范围
- 后端 `backend/server.js`：新增 `/pair/code`、`/pair/bind`、`/pair/status`、`/pair/sync`、`/pair/partner`、`DELETE /pair`；配对码 10 分钟有效，同一学号连续输错 5 次暂停 10 分钟，180 天无同步自动解绑。
- 客户端：新增 `lib/models/couple_models.dart`、`lib/api/couple_api.dart`、`lib/ui/couple/couple_page.dart`；「我的」页新增「情侣课表」入口；`UsageTracker` 暴露带会话的 `apiRequest`。
- 官网：`site/notes.html` 删除指定的隶属关系表述。

### 决策
- 一对一绑定，任一方解除即整体失效；昵称仅保存在本机，默认「TA」，服务端不返回对方学号。
- 只同步课名、星期、节次、地点、周次；服务端再次清洗字段，教师、成绩、学号等一律丢弃。
- 合看视图按时间段合并，同一时间双方都有课时左右 50% 分栏；双方快照都在 7 天内才计算共同空闲。
- 首版不包含空教室推荐与双人桌面组件。

### 验证
- `node --check backend/server.js` 通过。
- 本地后端端到端测试全部通过：设备注册/挑战/验签、生成配对码、绑定、双方状态、快照同步、隐私字段剥离、解绑、连续 5 次错误码触发限流。
- 后端已上传 NAS 并用 `docker compose up -d --build` 重建，容器内 `grep -c 'pair/code'` 返回 1。
- `flutter analyze` 无 issue；x86_64 APK 4147 已安装到 `Pixel_7_API36`，入口与配对页排版正常；游客态提示先登录。
- 当前只有单个账号可用于真机/模拟器，完整双账号 UI 配对流程待有第二账号时回归。

### 部署
- 后端：`/vol1/1000/docker/haipan-api`，容器 `haipan-api` 已重建并运行。
- 官网注意事项表述更新：GitHub `5793674`、Gitee `65fdf0d`。
- 客户端 4147 仅安装到模拟器，未发布 Release。

## 2026-11-27 · Batch89：修复日志设置重复并发布 1.0.1+4146

### 范围
- 客户端：`log_page.dart` 移除运行日志页中重复的「输出详细日志 / 日志保留」卡片，两项设置仅保留在「调试」页；删除两项的灰色说明小字并恢复分隔线。
- 官网：`docs.html`、`notes.html` 同步日志设置与调试入口说明；移除页面中具体学校名称，统一使用「学校」。
- 版本：`pubspec.yaml` → `1.0.1+4146`。

### 验证
- `flutter analyze` 无 issue；`check_version.ps1 -Tag v1.0.1+4146` 通过。
- APK：versionName `1.0.1`、versionCode `4146`，24,065,925 字节，SHA-256 `67c3f62af1ab74886925d373c2d8271b94edd15c880fbef3e4c1c76e7e66726b`。
- 已通过 ADB 安装到 `192.168.6.206:38609`（4145 → 4146）并启动。

### 部署
- `QingYu327/HaiPan`：`0666d32`（main）。
- Release `v1.0.1+4146`（latest），资产 `haipan-app-release.apk`。
- 官网 `QingYu327/haipan-website`：`f3f7321`（main，Netlify 自动部署）；Gitee：`056c333`（master）。

## 2026-11-27 · Batch88：官网文档/须知导航与文案重写

### 范围
- 官网：`site/docs.html`、`site/notes.html` 顶栏改为与首页一致的四项文字导航（功能、网络、使用文档、注意事项）；≤980px 时统一收进汉堡菜单，菜单内保留功能、网络、使用文档、注意事项、下载五个入口。
- 样式与脚本：`site/assets/pages.css`、`pages.js` 调整菜单断点为 980px，补充行内代码样式；CSS/JS 引用加 `v=4145` 参数，避免旧样式被缓存。
- 文案：两页 8 个章节按正式使用文档/使用须知的语气重写，补充功能实际行为、限制条件与违规处理措施；移除全部硬编码版本号与构建号。

### 决策
- 移动端不再显示会被挤压的文字导航，统一由汉堡按钮收纳，避免 390–980px 区间排版拥挤。
- 文案以「说明行为与边界」为主，减少口号式表达；账号、隐私、通道与使用边界章节明确管理措施（撤销准入、重置绑定、限流或停止通道）。

### 验证
- 390 / 760 / 900px：文字导航隐藏、菜单按钮显示，展开后 5 个入口完整，`body.menu-open` 生效；1024 / 1440px：显示四项文字导航，菜单隐藏。
- 三页 `scrollWidth == clientWidth`，无横向溢出；本地链接、锚点与重复 ID 校验通过。
- 本次仅改官网，未重新构建 APK，版本仍为 `1.0.1+4145`。

### 部署
- `QingYu327/HaiPan`：`ea54f0b`（main）。
- 官网 `QingYu327/haipan-website`：`9e25711`（main，Netlify 自动部署）；Gitee：`ec54744`（master）。

## 2026-11-27 · Batch87：构建并发布 1.0.1+4145

### 范围
- 版本：`jw_app/pubspec.yaml` → `1.0.1+4145`；文档基线同步。
- 构建：Android arm64 Release APK；Release 资产名 `haipan-app-release.apk`。
- 内容：Batch86 的灵动岛反馈、日志设置、关于页文案与官网导航调整。

### 决策
- 构建号从 4144 递增到 4145，Release tag 使用 `v1.0.1+4145`，不使用同 tag 覆盖旧包。
- 发版前用 `tool/check_version.ps1 -Tag v1.0.1+4145` 校验 pubspec 与 tag 一致。

### 验证
- `flutter analyze` 无 issue、`flutter test` 通过。
- `check_version.ps1` 对 `v1.0.1+4145` 通过。
- APK：`cn.gdou.xiuhong` / versionName `1.0.1` / versionCode `4145`，24,065,921 字节，SHA-256 `6614e6c48b7e0c383323908497c8ccebfeaefb4093eda693a306a4d94d4892e9`。
- Release 标记 latest。

### 部署
- `QingYu327/HaiPan`：`0d1ec6f`（main）。
- Release `v1.0.1+4145`（latest），资产 `haipan-app-release.apk`。
- 官网 `QingYu327/haipan-website`：`4dc75a9`（main，Netlify 自动部署）；Gitee `heaven-does-not-move/haipan-website`：`814e613`（master）。

## 2026-11-27 · Batch86：补齐灵动岛反馈、日志设置入口与官网导航/版本清理

### 范围
- 客户端：`about_page.dart`（介绍文案）、`common.dart`（刷新成功文案可定制、切换学期反馈）、`log_page.dart`（日志设置卡与反馈）、`debug_page.dart`（复用日志设置组件）、`app_log.dart`（容量与设置留痕）、`settings_page.dart`、`favorite_rooms_page.dart`、`rank_page.dart`、`ge_credit_page.dart`、`update_page.dart`、`tunnel_page.dart`、`storage_page.dart`、`grade_page.dart`、`exam_page.dart`、`academic_page.dart`、`timetable_page.dart`、`usage_page.dart`。
- 官网：`site/docs.html`、`site/notes.html` 改为与首页一致的汉堡菜单；`site/assets/pages.css`、`pages.js` 增加窄屏菜单；三页移除硬编码版本号/构建号。

### 决策
- 关于页介绍改为「在线查询学业情况、空教室和排名，支持离线缓存课表与课程提醒」。
- 刷新/查询类操作统一给出具体反馈：成绩、考试、学业、课表、通识学分、统计、排名、空教室查询、收藏/取消收藏、通道测速、检查更新、日志清空/导出等均有对应灵动岛文案；`InkRefresh` 新增 `successMessage` 便于各页定制。
- 日志设置（输出详细日志、保留天数）从调试页抽为 `LogDetailRow` / `LogRetentionRow`，日志页与调试页共用；关闭详细日志时日志页不再展示 D 级条目，保留天数变化会立即清理并记录清理条数，确保开关有实际效果。
- 日志内存上限 800 → 2000；日志开关与保留天数的变更本身写入日志。
- 官网窄屏（≤860px）隐藏文字导航，统一收进汉堡菜单；桌面仍保留完整导航。移除页面中的固定版本号与构建号，版本以应用内「关于」和 Release 为准。

### 验证
- `flutter analyze` 无 issue。
- 官网 390 / 760 / 900 三档实测：窄屏 `.links` 隐藏、菜单按钮显示、展开后 3 个入口可见且 `body.menu-open` 生效；900px 恢复桌面导航；`scrollWidth == clientWidth`，无横向溢出。
- 本批改动随 Batch87 的 `1.0.1+4145` 构建发布。

### 遗留
- 官网版本号已改为「最新版 / 以应用内显示为准」，后续发版无需再改静态页。

## 2026-11-26 · Batch85：更新通道版本源改为安装包 + 官网三页与文档刷新

### 范围
- 客户端：新增 `lib/util/build_info.dart`；重写 `lib/api/update_api.dart` 的结果模型；调整 `main.dart`、`home_shell.dart`、`update_page.dart`；新增 `tool/check_version.ps1`。
- 官网：`site/index.html` 补移动端菜单（含使用文档 / 注意事项入口）；新增 `docs.html`、`notes.html` 与 `assets/pages.css`、`pages.js`、`app-icon.png`。
- 文档：根 `README.md`、`jw_app/README.md`、`jw_app/INDEX.md`、`docs/PROJECT.md`、`PROJECT_SUMMARY.md`、`ARCHITECTURE.md`、`INDEX.md`、`LESSONS_LEARNED.md` 同步现状。

### 决策
- 运行版本不再手写：`BuildInfo` 通过原生 `cn.gdou.xiuhong/app` 读取安装包 `versionName` / `versionCode`，从根上消除源码常量与 `--build-number` / Release tag 的漂移。
- 更新检查返回 `UpdateCheckResult`：`hasUpdate` 与 `isCurrent` 分离；首页只在 `hasUpdate && downloadUrl.isNotEmpty` 时弹窗，更新页用 `isCurrent` 展示发布说明。
- 发布前用 `tool/check_version.ps1 -Tag v<版本>+<构建号>` 校验 pubspec 与 tag；Release 资产名固定 `haipan-app-release.apk`。
- 官网 ≤860px 把桌面导航收进菜单按钮，菜单内保留功能、网络、使用文档、注意事项、下载五个入口；新增页品牌位改用 APP 图标，不再用文字占位。
- 官网顶栏对齐 DeepSeek：桌面导航高度 64px、链接 14.5px、品牌 18px，文档/注意事项与工具组整体靠右；移动端导航 56px，入口收进菜单。

### 验证
- `flutter analyze` 无 issue；`check_version.ps1` 对 `1.0.1+4144` 通过。
- 官网在 390 / 768 / 1024 / 1440 四档宽度实测：`scrollWidth == clientWidth`、无横向溢出、无破图、无重复 ID、单页单 H1；移动菜单展开后 5 个入口可见；三页控制台无报错。
- 本批未构建 APK（按「攒批」处理），版本仍为 `1.0.1+4144`。

### 部署
- GitHub `QingYu327/haipan-website`：`8ced5ea`（三页与动效）、`4e0ad4d`（APP 图标）。
- Gitee `haipan-website`：`f095445`、`e1e62f7`。
- `QingYu327/HaiPan`：`fe49929`、`9c9bdcb`（`site/` 同步）。

### 遗留
- Netlify 生产地址未记录在仓库中，构建完成后需用实际域名复核线上版本。

## 2026-11-26 · Batch84：修复「已是最新仍提示更新」（build 4144）

### 问题
4143 装机后启动仍弹「发现新版本 v1.0.1+4143」。日志：
`17:39:53 启动检测到新版本 v1.0.1+4143`。

### 根因
`checkLatest` 的主版本循环用了完整版本号的数字段，`1.0.1+4143` 会解析成
`[1,0,1,4143]` 与 `1.0.1` 的 `[1,0,1]` 比较，第 4 段 `4143 > 0` 直接判定为更新，
后面的「构建号比较」分支根本不会执行。

### 修复
- 主版本比较只取 `+` 之前的段：`_numbers(version.split('+').first)`，再单独比构建号。
- 版本判定用临时 Dart 脚本验证：
  `1.0.1+4144`/4144 → 最新；`1.0.1+4144`/4143 → 更新；`1.0.1+4143`/4144 → 最新；
  `1.0.1+4145`/4144 → 更新；`1.0.2+1`/4144 → 更新。

### 发布
- 新 Release `v1.0.1+4144`（两仓库，latest），APK 24,065,925 字节，
  SHA-256 `29026658…28a8`；旧 tag 保留。
- 官网与 Gitee `haipan-website` 的版本标签同步为 `1.0.1+4144`。
- 无线 adb 掉线，4144 尚未装机验证。

## 2026-11-26 · Batch83：版本标识改为「版本号+构建号」，Release 换标（build 4143）

### 版本比对（`update_api.dart`）
- 新增 `appBuild = 4143`、`appVersionLabel`；Release tag 形如 `v1.0.1+4143`。
- `checkLatest` 先比主版本数字段，主版本相同再比 `+构建号`；只有构建号也相同才视为
  「已是最新」。避免 tag 带构建号后，同版本每次启动都被提示升级。
- 新增 `isCurrentRelease()`；更新页据此展示「当前已是最新」并显示完整版本号。

### 发布
- 新建 Release **`v1.0.1+4143`**（两个仓库），APK 24,065,925 字节，
  SHA-256 `c7c202a0…594d`，标记为 latest；旧的 `v1.0.1` 保留以兼容历史链接。
- 更新日志合并为一份（相对 1.0.0 的变化 + 致谢 + 修复清单，致谢代称「X」）。
- 官网下载卡版本标签同步为 `1.0.1+4143`。

## 2026-11-26 · Batch82：准入纠偏探针 + Release 致谢（build 4142）

### 修复
- `appAccessProvider`：判定为公网但名单未通过（缓存拒绝 / gates 返回 false / 在线校验失败）时，
  先 `probeCampusNow()` 现场复核校内直连；可达即放行。避免「弱 Wi-Fi 被误判校外」
  导致校园网用户被名单拦下。仅拒绝路径多一次 1.8s TCP 探测。

### 发布
- `1.0.1+4142` 装机；两仓库资产替换（SHA-256 `5039d264…43d3`）。
- Release 说明新增「致谢」段，感谢 2024****1227 同学反馈误判问题。

## 2026-11-26 · Batch81：校园网误报白名单修复 + 导航 GitHub 图标（build 4141）

### 问题定位（学号 202411621227 反馈：校园网直连仍弹「未开通公网通道」）
核查 NAS 数据与容器日志：
- `haipan.json`：该学号在登录名单、在 `allow_app` 白名单、设备已登记；
- 容器日志：16:45:34 `mux open 20********27` → 16:45:45 `mux close (streams=2, rejected=0)`，
  即 App 当时**建了隧道**（说明被判定为校外），且没有任何隧道级拒绝或 guard 拦截记录。
结论：服务端没有该学号的名单拒绝记录，误报来自客户端口径与判定。

### 修复
1. `appAccessProvider` 原本对所有人强制校验名单，校园网用户一旦 `gates` 请求失败
   （超时/入口不可达）就按拒绝处理 → 无权限页。现改为：`CampusTunnel.isPublicNetwork`
   为 false（校园直连）时直接放行，不做名单校验。
2. `CampusTunnel.adapt()` 显式记录本次判定（`_public`），校园直连/wfw/无学号置 false，
   建隧道置 true；新增 `probeCampusNow()` 现场复核（绕过 10 分钟缓存）。
3. `UsageTracker._authenticateAt` 与 `checkAllowed` 只认服务端 JSON 里的
   `error=not_allowed / device_mismatch`；网关、限流、代理返回的裸 403 不再被误报成
   「未开通公网通道」，改按网络错误处理。
4. 登录页遇 `not_allowed` 时先 `probeCampusNow()`，确实在校内则放行并记日志。

### 官网
- 右上角补回 GitHub 仓库图标（与明暗切换并排），链接同 `REPO` 常量。

### 发布
- `1.0.1+4141` 已构建并替换两个仓库资产（SHA-256 `56c84b87…0373`）；
  无线 adb 端口失效，未装机。

## 2026-11-26 · Batch80：关于页简介定稿 + 官网免责声明（build 4140）

### 关于页（`about_page.dart`）
- 简介改为：「一款支持课表、成绩、考试与空教室查询等功能，同时离线缓存课表与课程提醒的课表 APP。」

### 官网（`site/index.html`）
- 下载卡下方新增「免责声明」卡片：非官方工具、数据仅本地缓存不上传、成绩仅供参考、
  使用后果自负；带盾牌勾选图标，随明暗主题变化。
- 页脚署名改为 `Powered By XIUHONG & KJCXXH`。

### 发布
- `1.0.1+4140` 构建并装机；两个仓库 v1.0.1 资产替换为
  SHA-256 `d0f63484…2186e`，Release 说明同步。

## 2026-11-26 · Batch79：关于页措辞收敛 + 官网重做（DeepSeek 式胶囊导航 / 明暗模式）（build 4139）

### 关于页（`about_page.dart`）
- 简介改为中性表述，不涉及学校相关字眼：
  「面向学生的第三方教务工具。集中查看课表、成绩、考试与空教室，界面简洁，支持离线缓存与课程提醒。」
- 技术栈新增行「校外通道」去掉副标题小字。

### 官网（`site/index.html`）
- 抓取 deepseek.com 实测值后重做导航：固定外层 54px，内层胶囊高 48、圆角 100px，
  顶部全透明；滚动 >10px 收缩为更窄的胶囊（1140 → 860），加半透明底 + `blur(12px)` +
  细描边 + 淡阴影，过渡 `max-width .5s` / 背景与模糊 `.3s`。
- 菜单文字统一为无衬线（PingFang/YaHei）15px，去掉宋体；右上角只保留明暗切换按钮，
  删除「功能 / 网络」与下载按钮。
- 新增明暗主题：跟随系统偏好，手动切换写入 `localStorage('hp-theme')`；深色取 App
  暗色令牌（#0F171D / #152026 / #EDF3F6 / #8FB9D6）。
- 背景改为三团缓慢漂移的雾光（`drift` 26/33/39s，reduced-motion 下关闭）。
- 依据真机截图（课表 / 成绩 / 考试）重绘手机模型：课表带周次与彩色课程块，成绩带
  学分绩点与分数分布柱状，考试带倒计时徽标与地点条。
- 下载区：主按钮标注「Android 安装包」，旁附禁用的「iOS 版本 · 敬请期待」；删除
  「Android 8.0+ · 约 23 MB」那行说明字。
- 页脚：「Powered By XIUHONG Ⅰ 科技创新协会」。

### 发布
- `1.0.1+4139` 构建并装机；两个仓库 v1.0.1 资产替换，Release 说明同步新 SHA-256。

## 2026-11-26 · Batch78：启动自动检查更新 + 关于页信息重写（build 4138）

### 启动检查更新（`home_shell.dart`）
- `HomeShell.initState` 首帧后延迟 2s 调 `UpdateApi.checkLatest()`；首屏导入弹窗未结束
  时最多再等 10s，避免与导入进度抢同一层弹窗。
- 命中更新黑名单（`gateUpdateBlock`）时直接跳过；有新版且能拿到 APK 直链时用
  `showInkDialog` 弹「发现新版本 vX」，确认后 `InkPageRoute` 进入 `UpdatePage`。
- 用 `_updateChecked` 保证一个进程内只询问一次。

### 登录提示（`login_page.dart`）
- 横幅文案去掉句末句号：`建议使用校园网登录。公网通道需联系管理员开通，且速度较慢`

### 关于页（`about_page.dart`）
- 首卡去掉「应用版本 / 构建版本」两行（应用信息栏已有），换成一段 App 简介。
- 技术栈补充「桌面小组件（AppWidget · AlarmManager）」与「校外通道（WebSocket · Node.js）」。
- 开源许可按实际依赖校准：`dio_cookie_manager` 合入网络行，删掉实际未依赖的
  Cupertino Icons，uuid 说明改为「登录验证码随机数」。

### 发布
- `1.0.1+4138` 已构建、装机；两个仓库 v1.0.1 资产替换为新包，
  Release 说明按要求重写为「相对 1.0.0 的变化」，不再逐构建对比。
- 官网下载信息同步：架构改为 arm64（实际只出 arm64 包）。

## 2026-11-26 · Batch77：准入口径文案对齐 + 登录页校园网建议横幅（build 4137）

### 准入口径（确认，不改逻辑）
- 代码里 `checkAllowed` 只在 `CampusTunnel.adapt` 返回「已启用通道」（校外）后调用，
  校园网直连登录完全不校验名单。因此名单**只对公网登录生效**。

### 文案（`usage_page.dart`、`access_denied_page.dart`、`usage_api.dart`）
- 用户统计「APP 准入名单」提示改为：只校验公网（校外）登录，名单内可用公网通道，
  校园网登录不受限。
- 取消权限弹窗：`取消 APP 权限` → `取消公网权限`，说明改为「只能在校内网使用」。
- 拒绝页与拒绝提示统一为「未开通公网通道，请使用校园网登录或联系管理员」。

### 登录页横幅（`login_page.dart`）
- 页面最上方（字标之上）新增可关闭的提示条（InkCard + info 色调）：
  「建议使用校园网登录。公网通道需联系管理员开通，且速度较慢。」
- 关闭状态只作用于当前登录页实例，不写盘，不打断登录操作。

### 验证
- `dart analyze lib`：No issues found；release arm64 构建见下。

## 2026-11-26 · Batch76：定位确认「每跳 4–5s」= 容器 DNS，并补 App 侧计时探针（build 4136）

### 结论（推翻中间误判）
- 真机 5G 实测隧道端到端：`隧道心跳 RTT 46ms / 90ms`，每条子流
  `建流→首包 52–94ms`，`通道+认证页就绪 831ms`（Batch73 前是 4811ms）。
- 服务端容器内冷连接探针（8 次新建 TCP+TLS）：DNS 2ms、TCP 4–5ms、
  首字节 28–30ms；出口 `/health`：东莞 5G 202ms、深圳 141ms、
  国内直连 322ms、Cloudflare 900–2000ms；同一条连接连发 8 次 39–99ms/次。
- 因此 4–5s/跳确实来自 **每条新连接一次 Docker 默认 DNS 转发（2s×2 重试）**，
  Batch75 的修复有效。此前「容器内 DNS 只有 8ms，所以 DNS 不是瓶颈」的测量
  是在修复之后做的，结论作废。

### 改动（`jw_app`）
- `campus_tunnel.dart`：mux 连上立刻发一次心跳，日志输出 `隧道心跳 RTT`；
  每条子流记录 `建流→首包` 耗时；`复用建立` 带建流耗时。
- `jw_client.dart`：`POST/GET … → 状态（xxms）` 带请求总耗时。
- 探针均为 D 级日志，成本可忽略，后续定位链路问题直接用。

### 验证
- `dart analyze lib`：No issues found；release arm64 构建通过，真机已装 4136。
- 全新 5G 登录日志（01:18:44）：机器耗时约 6s（就绪 0.8s + 换票 2s + 数据 3s），
  其余为人工操作：点「发送验证码」→ 5s、输入短信验证码 → 8s，非代码问题。

## 2026-11-26 · Batch75：隧道服务端 DNS 缓存（极大缩短每跳延迟）

### 依据
- 本机直连教务：`jw` 首字节 74ms、`authserver` 45ms（DNS 17–42ms）。
- 经隧道：每条请求固定 4.8s。两者差两个数量级，不是线路 RTT，而是**每条新连接
  都做了一次慢解析**（Docker 默认 DNS 转发常见 2s×2 重试 ≈ 4s），
  Node 的 `net.connect({host})` 每次连接都会触发 getaddrinfo。

### 改动（`backend/server.js`、`backend/docker-compose.yml`）
- 进程级 `dns.lookup` 缓存（TTL 10 分钟，命中走 nextTick，不阻塞事件循环）；
  `all`/IPv6 语义的调用原样透传，避免改变行为。
- compose 给容器显式指定 `dns: 223.5.5.5 / 119.29.29.29`，双保险。

### 部署
- 需在 NAS 上重建容器：`docker compose up -d --build`。
- 若 NAS 所在网络不允许公共 DNS，可删掉 compose 里的 `dns:` 两行，仅靠进程缓存。

### 验证
- `node --check backend/server.js` 通过。
- 已在 NAS 重建容器（`docker compose up -d --build`），`/health` 正常。
- 真机复测见 Batch76：每跳 4–5s → 首包 52–94ms，判断成立。

## 2026-11-26 · Batch74：认证跳转自动升 https，少一跳明文（build 4135）

### 现象
日志里认证 302 的 Location 是 `http://authserver.gdou.edu.cn/...`，客户端照跟，
多出 `authserver.gdou.edu.cn:80 #4` 一条连接（约 4–5s），且认证 Cookie 会走明文。

### 改动
- `_followRedirects` 跟随前统一 `_upgradeHttp`：`*.gdou.edu.cn` 的 `http://` 一律升级为
  `https://`，并去掉 80 端口。

### 验证
- `dart analyze lib` 无问题；release arm64 构建成功，真机已装 4135；桌面留档
  `海畔_1.0.1_4135.apk`。
- Batch73 复测：通道+认证页就绪 **21205ms → 4811ms**，首屏并发 **5 条 → 2 条**。

## 2026-11-26 · Batch73：登录请求并发合流，消除重复拉取（build 4134）

### 诊断结论（4133 加了 stream 存活日志）
- 日志显示每条隧道流都活到约 24–27s 才由上游正常关闭，**不是隧道主动断**；
  连接没被复用的真正原因是**同一时刻并发打了 5 条连接**（00:25:42 #4–#8），
  把高延迟隧道堵住，认证页就绪从 5s 拖到 21s、密码校验 30s。
- 次要原因：`_preload` 在隧道未就绪时就去拉认证页，失败后重试；`warmUp` 在登录
  期间还在抢带宽（日志里预热 20s 超时）。

### 改动
- `CasAuthApi.prepare()` 增加在飞合并（`_prepareFuture`）：预检与提交同时触发只发一次请求。
- `checkNeedCaptcha` 先等在飞的 prepare，避免并发再开一条连接。
- `_preload` 与 `_submit` 都改为**先网络、后认证页**：隧道没就绪时并发拉取必然失败重试。
- `CampusTunnel.adapt(..., warm: false)`：登录页不再触发预热；启动路径仍预热。

### 验证
- `dart analyze lib` 无问题；release arm64 构建成功，真机 `d4b532b4` 已装 4134；
  桌面留档 `海畔_1.0.1_4134.apk`。
- 待复测：`认证页就绪` 应由 21s 降到 5s 左右，并发连接数由 5 条降到 1–2 条。

## 2026-11-25 · Batch72：公网登录提速——连接池/换票/端口残留（build 4132）

### 1. 连接复用（`jw_client.dart`、`cas_auth.dart`）
- 教务与认证两个 Dio 统一连接池参数：空闲 120s、单域并发 6（教务 8）、连接超时 10–15s。
- 认证侧原来空闲 60s，登录链路多次跳转容易断连重握手，已对齐到 120s。
- 说明：Dart `HttpClient` 本身默认 keep-alive，本次把参数对齐到上限；日志里「每跳 4–5s」说明上游仍在关连接，需看 NAS 隧道服务端代码（不在本仓库）。

### 2. 多因子后只换一次票（`cas_auth.dart`）
- 删除「按候选 service × 2 种 URL」的探测循环（最多 6 次请求），改为固定一次
  `GET /authserver/login?service=<jw sso>`（服务端下发 redirect 时优先用它），失败只原样重试 1 次。
- 日志证据：23:38:38 一次 `Connection closed` 就导致整条链路重走，单次重试 ~12s；改后重试只重复一次请求。

### 3. 端口残留（`jw_client.setProxyPort`、`cas_auth.setProxyPort`、`adapt`）
- 两个客户端都支持 `force` 重建连接池；隧道**新建**时强制换 adapter。
- 根因：隧道重启后端口号可能复用，旧的空闲 socket 指向已关闭监听口，复用时直接 `Connection refused`（日志 `port=33408` 那类）。旧逻辑「端口相同就跳过」正好踩中。

### 验证
- `flutter analyze` 无问题；`flutter test` 3 项通过。
- release arm64 构建成功，真机 `d4b532b4` 已装 4132；桌面留档 `海畔_1.0.1_4132.apk`。

## 2026-11-25 · Batch71：修复非白名单被误报为「网络错误」（build 4131）

### 根因
两处吞错叠加，把业务拒绝降级成了网络失败：
1. `_configureNetwork` 的兜底 `catch (e) => AuthException(_tunnelError(e))` 会把内部抛出的 `AuthException` 一起改写成「网络连接失败」（`_tunnelError` 只认 `DioException`，其它一律网络错误）。
2. `checkAllowed` 里 403 被 `catch` 静默跳过；`_connectMux` 把各入口的 `AccessDeniedException` 收进 `last` 后抛 `StateError('$last')`，异常类型丢失。

### 修复
- 新增 `AccessDeniedException(code, message)`（`not_allowed` / `device_mismatch`）。
- `_authenticateAt`：注册接口 403/409、以及「200 + error 字段」两种拒绝形态都转成 `AccessDeniedException`；`_authenticate` 遇到业务拒绝立刻上抛，不再逐个入口重试。
- `checkAllowed`：gates 明确 `app=false` 时抛业务异常；结构不认识时不拦。
- `_connectMux`：业务拒绝不再被 `last` 吞掉。
- `_configureNetwork`：`on AccessDeniedException` / `on AuthException` 先接住并原样上抛，只有真正的连接异常才落到「网络失败」。`_friendly` 同步识别该异常。

### 验证
- `flutter analyze` 无问题；release arm64 构建成功（23.0MB），真机 `d4b532b4` 已装 4131；桌面留档 `海畔_1.0.1_4131.apk`。
- 预期表现：非白名单学号提交后弹灵动岛「无权限登录 / 该学号未加入白名单」，不再出现网络错误。

## 2026-11-25 · Batch70：自建页准入校验轻量化 + 废弃 wfw 分支瘦身（build 4130）

### 自建页白名单校验（`lib/ui/login/login_page.dart`、`lib/api/usage_api.dart`）
- 自建页不再弹学号验证窗口：非白名单只弹灵动岛「无权限登录」。学号窗口只保留在认证网页里（没有其他拦截手段时使用）。
- 新增 `UsageTracker.checkAllowed(xh)`：只把学号交给设备会话接口换一个放行结果，不发账号密码、不建完整登录态，返回 bool。替换原来提交前的 `tokenFor` 全流程。
- 校验接口不可达时不拦登录（记录日志后继续），避免网络抖动误挡用户。

### 瘦身：删除已废弃的官方通道分支
- `login_page`：删除 `_wfwLogin`/`_wfwRetried`、`loginWithWfw` 分支、官方通道换票重试块、`client.wfwMode` 回退（约 60 行）。
- `cas_auth`：删除 `useWfw()`、`clearWfwCookies()`、`landedOnJw`、`_service`/`_loginUrl` 可变字段、`_wfwService/_wfwHost/_wfwBase` 常量与全部 wfw 分支；`prepare()` 少一次网关入口往返。
- 保留：`SsoLoginPage(wfw:)` 与 `JwClient.enableWfw()`（认证网页的官方通道能力，当前无入口、不启用）。该文件不在版本控制内，300+ 行改写没有回滚兜底，且处于登录主链路，暂不动。

### 回环测试
- `flutter analyze` 无问题；`flutter test` 3 项通过。
- release arm64 构建成功（22.9MB），真机 `d4b532b4` 覆盖安装 4130 并启动；冷启动进入登录页正常渲染，无崩溃。
- 桌面留档 `海畔_1.0.1_4130.apk`。
- 完整登录回环（密码 + 企业微信验证码 + 拉课表）需人工过验证码，未自动执行。

## 2026-11-25 · Batch69：登录提示全部接入灵动岛 + 非白名单弹学号窗（build 4129）

### 登录页（`lib/ui/login/login_page.dart`）
- 删除页面内的小字错误位（原 `_error` 文本条）；`_error` 改为只写不读的 setter，赋值即通过 `showInkNotice` 弹灵动岛。调用点零改动，覆盖：空学号/空密码/空验证码、验证码要求、登录失败、发码失败、多因子校验失败等全部提示。
- 多因子切换时补一条灵动岛提示（原先是表单里的小字说明），并移除该小字。
- **非白名单（403 not_allowed）**：不再只显示一行字。识别到「白名单 / 无权限 / not_allowed」后，弹灵动岛「无权限登录」，并直接弹出学号验证窗口（`askStudentId`）让用户换号重试。

### 学号验证窗口（`lib/ui/login/sso_login_page.dart`）
- 弹窗保留（`_XhDialog`），并暴露公共入口 `askStudentId(context)`，原生登录页与认证网页共用同一套交互。

### 统一接入检查
- 全仓已无 `SnackBar` / `ScaffoldMessenger`；`ui/` 下除弹窗正文外，不再有 `Text('请…')` 形式的行内提示。
- 登录卡片副标题「使用学号与密码直接登录教务」属于区块说明而非流程提示，保留。

### 验证
- `flutter analyze` 无问题；`flutter test` 3 项通过。
- release arm64 构建成功（23.0MB），已装到真机 `d4b532b4`（versionCode 4129）并启动；桌面留档 `海畔_1.0.1_4129.apk`。

## 2026-11-25 · Batch68：通道/拉取提速 + 登录入场收敛 + 开发残留清理（build 4128）

### 通道检测与拉取（`lib/util/campus_tunnel.dart`、`lib/api/jw_client.dart`）
- 直连探测 4s → **1.8s**：校内到教务是同网段握手（正常 100ms 内），1.8s 足够覆盖弱 Wi-Fi；校外则更快失败切隧道，冷启动最多少等 2.2s。
- 新增统一 `_adapter(proxyPort)`：直连与隧道共用同一套连接池参数——空闲连接 120s、单域并发 6、连接超时 10s。原来**直连模式用的是裸 `IOHttpClientAdapter()`**，空闲 15s 就断，翻页要重新握手，这是校园网下拉取偏慢的一个隐性原因。
- 隧道并发 4 → 6，方案抓取与当前页面并行时不再互相排队。

### 登录（`lib/ui/login/login_page.dart`）
- 入场动画 280ms → **200ms**：登录页是用户最急着操作的界面，先给可点击的稳定画面。
- 页面跳转维持现状（冷启动 → 登录页一屏；认证网页仅在需要时 push 一层），未增加任何中转页。

### 清理
- 删除 `api-captures/`（30 个 2026-11-22 抓包样本：JSON/HTML/PDF）与 `tools/`（抢课脚本及输出）。二者均为开发期探针，不参与构建。
- 临时登录探针脚本（`jw_app/tool/wfw_probe.dart`，含明文测试账号）已在上一步删除，`lib` 内无硬编码账号/密码。
- `jw_app/test/` 保留（仅设计令牌单测，不打包进 APK）。

### 验证
- `flutter analyze` 无问题；`flutter test` 3 项通过。
- `flutter build apk --release --target-platform android-arm64` 成功，22.9MB；已复制到桌面 `海畔_1.0.1_4128.apk`。

## 2026-11-25 · Batch67：官方 wfw 两段式登录实测结论（不启用，维持 NAS 通道）

### 范围
- 仅调研与文档，**不改业务代码**；临时验证脚本（`tool/wfw_probe.dart`，含明文测试账号）验证完已删除。
- 文档：`docs/PROJECT.md` 8.1 重写为实测结论。

### 实测过程（命令行 Dart + 真实账号 + 3 次企业微信验证码）
- 第一段：`GET authserver/login?service=https%3A%2F%2Fwfw.gdou.edu.cn%2F` → 取盐 → POST 密码 → `302 reAuthLoginView.do`（该账号每次登录强制多因子）→ 发码 → `reAuthSubmit.do` 返回 `reAuth_success`。
- 第二段：`GET wfw/authserver/login?service=https%3A%2F%2Fjw.gdou.edu.cn%2Fsso%2Fjziotlogin` → 第二套盐 → POST 密码 → 再次多因子 → `reAuth_success`。

### 关键决策与原因
- **认证接口必须用归一化地址** `https://wfw.gdou.edu.cn/authserver/...`：wfw 下发的 `JSESSIONID`/`route` 是 `Path=/authserver`，带 `/https://authserver.gdou.edu.cn` 前缀的请求带不上 Cookie，会导致每个请求都重置会话（第三方仓库 `normalizeWfwAuthUrl` 同因）。修正后会话确实保持，但票据仍未签发。
- **结论：官方通道不启用**。两次 `reAuth_success` 之后 `authserver/login?service=...` 仍回多因子页（直连与 wfw 代理一致）；`wfw/https://jw.gdou.edu.cn` 的 302 指向裸 `jw.gdou.edu.cn`，校外不可达，套回前缀则无限 302。
- 成本对比：官方通道需 2 次密码 + 2 次人工验证码且仍失败；自建 NAS 隧道 1 次密码 + 1 次验证码即可。**NAS 继续作为校外唯一通道**，wfw 代码保留但不启用。

### 验证
- 未改业务代码，无需 `flutter analyze` / `flutter test`；版本保持 `1.0.1+4127`。

### 补充：WebView 路径的机制已确认（模拟器实测）
- 在模拟器 debug 包中把「使用认证网页登录」临时指向 `SsoLoginPage(wfw: true)`，WebView 能正常渲染 wfw 的 CAS 登录页与多因子页（企业微信发码成功），说明**第一段在浏览器里完全可行**。
- 关键机制：wfw 代理出的第二段登录页表单 `action="/authserver/login"`（相对 wfw 根路径），浏览器提交时落在 `wfw.gdou.edu.cn/authserver/login`，`Path=/authserver` 的 `JSESSIONID` 才随请求带上——这正是手工 HTTP 拼前缀路径失败、浏览器可行的地方。
- 因此把 `sso_login_page.dart` 的 wfw 入口改为 CAS `service=https://wfw.gdou.edu.cn/`，第一段完成后自动导航到 `wfw/https://jw.gdou.edu.cn` 让页面自行完成第二段；`_isPostLoginJw` 对应的前缀判定同步放宽。
- 未完成端到端验证（第二段多因子后能否进教务门户）：adb 驱动 WebView 不稳定（输入法浮层、返回键会直接弹出路由、进程重启丢失会话），验证码多次过期。**该入口未在 UI 上启用**，`_openSso()` 仍走普通通道，行为无变化。

### 遗留
- 若学校后续调整 CAS 的二次认证策略（例如允许可信设备免二次认证），可重新用 `normalizeWfwAuthUrl` + 两段式再验证一次；在此之前不再投入。

## 2026-11-25 · Batch66：下载灵动岛动效 + 公网加载提速 + 通知后台可达 + 清理临时 Release（build 4127）

### 下载灵动岛（`lib/ui/widgets/ink_notice.dart`）
- 开始：药丸改为淡入 + 自上而下轻微位移 + 0.92→1 缩放（280ms），不再突然出现。
- 取消/结束：先播放 180ms 退场动画再移除；退场途中若又开始新下载，自动中止收起并重新出现。
- 完成/失败：弹一下（1→1.025→1，240ms），状态文案与颜色同步切换。
- 尺寸：状态切换（下载中→完成/取消）用 `TweenAnimationBuilder<Size>` 做 240ms 平滑过渡；展开/收起时改为逐帧跟随，避免双重缓动拖沓。
- 进度：进度条与百分比用 380ms 补间，取代原来 600ms 一格一跳；完成时补满、取消/失败保留最后进度，不再出现“失败也 100%”。

### 公网加载提速（`lib/util/campus_tunnel.dart`、`lib/api/jw_client.dart`）
- `adapt()` 先读网络类型：**仅移动数据时直接建通道**，跳过必然失败、每次要等满 4s 的直连探测；Wi-Fi 仍先试直连（校园网可零通道使用）。
- 直连探测合并并发调用（`_directProbe`），启动期多处同时 `adapt` 不再各等 4s。
- 隧道连接池：单域并发 3→4（教务方案抓取占 3 条时仍留 1 条给当前页面），空闲连接 90s→120s，减少重连握手。

### 课程通知后台不触发（`AndroidManifest.xml`、`NotificationHelper.kt`）
- 根因：Android 13+ 上 `SCHEDULE_EXACT_ALARM` 对新装应用默认不授予，`setAlarmClock()` 抛 `SecurityException` 后降级为非精确闹钟；国产 ROM 深度休眠时非精确闹钟可能一直推迟到 App 回到前台才弹出。
- 修复：声明 `USE_EXACT_ALARM`（Android 13+ 安装即授予），并在排程前先检查 `canScheduleExactAlarms()`；无权限时才降级，并写入 `HaipanNotify` 日志便于排查。
- 原有电池优化白名单、MIUI 自启动引导保留。

### 隧道与登录一致性
- 自建登录页与认证网页登录**共用同一条隧道**（同一本地 CONNECT 代理端口 + `/tunnel-mux` + 同一设备令牌 + 同一目标白名单），认证接口与教务接口完全相同。
- 差异只在入口：自建页用 `tunnel.adapt()`（Dio 代理 + 4s socket 探测）；认证网页用 `NetworkInfo` 判断蜂窝后直接建通道，Wi-Fi 下先直连、8s 无进展或加载错误再切隧道，并由 `WebViewProxy` 接管 WebView。认证网页失败时同样会回落到同一隧道。
- 学号验证弹窗只属于认证网页：本地没有已保存学号时才会弹出（`SsoLoginPage._askXh`）；自建页直接用输入框里的学号。
- 自建页补显式设备认证（`login_page.dart`）：`adapt()` 返回已用隧道后，先 `await UsageTracker.tokenFor(xh)`，白名单未放行/设备换绑会在提交账号前给出明确文案，不再等首次请求才报含糊的网络错误（与认证网页行为一致）。

### 清理临时 Release
- 删除 GitHub `QingYu327/HaiPan` 上仅用于验证应用内更新的临时 Release（v1.0.2，说明为“本版本仅用于验证应用内更新链路”），更新源恢复为无更高版本状态。
- 远端 `v1.0.2` 标签仍在（Release 对象已删除，客户端不可见）；如需彻底清理标签需再执行一次带权限的删除。

### 版本与验证
- `pubspec.yaml` → `1.0.1+4127`；`flutter analyze` 无问题；`flutter test` 3/3 通过；release arm64 构建见下。
- 真机未连接，通知与动效待真机复验。

## 2026-11-25 · Batch65：反馈模板简化/设备信息自动采集 + 空教室筛选按钮 + 全新状态登录实测（build 4125）

### 意见反馈（`feedback_page.dart`、`app_log.dart`、`MainActivity.kt`）
- 模板精简：邮件主题改为「【海畔反馈】问题简述」，正文模板只保留「问题描述：」，不再要求用户填写复现步骤、页面、机型系统等。
- 自动采集：新增原生通道 `deviceInfo`（厂商/品牌/机型/设备代号/Android 版本/SDK/ABI/分辨率/密度/版本号/构建号/语言/时区），`AppLog.exportForFeedback(extraInfo:)` 把信息写在日志文件头「设备与环境（自动采集）」段，导出时自动附带。
- 说明卡片同步改为「简单描述问题即可，机型系统会自动写入日志」。

### 空教室（`favorite_rooms_page.dart`）
- 「只看可借」FilterChip：默认透明底 + 发丝描边，点击选中后才填充原来的 `primaryContainer 0.6`，避免未选中时看起来已开启。

### 自建通道白名单结论（未改代码）
- 仍生效：服务端 `/device/register` 对非 `allow_app` 学号直接 403 `not_allowed`；`/gates` 返回 `app=allow_app(xh)`；管理员账号恒放行。
- 客户端 `appAccessProvider` 默认拒绝，命中缓存先放行并后台复核；因此移出白名单后「下次启动」生效，已签发的隧道令牌最长约 30 分钟（`SESSION_TTL`）才失效；后端在移出白名单时会同时删除该学号的设备公钥（`allow_app` 变更清理 devices）。

### 全新状态登录实测 + 权威接口核对（校园网/公网真机 d4b532b4，4125）
- 真机：学号 + 密码 → 多因子页；选择「短信」→ 灵动岛显示验证码 004552 → 「验证并登录」→ 成功进入课表（第 13 周，课程正常）。随后「我的 → 退出登录」回到登录页，账号状态已清。
- 浏览器侧（edge-cdp，真实页面抓取）：
  - 登录 POST：`/authserver/login?service=<encoded jw sso>`，字段 `username`、`password`（AES 密文，108 字符）、`captcha`、`_eventId=submit`、`cllt=userNameLogin`、`dllt=generalLogin`、`lt`（空）、`execution=e1s1`。
  - 验证码检查：`GET /authserver/checkNeedCaptcha.htl`，参数 `username`；验证码图 `/authserver/getCaptcha.htl?<ts>`。
  - 多因子：`reAuthType=4`（企业微信）；发码 `POST /authserver/dynamicCode/getDynamicCodeByReauth.do`，body `userName=202411413203&authCodeTypeName=reAuthWChatDynamicCodeType`；切换 `POST /authserver/reAuthCheck/changeReAuthType.do`，body `isMultifactor=true&reAuthType=3&service=...`；提交 `POST /authserver/reAuthCheck/reAuthSubmit.do`，成功后跳 `/login?service=<reAuthParams.service>`（取自官方 `reAuth.js`）。
  - 结论：与现有 `cas_auth.dart` 的路径/参数一致，无需修改。
- 浏览器测试会话已通过 `/authserver/logout` 注销（页面显示「注销成功」）。

### 验证与产物
- `flutter analyze` 无问题（改动后）；release arm64 `1.0.1+4125` 构建成功、安装真机；桌面留存 `海畔_1.0.1_4125.apk`。

### 遗留
- 浏览器 MFA 的 `reAuthSubmit.do` 实际响应未抓到（插件通道下该页 POST 挂起），以官方 `reAuth.js` 的参数与跳转逻辑为准。
- 空教室「只看可借」仅验证默认态样式，未在查询结果页截图（验证时已退出登录）。

## 2026-11-25 · Batch64：修复 WebView 退出报错 + 按真实抓包校正登录/登出接口

### 客户端：WebView 页面退出框架报错（`lib/ui/login/sso_login_page.dart`）
- 根因：`_askXh()` 在 `await showDialog` 返回后立刻 `ctrl.dispose()`，而 DialogRoute 还有约 120ms 退场动画，退场中的 `TextField` 继续使用已释放的 `TextEditingController`；异常发生在路由 teardown 阶段，会连带抛出重复 GlobalKey 断言（即交接文档里「GlobalKey / TextEditingController」两类报错）。
- 修复：新增私有 `_XhDialog` StatefulWidget 持有输入控制器并在自身 `dispose` 释放；`_askXh()` 只负责 `showDialog`。
- 加固：新增 `_disposed` 标记，`dispose()` 里同时置 `_done=true`；WebView 的 JS Channel、`_prepare/_enableTunnel/_logPageTip/_inspectWfwPage/_maybeAutoFillSubAuth` 等异步入口在页面销毁后立即返回，避免退出转场期间继续 setState / 读控制器。

### 接口校正（浏览器真实抓取，校园网 + 已登录浏览器）
- 认证登录页（凭据 `credentials: omit` 拉取）：`GET /authserver/login?service=...` 返回 200，表单 `id="pwdFromId" action="/authserver/login"`，隐藏域 `_eventId/cllt/dllt/lt/execution/uuid/rmShown`，`pwdEncryptSalt` 长度 16；验证码接口与 `login.js` 完全一致（`/checkNeedCaptcha.htl`、`/getCaptcha.htl`），现有 `cas_auth.dart` 无需改动。
- 教务登出：教务首页 `jwglxt_index.js` 绑定 `#exit_btn` →
  `window.location = _systemPath + "/logout?t=" + jQuery.now() + "&login_type=" + $("#login_type").val()`；
  本校部署 `_systemPath` 为空，即真实地址 **`/logout?t=<毫秒>&login_type=`**。
  `curl` 实测：未登录访问返回 `302 → /xtgl/login_slogin.html`；旧的 `/xtgl/login_xxlc.html` 也返回 302，但只是普通业务页，**不会注销会话**。
- 认证中心登出：`GET /authserver/logout?service=...` 实测 200 / 无会话时正常返回，保留原实现。
- 代码：`lib/api/auth_api.dart` 退出地址改为 `/logout`（带 `t`、`login_type`，`followRedirects:false`、允许 <500）；`lib/providers/session_provider.dart` 退出顺序改为「先教务 `/logout`、后认证中心 `/authserver/logout`」，避免先清 CAS 导致教务侧无会话可注销。

### 验证
- `flutter analyze`：No issues；`flutter test`：3/3 通过。
- 真机 `d4b532b4`（debug arm64）反复「登录页 → 使用认证网页登录 → 系统返回」3 轮，以及「校外弹出填写学号框 → 连续两次返回」均无 Flutter 异常（`logcat` 无 `E/flutter` / GlobalKey / disposed 记录）。
- 已构建 release arm64 `1.0.1+4124` 并安装真机，桌面留存 `海畔_1.0.1_4124.apk`；因 debug/release 签名不同，验证时卸载重装过一次，本地会话与设置已清空（登录页状态）。

### 遗留
- 官网登录页隐藏域里另有 `uuid`、`rmShown` 字段，现有提交未携带；实测校园网/隧道登录均能通过（服务端未强制），暂不改动，若后续登录异常再补。

## 2026-11-25 · Batch63：退出登录对接认证注销 + 清理测试入口 + 项目文档

- 官方通道定论：WebVPN（wfw）彻底放弃。纯 HTTP、网关入口、真实 WebView 三种方式均在 CAS 认证成功后被打回登录页，判定为网关不接受第三方客户端会话；企业微信靠应用内身份置换进入，海大课表为自有接入方式，均不可复刻。移除登录页 WebVPN 切换按钮与网页入口按钮，`_wfwLogin` 置为 `final false` 保留分支备查。
- 退出登录：新增 `CasAuthApi.logout()`（GET `/authserver/logout?service=`）先注销服务端会话再清 Cookie，`sessionProvider.logout()` 改为先调它，避免服务端保留在线记录导致重复登录。
- 清理：删除桌面/临时目录下的抓包与探针脚本（`*wework*`、`*probe*`、`*monitor*`、`phone_*`）。
- 文档：新增 `docs/PROJECT.md`（10 章，含架构、登录链路、接口、配置、构建发布、已知问题、接手清单）。
- 验证：`flutter analyze` 无问题，release arm64 `1.0.1+4121` 构建成功；真机 USB 断开，安装待重连。
- 遗留：WebView 页面进出时偶发 Flutter GlobalKey / TextEditingController 报错，待修。

## 2026-11-25 · Batch62：考试卡改版 + 官方通道换票失败自动重试（debug）

- 考试卡按「海大课表」样式重做（`exam_page.dart`）：标题 + 考试形式小标签、右侧「还有 N 天」胶囊、独立时间行、整行灰底地点框；去掉原来的「标签+值」多行结构。
- 官方通道：换票挂回 wfw 登录页时，清空网关 Cookie → 重新 prepare/login → 若仍需多因子则提示重新获取验证码，只重试一次（`cas_auth.clearWfwCookies`、`login_page._wfwRetried`）。
- 抓包结论：海大课表登录全程只连 authserver 与 wfw（IPv6），不直连 jw，与我们 WebVPN 前缀方案一致。
- 验证：`flutter analyze` 无问题，debug arm64 构建并覆盖安装。

## 2026-11-25 · Batch61：按「海大课表」的方案实现 WebVPN 登录（认证直连 + 票据受众 wfw）（build 4118）

- 依据（真机抓包 `cn.edu.gdou.schedule`，UID 10419）：启动与登录只连三台校内服务器（jw 210.38.137.108、wfw 网段 210.38.139.201、authserver 210.38.136.93），无第三方后端。
- 命令行验证：直接向 `authserver.gdou.edu.cn/authserver/login` 提交账号密码、`service=https://wfw.gdou.edu.cn/https://jw.gdou.edu.cn/sso/jziotlogin`，密码校验通过并落到 `reAuthCheck/reAuthLoginView.do`（多因子）。
- 代码：
  - `cas_auth.dart`：`_service` 改为实例字段，新增 `useWfw()/useDirect()`；wfw 模式下 `service` 与多因子 `_mfaService` 同步切换；登录/多因子换票成功判定增加 `wfw.gdou.edu.cn` 落点，并新增 `_cookiesAt()` 读取 wfw 域 Cookie。
  - `login_page.dart`：新增「登录路径：校内直连 / 校外 WebVPN」切换按钮；WebVPN 模式跳过自建隧道，成功后调用 `session.loginWithWfw(cookies)`。
- 验证：`flutter analyze` 无问题；arm64 release 1.0.1+4118 构建并安装真机。
- 遗留：待真机完整走一次 WebVPN 登录（含多因子）确认换票与会话建立。

## 2026-11-25 · Batch60：官方通道（wfw）结论定案并移除入口（build 4117）

- 范围：客户端 `login_page.dart`、`sso_login_page.dart`（wfw 代码保留，入口移除）
- 实测证据（真机，纯公网 / 电信移动数据）：
  1. wfw 原路径入口可渲染统一身份认证页，账号密码提交成功并拿到票据，回跳 `wfw/https://jw.gdou.edu.cn/sso/jziotlogin` 后仍是登录页（`密码框=1`）；
  2. 改表单 action 到 jw 前缀 → 白屏；改到 authserver 域前缀 → 命令行复现返回 HTTP 401；
  3. 企业微信在同一公网环境秒进教务，抓包显示只连 wfw、无 authserver 往返、无 jw 直连。
- 结论：网关只接受「已认证的会话」，不接受客户端现场登录换票；企业微信能进是其应用内身份/会话所致，自建 WebView 无法复刻。
- 处理：移除「官方通道（校外 WebVPN）」入口（`_openSso(wfw:true)` 保留，一行可恢复）；主路径仍为自建隧道 + 原生登录。
- 验证：`flutter analyze` 无问题；arm64 release 1.0.1+4117 构建成功，已 `adb install -r` 真机。
- 遗留：企业微信那条链路的身份置换细节未知（未拿到登录后的 URL 参数），若日后要复刻需拿到 WeCom 内「复制链接」的完整地址。

## 2026-11-25 · Batch59：wfw 网关改为原路径直通 / 登录后遮罩保持到教务真正就绪（build 4115）

### 官方通道（wfw）重新定位
- 实测（浏览器 + curl）：
  - `https://wfw.gdou.edu.cn/xtgl/dl_loginForward.html` 返回的是**经网关转发的统一认证登录页**（标题「统一身份认证平台」，含 `pwdEncryptSalt`），并下发 `WFWSESSID`、`urlss_jw=https://jw.gdou.edu.cn/`。
  - `https://wfw.gdou.edu.cn/xtgl/...`、`/kbcx/...` 等**教务原路径**都被网关直通到 jw（200 + 登录页/教务页），说明 wfw 是「按原路径代理 jw」的 WebVPN 网关，不是只有 `/https://jw...` 前缀式反代。
  - `netcheck.gdou.edu.cn/go.php?code=jw` 只是 302 到 `jw.gdou.edu.cn/sso/jziotlogin`，不含任何 WebVPN 逻辑（参考仓库的“自动路由”依赖设备本身能到 jw）。
  - 之前失败原因判断：前缀式入口 + 票据 service 指向 jw 绝对地址，登录后跳出网关。
- `lib/api/jw_client.dart`：`wfwJwBase` 由 `https://wfw.gdou.edu.cn/https://jw.gdou.edu.cn` 改为 `https://wfw.gdou.edu.cn`，wfw 模式下教务请求直接走网关原路径。
- `lib/ui/login/sso_login_page.dart`：官方通道入口改为 `https://wfw.gdou.edu.cn/xtgl/dl_loginForward.html`（带时间戳防缓存）；页面判定从「路径包含 jw.gdou.edu.cn」改为「wfw 域且非 authserver / 非 login 页」；已在教务页（`教学管理信息服务平台`）时不再二次进入入口。
- `lib/ui/login/login_page.dart`：保留「官方通道（校外 WebVPN）」入口供真机验证。

### 登录后遮罩
- 登录成功跳回教务（带 ticket 的 `/sso/` 入口或教务内页）时，遮罩继续保持，文案改为「登录成功，正在进入教务系统…」，直到读取到登录态再收起；此前进度条一到 100% 就撤遮罩，用户对着空白教务页等待。
- 进入教务后 `_tryRead` 同步失败最多等 10 次（约 7s）再放开遮罩，另有 30s 兜底，避免遮罩卡死。

### 版本
- `pubspec.yaml` 1.0.1+4115；`update_api.dart` 仍为 1.0.1（Release v1.0.2 保留供更新测试）。
- 验证：`flutter analyze` 无问题；arm64 release 构建成功；**真机安装待用户重新连接 USB**（构建完成后设备已断开）。

### 模拟器复核（同日）
- 开发机浏览器带登录态且处于校园网，浏览器结论不能代表校外，已写入项目记忆。
- 模拟器（debug x64，清空数据后）从登录页点「官方通道」：WebView 内正常渲染经网关的「统一身份认证」页（URL `wfw.gdou.edu.cn/xtgl/dl_loginForward.html`），页面脚本里 `service = ["https://wfw.gdou.edu.cn/https://jw.gdou.edu.cn/sso/jziotlogin"]`，说明票据回跳仍在网关内。
- 修正误判：入口页路径也含 `/xtgl/`，之前被当成「已进入教务」导致遮罩误开、并触发「已登录→重进入口」循环；现登录路径（含 login）一律不算教务页；网关首页也不再被判为已登录，只在停留在 `/` 时补进一次入口。
- 二次认证自动填充不再要求「先重进入口」才生效。

### wfw 通道最终结论（模拟器实测，已放弃）
- 网关根路径入口 `wfw/xtgl/dl_loginForward.html`：能正常渲染统一认证页，账号密码提交后确实拿到票据并回跳 `wfw/https://jw.gdou.edu.cn/sso/jziotlogin`，但该地址返回的仍是空表单登录页，票据不被教务域接受。
- 尝试把登录表单 action 改写到 `wfw/https://jw.gdou.edu.cn/authserver/login`（同一网关会话内提交）：提交后页面直接空白，登录页消失，同样拿不到教务会话。
- 结论：wfw 网关的 CAS 票据与教务子会话无法在客户端打通，属网关侧集成问题，App 内无法修复。已移除「官方通道（校外 WebVPN）」入口（wfw 内部代码保留，便于日后网关升级后恢复）。

### 原生登录实测（模拟器，校园网直连）
- 账号密码校验通过，`认证落点` 为 `reAuthCheck/reAuthLoginView.do`，正确进入多因子（type=4 企业微信）。
- 多因子面板符合预期：企业微信 / 短信可自行切换，「获取验证码」需手动点击，不再自动发码。
- 耗时：网络通道就绪 1676ms，通道+认证页就绪 2364ms（直连，未走隧道）。
- 凭证只在内存中用于一次密码校验，未写入任何文件，日志中学号已打码。

## 2026-11-25 · Batch58：下载灵动岛文字完整显示 / 个人信息卡换 App 图标 / 去掉校名 / 版本回 1.0.1（build 4114）

### 下载灵动岛
- `lib/ui/widgets/ink_notice.dart`
  - 收起态追加「已下载 / 总大小」（下载中才显示），如 `正在下载 42% · 12.3 MB / 24.0 MB`，不必点开才知道进度明细。
  - 宽度上限由 `屏宽 - 48` 放宽到 `屏宽 - 32`；文字宽度测量后额外留 6px 余量，消除宽度刚好相等导致末尾出现省略号的问题。
  - 一行放不下时自动换两行并把药丸高度一起撑开，不再直接截断文字。
  - 展开态宽度 248 → 300，说明文字（含失败原因）能完整显示。

### 去校名 / 换图标
- `lib/ui/profile/profile_page.dart`：个人信息卡右侧由 `assets/school_logo.png`（校徽）改为 `assets/app_icon.png`（App 图标）。
- `lib/ui/profile/about_page.dart`：免责声明「登录通过广东海洋大学统一身份认证完成」改为「登录通过学校统一身份认证完成」；App 内已无校名文字。
- `pubspec.yaml`：description 去掉校名，改为「海畔 · 教务客户端（非官方）」。

### 版本
- `pubspec.yaml` 回 `1.0.1+4114`，`update_api.dart` appVersion 回 `1.0.1`；GitHub Release 的 `v1.0.2` 保持不变，供应用内更新测试（1.0.1 会检测到 1.0.2）。
- 验证：`flutter analyze` 无问题；`flutter build apk --release --target-platform android-arm64` 成功；`adb -s d4b532b4 install -r` 成功，真机 `versionName=1.0.1 versionCode=4114`。

## 2026-11-25 · Batch57：验证码/设备信任流程（build 4113）

- 验证码不是强制显示：进入登录页（有缓存学号）时调用 `checkNeedCaptcha.htl` 查询，服务端说需要才显示验证码框并拉图；不需要则不显示。提交前再查一次（2 分钟内复用结果）。
- `lib/api/cas_auth.dart`
  - 认证 Cookie 从内存改为 `PersistCookieJar` 落盘（`cas_cookies`），重启后仍带同一套 CAS 会话/信任 Cookie；会话有效时 `prepare()` 可直接拿到教务 Cookie 跳过密码提交。
  - 设备指纹 `bfp` 首次随机生成后写入 SharedPreferences 复用，避免每次启动被认证中心当成新设备而反复要验证码 / 多因子。
  - 新增 `clearCookies()`：更换学号时清空认证会话，避免复用上一个账号的 Cookie。
- `lib/ui/login/login_page.dart`
  - 学号与上次登录一致时保留认证会话；不一致才清空。
  - 服务端返回「不需要验证码」时自动收起验证码输入框（不再一直挂着），并记录日志 `服务端已信任此设备，无需验证码`。

## 2026-11-25 · Batch56：登录提速 / 多因子验证方式手动选择 / 发布 1.0.2 测试更新（build 4112）

### 登录提速（自建页面）
- 校外进入登录页时，原本先 `tunnel.adapt`（校内直连探测最长等 4s）再拉认证页；现在「建隧道 / 探测」与「直连拉认证页」并行，认证页不再等通道。
- 同一学号的验证码预检结果缓存 2 分钟，提交时不再重复请求 `checkNeedCaptcha`（省一次隧道往返）。
- 新增耗时日志：`网络通道就绪 xxms`、`通道+认证页就绪 xxms`、`密码校验 xxms`、`总耗时`，便于后续定位慢点。

### 多因子验证交互
- 不再默认自动发送企业微信验证码：进入多因子状态后由用户选择「企业微信 / 短信」，再手动点击「获取验证码」。
- 切换验证方式只更新选择并清空已发送状态；未发送验证码时点「验证并登录」会提示先获取验证码。

### 版本
- `pubspec.yaml` 1.0.2，`update_api.dart` appVersion 1.0.2，构建号 4112；用于在 GitHub Release 发布 `v1.0.2` 验证应用内更新链路（已安装的 1.0.1 会检测到新版本）。

## 2026-11-25 · Batch55：多因子提交后换票失败 / 官方 wfw 通道登录后不跳转（build 4111）

### 日志结论（`海畔日志_20261125_032927.log.txt`）
- 原生：`03:26:59` 密码通过后 302 到 `reAuthLoginView.do`（type=4）；`03:27:33 / 03:28:22` 两次 `reAuthSubmit.do` 都是 **HTTP 200**，但随后换票落点不是教务：一次 500、一次回到登录页，最终报「多因子验证未生效」。
- `reAuthSubmit.do` 是页面里的 AJAX 接口，服务端返回 JSON、不会自带 302；原实现没带 `X-Requested-With`，也没打印响应体，无法判断成功码与后续跳转地址。
- 官方通道：`03:28:42 / 03:29:04` 两次直接加载 `wfw/https://jw.gdou.edu.cn/sso/jziotlogin` 后再无任何页面事件；深链进入时 wfw 会把登录页渲染在同一路径，登录完成后既不会自动跳转，也因 URL 含 `jw.gdou.edu.cn` 导致「重新进入教务」逻辑永远不触发。

### 修复
- `lib/api/cas_auth.dart`
  - 多因子三个接口（切换方式 / 发码 / 提交）补齐 `X-Requested-With: XMLHttpRequest`、`Accept`、`Origin` 与 `Referer`（多因子页地址），并打印发码与提交的响应片段。
  - `reAuthSubmit` 改为 `followRedirects: false`；成功后解析响应 JSON 里的跳转地址（`url/redirectUrl/reAuthUrl/serviceUrl`），再依次用「服务端跳转地址 → 多因子页 serviceUrl → 登录 service」主动换票；每条候选同时尝试 `authserver/login?service=` 与 service 本身，任何一步落回 jw 域且有 Cookie 即成功。
  - `_followRedirects` 容忍 5xx（拿到落点交给上层换下一个候选）；新增 `_normalizeService` 还原 `\/`、`\u0026`、整段 URL 编码。
  - `prepare` 若遇到上次未完成的多因子页，直接接回验证态并抛 `MfaRequiredException`，不再误报「认证页未下发加密参数」。
- `lib/ui/login/sso_login_page.dart`
  - 官方通道入口从教务深链改为 `https://wfw.gdou.edu.cn/`：先完成 wfw 自身登录，再自动进入 `wfw/https://jw.gdou.edu.cn/sso/jziotlogin` 建立教务子会话（原深链会停在原地）。
  - 新增页面诊断日志（密码框 / 多因子 / 教务标记 / 标题）；「重新进入教务」改为页面加载完、**没有密码表单**且 URL 不含 `login` 时才触发，避免把正在输入的登录页顶掉。
  - 通过 `HpCred` JS Channel 记录用户输入的账号密码（仅内存），wfw 二次认证页出现时自动填充并提交，免重复输入。
- `lib/api/jw_client.dart`
  - `probeLoggedIn` 增加统一认证页判定（`pwdEncryptSalt` / `id="pwdFromId"`），避免 wfw 把登录页渲染在教务路径上时被误判为已登录。

## 2026-11-25 · Batch54：原生登录真正根因——POST 302 票据跳转未被跟随（build 4110）

### 日志结论（`海畔日志_20261125_031352.log.txt`）
- 每次提交后服务端返回「HTTP 302 len=0 @/authserver/login」，App 把 302 当成失败，回落到本地兜底文案「登录失败，请检查学号与密码」，所以用户一直看到「账号密码错误」。
- 用同一套 AES 算法在 PC 复现：假账号得到 `401 + 登录页(含错误提示)`，说明 401 才是密码错误；302 是**认证通过后带 ticket 跳转教务**。
- Dart 的 `HttpClient` 对 POST 的 301/302/303 不会自动跟随，导致票据跳转被丢掉。

### 修复（`lib/api/cas_auth.dart`）
- 新增 `_followRedirects`：手动沿 `Location` 跟随（最多 8 跳，逐跳写日志，隐藏 ticket 查询串），密码登录与多因子提交都改用它。
- 落点判定改为：落回 jw 域即成功；否则才解析服务端错误文案。
- prepare 时若认证中心会话仍有效（GET login 直接跳到教务），直接复用教务 Cookie，不再要求密码盐。
- 保留 Batch53 的 `service` 参数、Origin/Referer、盐值 trim 与响应诊断日志。

### 产物
- arm64 v1.0.1（versionCode 4110）：`C:\Users\Lime\Desktop\海畔-1.0.1-4110.apk`，23,934,837 字节，sha256 `1401ac5d…15dc`。

## 2026-11-25 · Batch53：按真机日志修原生登录（POST 补 service / Origin / Referer，盐值 trim，失败诊断）

### 日志结论
- 桌面日志（`海畔日志_20261125_025758.log.txt`）显示三次原生登录都落在 `/authserver/login`，第一次服务端明确回「您提供的用户名或者密码有误」，后两次只回登录页，无多因子页、无验证码提示。
- 对照学校 `encrypt.js`、`login.js` 与参考项目：原生 POST 少了 `service` 查询参数、`Origin`/`Referer` 头；盐值未 trim（学校脚本会 `trim`）。认证中心按请求里的 service 生成票据，缺省时即使密码正确也会回到登录页。

### 修复（`lib/api/cas_auth.dart`、`MainActivity.kt`）
- POST 改为 `/authserver/login?service=<encoded>`，并补 `Origin`、`Referer`、浏览器 `Accept`。
- 加密前对 `pwdEncryptSalt` 做 trim（Dart 与 Kotlin 双端），长度不足 16 位直接提示改用官方通道。
- 失败诊断日志增强：记录 HTTP 状态、响应长度、最终路径、正文前 160 字；prepare 记录 salt 长度与 execution/lt。
- 密码错误文案追加「如密码已确认无误，请改用官方通道登录」。

### 产物
- arm64 v1.0.1（versionCode 4109）：`C:\Users\Lime\Desktop\海畔-1.0.1-4109.apk`，23,934,837 字节，sha256 `2d5c5da7…ff5e`。
- 若仍失败，新日志会带服务端返回片段，可直接定位是密码解密、验证码还是设备风控。

## 2026-11-25 · Batch52：原生登录补多因子验证；接入官方 wfw 通道；灵动岛动画平滑化；版本回 1.0.1（build 4108）

### 1. 原生登录失败修复（`lib/api/cas_auth.dart`、`lib/ui/login/login_page.dart`）
- 新增 `MfaRequiredException`：密码提交后若落到 `reAuthLoginView.do` / 页面含 `reAuthParams` / 「多因子认证」，解析 `reAuthUserId`、`reAuthType`（4 企业微信、3 短信）并转入验证码流程，而不是笼统报「登录失败」。
- 新增 `sendMfaCode`（`changeReAuthType.do` + `getDynamicCodeByReauth.do`）与 `submitMfa`（`reAuthSubmit.do`，通过后再用教务 service 换 CAS 票据拿 jw Cookie），并按参考实现补 `/authserver/bfp/info` 设备指纹。
- 登录页新增多因子区：企业微信 / 短信分段选择、获取（重新发送）验证码、验证码输入，主按钮变为「验证并登录」；检测到 MFA 时自动按默认方式发一次码。
- 失败文案补充「非常用账号」「账号临时锁定」，避免全部落到「学号或密码不正确」。
- 登录前若客户端仍处于 wfw 模式，先 `clearCookies()` 回落直连，避免 wfw 与本地隧道互相干扰。

### 2. 官方通道（学校 WebVPN / wfw，免自建服务器）
- `lib/api/jw_client.dart`：新增 `wfw` 模式，baseUrl 切到 `https://wfw.gdou.edu.cn/https://jw.gdou.edu.cn`，Cookie 落 `wfw.gdou.edu.cn` 域并用 SharedPreferences 持久化；`setProxyPort` 在 wfw 下直接忽略。
- `lib/providers/session_provider.dart`：新增 `loginWithWfw`，注入 Cookie 后探针校验，失败回滚。
- `lib/ui/login/sso_login_page.dart`：新增 `wfw` 入口模式（`SsoLoginPage(wfw: true)`），直接加载 wfw 反代教务入口，不建隧道；登录成功后自动重进一次教务入口建立教务子会话。
- 轮询门控：wfw 下统一认证页会直接渲染在教务路径上，因此必须等页面加载完成且 DOM 中已无密码表单才开始读 Cookie，否则会在用户输入账号时误判失败（模拟器已复现并修复）；失败容忍从 3 次放宽到 8 次。
- `lib/ui/login/login_page.dart`：新增「官方通道（校外 WebVPN）」按钮。
- `lib/util/campus_tunnel.dart`：`adapt` 先 `await client.ready` 再判断 `wfwMode`，wfw 下不建隧道，避免冷启动时误用本地代理。

### 3. 下载灵动岛过渡动画（`lib/ui/widgets/ink_notice.dart`）
- 放弃 `AnimatedSize` 直接替换子树，改为 `AnimationController` 驱动：宽度/高度/圆角统一插值（easeInOutCubic），收起态与展开态双层叠加，一层淡出缩小、另一层淡入放大，消除展开/收起的跳变。
- 收起态宽度仍按文字实测贴合，展开固定 248 宽；展开高度预留两行说明，状态刷新时不跳动；展开查看详情时延长自动收起时间到 3.6s。

### 4. 版本与 Release
- `pubspec.yaml` 回 `1.0.1`，`appVersion` 回 `1.0.1`，构建号 4108（仅变构建号）。
- 删除 `QingYu327/HaiPan`、`QingYu327/GDOU-APP` 的 `v1.1` 与 `v1.0.2` Release 及对应 tag，两仓库当前最新为 `v1.0.1`；后续未明确要求正式推送时不再新建 Release。

### 5. 验证
- `flutter analyze` 无问题；`flutter test` 3/3。
- 模拟器（x64，Android 16）实测：登录页出现「官方通道（校外 WebVPN）」，点击后 WebView 正常加载学校统一身份认证页（含学号/密码/登录按钮），无报错遮罩。
- 未验证项：真实账号的多因子分支（需用户真机提交后确认短信/企业微信下发的返回结构）。

### 6. 产物
- arm64 v1.0.1（versionCode 4108，versionName 1.0.1）：23,934,837 字节，sha256 `488f0536db4cecacd13623efaec2f0f8b4e1eb3dc4814de1b4bb775345ccfb84`。
- 桌面副本：`海畔-1.0.1-4108.apk`。

## 2026-11-25 · Batch51：发布 v1.1（build 4107），用于验证应用内更新

- `appVersion` 与 pubspec 升至 `1.1.0`，构建号 4107。
- 两个仓库均创建 Release `v1.1`，资产 `haipan-app-release.apk`（23,934,833 字节，sha256 `6eb8e86a932ce98bd3a1d63d9f07a38e9e10f91e58daddf1d97f62cc317e0ee9`），本地与远端 digest 一致。
- 桌面副本：`海畔-1.1-4107.apk`。
- 说明：本版仍是「原生登录 + 自建隧道」；wfw（学校 WebVPN）通道尚未接入，作为下一步可选项。

## 2026-11-25 · Batch50：保留更新页波浪进度；灵动岛贴合文字、展开态收敛（v1.0.2 / build 4106）

### 1. 改动
- `lib/ui/profile/update_page.dart`：恢复 `_WaveProgressBar` / `_WavePainter`；下载中行高仍为 48（与「下载并安装」一致），左侧为带浅色轨道的 12px 波浪进度，右侧原位为「取消下载」按钮，页面内不显示百分比。
- `lib/ui/widgets/ink_notice.dart`：
  - 收起态去掉底部整条进度条，药丸宽度随「正在下载 N%」文字自适应。
  - 展开态固定 248 宽，标题 + 6px 进度条，百分比改为 13 号放在进度条右侧，下方一行「已下载 / 总大小」。

### 2. 回环测试（模拟器 x64 4106）
- `flutter analyze` 无问题，`flutter test` 3/3。
- 截图确认：药丸宽度贴合文字；更新页行内波浪进度带轨道、7% 时可见；展开卡片 248 宽，进度条右侧显示「13%」，不再使用 30 号大字。

### 3. 产物
- arm64 v1.0.2（versionCode 4106）：23,934,837 字节，sha256 `46b4745e348a5ffe58211f29a1f5f674f46888b80216e380bc91468f4205bd70`。
- 已复制到桌面 `海畔-1.0.2-4106.apk`，供真机远程安装。

## 2026-11-25 · Batch49：原生直连统一身份认证；下载卡片原位取消；灵动岛可展开（v1.0.2 / build 4105）

### 1. 改动
- 更新页（`lib/ui/profile/update_page.dart`）：下载中不再显示进度卡片，按钮卡片尺寸/位置不变，内容原位换成「取消下载」；页面内不显示百分比；删除已无引用的 `_WaveProgressBar` / `_WavePainter` 与 `dart:math`。
- 应用内灵动岛（`lib/ui/widgets/ink_notice.dart`）：去掉 `IgnorePointer`，药丸可点击展开/收起；收起态单行文案 + 2.5px 细进度条，展开态（220ms `AnimatedSize`）显示版本、30 号大百分比、6px 进度条与「已下载 / 总大小」。
- 原生登录（新增 `lib/api/cas_auth.dart`、改写 `lib/ui/login/login_page.dart`、`MainActivity.kt` 新增 `cn.gdou.xiuhong/crypto` 通道）：
  - 直接 GET 认证登录页并解析隐藏域（execution/lt/cllt/dllt）与 `pwdEncryptSalt`，service 绑定在同一 CAS 会话上。
  - `checkNeedCaptcha.htl` 判断验证码，`getCaptcha.htl` 取图；全新设备首屏自动展开验证码输入。
  - 密码按认证页 `encrypt.js` 算法原生 AES-CBC/PKCS7 加密（key=salt，明文=64 位随机前缀+密码，IV 随机 16 位），避免引入 Dart 密码学依赖。
  - POST 登录后跟随 302 回到教务，从 CookieJar 取出 jw 域 Cookie，交给现有 `loginWithSso` 完成课表拉取与落盘。
  - 保留「使用认证网页登录」兜底入口；不再冷启动自动弹出 WebView。
- 版本策略：`appVersion` 与 pubspec 保持 1.0.2，仅构建号递增（本批 4105）。

### 2. 回环测试（模拟器 x64 4105）
- `flutter analyze` 无问题，`flutter test` 3/3。
- 原生登录：登录页正常渲染学号/密码表单；提交假账号后直连认证中心返回并展示服务端原文「该账号非常用账号或用户名密码有误」，说明字段、会话、AES 加密与错误解析链路均已打通（无真实账号，成功分支待真机验证）。
- 用 PowerShell 独立复现已确认：GET 登录页 → AES 加密 POST 返回 401 + 错误文案；`checkNeedCaptcha` 返回 JSON、`getCaptcha.htl` 返回图片。
- 下载卡片：下载中按钮原位变「取消下载」，页面无百分比；灵动岛收起态「正在下载 N%」，点击展开显示「海畔 v1.0.2 / 31% / 7.2MB · 22.8MB」。
- 取消后灵动岛显示「下载已取消」并自动消失，按钮恢复「下载并安装」。
- 已知环境问题：模拟器上本次系统下载在 99.94%（23,919,747 / 23,934,565 字节）停滞且状态非 RUNNING，属 DownloadManager/网络侧未收尾，非 UI 逻辑问题；此前 4104 包下载可正常完成。

### 3. 遗留
- 需用真实学号在真机验证原生登录成功分支与验证码场景（`checkNeedCaptcha` 服务端按设备/IP 判定，模拟器与 PC 结果不同）。
- 待发布：arm64 4105 打包后按需替换两个仓库 v1.0.2 资产（versionName 不变，已安装 1.0.2 的用户不会收到更新提示）。

## 2026-11-25 · Batch48：更新下载进度接入应用内灵动岛；下载卡片改版（v1.0.2 / build 4102）

### 1. 改动
- `lib/ui/widgets/ink_notice.dart`：新增常驻 `_DownloadIslandNotice` 与 `InkNotice.showDownloadIsland`。顶部黑底药丸实时显示「正在下载 42%」，底部 2.5px 进度条；跨页面常驻，结束/取消/失败后停留 1.8 秒自动收起。
- `lib/ui/profile/update_page.dart`：
  - 下载中改为一张 `InkCard`：顶部波浪进度，百分比 26 号居中，右侧独立圆角「取消」按钮。
  - 删除「可退出本页…」等灰色小字，只保留一行「进度已同步到顶部灵动岛」。
  - 完成后提示改为正文加粗「vX 下载完成」。
  - 开始下载时拉起灵动岛；页面重建时自动补挂。

### 2. 回环测试（模拟器 x64 4104，临时以 1.0.1 检查 1.0.2）
- `flutter analyze` 无问题，`flutter test` 3/3。
- 下载中截图：顶部黑色药丸显示「正在下载 3%」，卡片百分比居中、取消为蓝色圆角按钮，无冗余灰色小字。
- 返回「我的」页：药丸仍在，11% → 13% 持续更新。
- 点取消：药丸短暂显示「下载已取消」后消失，卡片恢复「下载并安装」。

### 3. 发布
- arm64 4102 已构建：23,934,565 字节，sha256 `ca7099af…`。
- 两个仓库 v1.0.2 的 `haipan-app-release.apk` 均已替换为该包，GitHub digest 与本地一致。
- 说明：后台下载仍由系统 DownloadManager 执行；应用内灵动岛仅在 App 前台显示，系统通知栏进度继续作为后台补充。

## 2026-11-25 · Batch47：更新下载改为系统下载；按钮随内容滚动（v1.0.2 / build 4100）

### 1. 原因
- 更新按钮固定在底栏，用户希望它回到更新日志末尾，随内容滚动。
- 原下载在页面内用 Dio 执行，退出页面或长时间后台容易中断，且没有系统进度通知。

### 2. 改动
- `lib/util/update_downloader.dart`（新增）：单例下载状态，交给 Android DownloadManager 执行；支持镜像优先、失败自动回退直连；进度每 600ms 查询；任务 id 持久化，重进页面自动恢复进度与安装入口。
- `android/.../MainActivity.kt`：新增 `startUpdateDownload / queryUpdateDownload / cancelUpdateDownload / installDownloaded`，使用 `setDestinationInExternalFilesDir` + `VISIBILITY_VISIBLE_NOTIFY_COMPLETED`，通知栏持续显示「海畔 vX / 正在下载更新包」与进度。
- `lib/ui/profile/update_page.dart`：移除固定底栏，按钮/波浪进度移到更新日志末尾；状态区分下载中、已完成（立即安装）、失败（重新下载）；文案提示可退出页面后台继续。
- 删除已无引用的 `lib/util/apk_installer.dart`；`appVersion` / pubspec 升至 1.0.2。

### 3. 验证（模拟器 x64 4101，临时以 1.0.1 身份检查 1.0.2）
- 下载中切 HOME：18% → 37%，后台持续推进。
- 返回应用进度 37%，退出更新页再进入恢复为 42%。
- 系统通知标题「海畔 v1.0.2」、正文「正在下载更新包，可在后台继续」。
- 完成后面板显示「v1.0.2 下载完成 / 立即安装」。
- `flutter analyze` 无问题；`flutter test` 3/3；arm64 4100 已构建并上传两个仓库的 v1.0.2 Release（sha256 `1aa6328c…`，与本地一致）。
- 注意：模拟器网络初始为 PARTIAL_CONNECTIVITY，DownloadManager 会一直等待；将网络验证恢复后才开始下载。真机正常联网不受影响。

### 4. 说明
- 状态栏进度由系统 DownloadManager 提供；是否进入 HyperOS「灵动岛」取决于 ROM 对下载通知的展示策略，通知栏与锁屏一定可见。
- 1.0.1 用户升级到 1.0.2 仍走旧下载逻辑；装到 1.0.2 后，后续版本才具备后台下载能力。

## 2026-11-24 · Batch46：考试信息等权显示；更新页底部操作条；反馈日志纳入清理（build 4098）

### 1. 改动
- `lib/ui/exam/exam_page.dart`：移除「考试方式」高亮条，改为与时间/地点/类型相同的「图标 + 标签 + 加粗值」行，四项信息等权；仍不展示教学地点。
- `lib/ui/widgets/ink_page.dart`：`InkPageScaffold` 的底部操作条改为全宽实底 + 顶部 hairline，铺到手势条，不再透出背景纹理；更新页「下载并安装 / 已是最新版」使用该底栏。
- `lib/util/app_log.dart`：`clear()` 同时删除私有目录下 `haipan-feedback-*.txt`。
- `lib/ui/profile/storage_page.dart`：反馈导出文件计入「日志」分类，随「清除日志」一起清理。

### 2. 验证
- `flutter analyze` 无问题；`flutter test` 3/3；arm64 4098 构建完成，模拟器 x64 4099 验证：考试卡四项同级、无教学地点；更新页底栏为整宽实底。
- 加速镜像实测：`https://v6.gh-proxy.org/<release apk>` 返回 200、Content-Length 23934865，与源文件一致。
- GitHub Release 资产替换为 4098。

### 3. 说明
- 反馈日志位于 `/data/data/cn.gdou.xiuhong/files/haipan-feedback-<时间>.txt`，每次导出只保留最新一份，卸载应用即消失；现在也可在「设置 → 本地占用 → 日志 → 清除日志」删除。
- 真机 `d4b532b4` 在构建期间断开，4098 尚未推装。

## 2026-11-24 · Batch45：考试卡片重构；管理开关卡片间距；NAS 部署（build 4097）

### 1. 原因
- 考试卡仍展示「教学地点」（与考试地点易混淆且无实际用途）；「考试方式」是关键信息却和普通正文同级，不够醒目。
- 「设备自动换绑」卡片直接插入列表，缺少与相邻卡片一致的间距。
- 本地 `backend/server.js` 的 `/settings` 与换绑逻辑尚未部署到 NAS，管理页开关会读取失败。

### 2. 改动
- `lib/ui/exam/exam_page.dart`
  - 删除「教学地点」行；标题与倒计时保持不变。
  - 「考试方式」改为整宽高亮条：primary 8% 底 + 28% 描边 + 图标，标签小字、值加粗，成为卡片第一视觉层级。
  - 时间/地点/类型改为「图标 + 小字标签 + 加粗值」的三行结构，去掉分隔线与紧凑行距，长文本自动换行对齐；已结束卡片仍整体置灰。
- `lib/ui/profile/usage_page.dart`：`_RebindSwitch` 卡片补 `margin: bottom InkSpacing.m`，与上下卡片间距一致。
- `backend/server.js`：同步到 NAS `/vol1/1000/docker/haipan-api/server.js`（先备份 `server.js.bak-before-settings`），`docker compose up -d --build` 重建 `haipan-api`。

### 3. 验证
- `flutter analyze` 无问题；`flutter test` 3/3；arm64 构建 4097 → `C:\Users\Lime\Desktop\海畔_4097.apk`，已推装真机 `d4b532b4` 并启动无崩溃。
- 真机 UI dump 确认考试卡只剩「考试方式/考试时间/考试地点/考试类型」，无「教学地点」。
- NAS：`/health` 200、`/settings` 未授权 401（路由已生效）、TLS 8443 `/health` 200，容器 `Up`。
- GitHub Release v1.0.1 资产已替换为 4097。

### 4. 备注
- 现有 `haipan.json` 无 `settings` 字段时按「自动换绑开启」处理，无需迁移。
- 后续如需关闭自动换绑：管理员 App →「用户统计」→「设备自动换绑」关闭，立即生效并持久化。

## 2026-11-24 · Batch44：恢复自动换绑并改为管理员开关；更新日志正式排版（build 4096）

### 1. 原因
- Batch42 默认关闭自动换绑，虽安全但换机/清数据必须找管理员重置，日常成本高；需在「安全」与「省事」间可切换。
- 更新页把 Release 的 Markdown 当纯文本显示（`**`、`-`、`#` 原样露出），不像正式更新说明。

### 2. 改动
- `backend/server.js`：新增 `state.settings`（持久化到 `haipan.json`）；`/device/register` 换绑策略改读 `state.settings.allowRebind`，**默认 true（恢复旧的一键换绑）**，仅当管理员关闭时返回 409 `device_mismatch`。
- 新增管理接口 `GET/POST /settings`（仅管理员会话）：读取/修改 `allowRebind`，改完立即 `save()`，无需改代码或重启。
- `lib/api/usage_api.dart`：新增 `fetchSettings()` / `setAllowRebind()`。
- `lib/ui/profile/usage_page.dart`：用户统计页新增「设备自动换绑」卡片开关，先跟手、失败回滚并提示。
- `lib/ui/profile/update_page.dart`：更新日志由 `SelectableText` 改为轻量 Markdown 渲染（标题、无序/有序列表、引用、代码块、分隔线、行内加粗/代码/链接文字），不新增依赖；波浪进度条与「镜像优先、失败回退直连」逻辑保持不变。
- GitHub Release `v1.0.1` 说明重写为「相对 v1.0.0 的新增与改进」，并替换 Release 内 APK 为 4096 构建。

### 3. 验证
- `flutter analyze` 无问题；`flutter test` 3/3；`node --check backend/server.js` 通过。
- arm64 构建 4096 → `C:\Users\Lime\Desktop\海畔_4096.apk`（22.8MB）；Release 资产已更新为 4096。
- 未实测：管理页开关（需先部署新 server.js 并用管理员账号打开用户统计页）、Markdown 渲染视觉效果（可安装 4096 后进更新页查看）。

### 4. 部署
- NAS 重新 `docker compose up -d --build` 后，`/settings` 才可用；`haipan.json` 无需手工迁移，缺省即开启自动换绑。

## 2026-11-24 · Batch43：更新检查切换到新仓库 HaiPan，发布 v1.0.1（build 4095）

### 1. 原因
- 仓库重建为公开的 `QingYu327/HaiPan`（文档 + 主要源码），旧 `GDOU-APP` 不再作为发布源；更新页仍读取旧仓库 Release，会导致新版本无法下发。

### 2. 改动
- `lib/api/update_api.dart`：`githubRepo` 改为 `QingYu327/HaiPan`；`appVersion` 升至 `1.0.1`。
- `pubspec.yaml`：`version: 1.0.1+1`。
- 新仓库创建 Release `v1.0.1`（标题「海畔 v1.0.1」），上传构建产物 `haipan-app-release.apk`；更新页取 Release 中第一个 `.apk` 资产，文件名可任意，但**每次发版必须提升 version 并建同 tag 的 Release**。

### 3. 验证
- `flutter analyze` 无问题；`flutter test` 3/3。
- arm64 构建 4095 → `C:\Users\Lime\Desktop\海畔_4095.apk`（22.6MB）。
- `GET /repos/QingYu327/HaiPan/releases/latest` → tag `v1.0.1`，asset `haipan-app-release.apk`（23.7MB）。
- 旧版 1.0.0 客户端会判定 1.0.1 为新版本并显示下载；1.0.1 自身显示「已是最新」。

### 4. 后续
- 发版流程：改 `appVersion`/`pubspec version` → 构建 → 在 HaiPan 建 `vX.Y.Z` Release 并上传 APK。
- 公开仓库只保留文档与主要源码，APK 仅放 Release，不再入库。

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
- `/tunnel/endpoints` 首位固定下发 `DIRECT_TUNNEL`（默认 `https://8.148.27.215:48644`，名称「国内直连」），其余管理员配置按序去重后追加。
- 101 握手在客户端声明子协议时回显 `Sec-WebSocket-Protocol`（Dart 侧缺该响应头会判定握手失败）。

### 3. 部署（干净容器化）
- 证书用一次性容器生成并持久化到数据卷，不写入镜像（重建镜像不会改变指纹）：
  `docker run --rm -v .../data/tls:/tls docker.m.daocloud.io/alpine/openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 ... -days 3650`
  证书 `CN=haipan-tunnel`，SAN 含 `IP:8.148.27.215`，有效期至 2036-11-21。
- `docker-compose.yml` 增加 `18443:8443` 与 `TLS_PORT`/`DIRECT_TUNNEL`；`Dockerfile` `EXPOSE 8080 8443`。
- 阿里云 TCP 穿透 `8.148.27.215:48644` 指向 NAS `18443`；备份 `server.js.bak-before-tls`、`docker-compose.yml.bak-before-tls` 后 `docker compose up -d --build`。

### 4. 客户端
- 新增 `lib/util/tls_pin.dart`：只信任固定 SHA-256（DER）指纹，`TlsPin.check` 供 `badCertificateCallback`，`TlsPin.client()` 供一次性请求，`TlsPin.shared()` 供 WebSocket 长连接；系统 CA 正常证书不走该回调，Cloudflare 通道不受影响。
- `server_config.dart`：入口测速与配置同步改用固定指纹客户端，直连入口可正常 `GET /health`。
- `campus_tunnel.dart`：两处 `WebSocket.connect` 增加 `protocols: ['haipan-v1']` 与 `customClient: TlsPin.shared()`。
- `usage_api.dart`：`_plain` 改用 `IOHttpClientAdapter(createHttpClient: TlsPin.client)`，设备注册/挑战/验签与所有带令牌请求均可走直连。

### 5. 验证
- `node --check backend/server.js` 通过；`flutter analyze` No issues found；`flutter test` 3 项通过。
- 本机对全新 server.js 起沙箱（临时 `DATA_DIR` + 同证书）跑 8 项端到端：TLS `/health` 200、endpoints 首条为直连、EC 挑战签名换令牌、mux 101 且回显子协议、应用层 PING/PONG、缺子协议被拒、错误令牌 401、明文 HTTP 无响应 —— 全部 PASS。
- 线上：`curl -k https://8.148.27.215:48644/health` → 200（约 0.29s）；本地 `curl -k https://192.168.6.137:18443/health` → 200；公网取回证书指纹 `7392fdcb…57e877` 与生成值一致，`CN=haipan-tunnel` 说明中间无 TLS 卸载。
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
- 实测确认：`202411413202`（白名单内、已绑定旧公钥）用新公钥登记返回 409。

### 2. 改动
- 客户端 `usage_api._authenticate`：全部入口失败时保留服务端原始 `DioException` 上抛。
- 客户端 `sso_login_page`：设备认证与建隧道拆成两段错误处理；4xx 显示“学号验证失败（未加入白名单 / 已绑定其他设备）”，只有超时/断网才显示“校园通道连接失败”。
- 服务端 `/device/register`：公钥不一致不再 409，名单内学号直接覆盖旧绑定，并删除该学号全部旧会话（同一学号单设备生效）；管理页重置能力保留。

### 3. 部署与验证
- 上传 `backend/server.js` 到 NAS，`docker compose up -d --build` 重建容器；`/health` 正常。
- 用临时公钥登记 `202411413202` 返回 200（旧会话失效），随后用原公钥登记恢复绑定，状态文件确认已还原。
- `flutter analyze` 无问题、`flutter test` 通过，构建 2083。
- 端到端（Pixel_7_API36，清空数据后安装 2083，仅移动数据 5G）：
  - 未白名单学号 `999999999999` → `[E] [通道] 学号验证失败`（403），界面文案「学号验证失败：该学号未加入白名单」，不再显示“连接失败”。
  - 白名单学号 `202411413202` → 1 秒内 `设备认证成功`（说明 `/device/register` 走自动重绑返回 200）→ `复用隧道已连接` → 认证页完整渲染出账号密码表单；服务端日志同步出现 `device rebind 20********02`。
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

### 4. 账号准入核验（202411413202）
- `haipan.json`：`allow_app` 已含 `202411413202`，`devices` 有其公钥记录（createdAt 1795437648718）。
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
- 后端已上传 `/vol1/1000/docker/haipan-api/server.js`（备份 `server.js.bak-before-mux`），`docker compose up -d --build` 重建容器成功，启动日志正常。
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
- 实际 compose 目录为 `/vol1/1000/docker/haipan-api`（不是 `/vol1/1000/docker/haipan`，后者是旧副本）。
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
- NAS（Plexus / 192.168.6.137）上运行两套穿透：fnOS 的 Cloudflare Tunnel（主站）与 **ME Frp 客户端**（备用）。
- ME Frp 日志显示 `haipan` 隧道启动成功，公网地址 `https://haipan-api1.cjhong.top`，但该隧道协议被设为 **https**，而本地服务是 `127.0.0.1:18080` 的**明文 HTTP**：
  `转发请求到本地服务 [127.0.0.1:18080] 失败: tls: first record does not look like a TLS handshake`。
- 因此 Cloudflare 收到的是 ME Frp 边缘返回的 502。修复：在 ME Frp 控制台把该隧道协议改为 **HTTP**（本地端口 18080 不变），或保留 HTTPS 隧道但在前面加一层带证书的 nginx/Caddy。
- 已修复并验证（2026-11-23 14:0x）：`https://haipan-api1.cjhong.top/health` → 200（约 0.43s）；云端 `/tunnel/endpoints` 已同时返回主通道与备用通道，客户端故障切换会自动尝试。

### 6. 学号备注（管理员）
- `backend/server.js`：新增 `state.notes`（随 `haipan.json` 持久化）；`GET /notes` 返回全部备注，`POST /notes {xh,note}` 写入/清空（空串删除），均仅管理员会话可读；备注最长 40 字。
- `lib/api/usage_api.dart`：新增 `fetchNotes()` / `setNote()`。
- `lib/ui/profile/usage_page.dart`：用户统计、APP 准入名单、更新黑名单每行显示「备注：xxx」，点击弹出输入框编辑；未填写时显示「点击添加备注」。学号恢复完整展示。

### 7. 公网通道智能选路
- `lib/util/server_config.dart`：新增 `autoSelect()`，启动时并行测速全部入口并自动切到最快；仅在「当前不可达、快 200ms 以上或快过 1.5 倍」时切换，避免抖动；10 分钟内不重复测速；云端入口列表同步后会强制重选一次。
- 手动切换仍会持久化，自动选路只在差异明显时覆盖。

### 8. 提醒与运维增强
- `lib/util/lesson_notifier.dart`：考试当天在自定义提前提醒之外，若提前量 ≥20 分钟，再补一条「即将开考 · 课程」的 10 分钟提醒；两者过近时不重复打扰。提醒 id 仍复用 1000–1499 区间。
- NAS 运维脚本（`/vol1/1000/docker/haipan-api/ops/`）：
  - `backup.sh`：每天 03:30 备份 `data/haipan.json` 到 `backups/`，保留 14 天；
  - `healthcheck.sh`：每 5 分钟探测主入口、备用入口、本地 18080 与 mefrpc 进程，仅在状态变化时写 `ops/health.log`，日志超 2000 行自动截断；
  - 已写入 `lime` 用户 crontab（带 `# haipan-ops` 标记，便于移除）。
- 首次执行结果：`main=200 backup=200 local=200 mefrp=up`，备份文件已生成。

### 9. 验证与部署
- `flutter analyze`：No issues found；`flutter test`：3 passed；`node --check backend/server.js`：通过。
- `flutter build apk --release --target-platform android-arm64 --build-number=2048`：通过（22.6MB），已安装到真机并复制到桌面 `haipan-2048.apk`。
- `flutter build apk --release --target-platform android-arm64 --build-number=2049`：在 2048 基础上加入智能选路，构建通过并安装到真机。
- `flutter build apk --release --target-platform android-arm64 --build-number=2050`：加入考试多段提醒，构建通过并安装到真机。
- 后端已部署到 NAS（`/vol1/1000/docker/haipan-api`，旧文件备份 `server.js.bak-2048`，`docker compose up -d --build` 重建成功）：
  - `http://127.0.0.1:18080/health` → 200
  - `https://haipan-api.cjhong.top/health` → 200，响应头已带 `cache-control: no-store`
  - `/gates` 未带会话 → 401
  - `/notes` 未带会话 → 401；`https://haipan-api1.cjhong.top/health` → 200

## 2026-11-23 · Batch12：公网通道可配置 / 上课提醒诊断 / 标题间距

### 1. 公网入口不再硬编码（多通道 + 故障切换）
- 新增 `lib/util/server_config.dart`：维护入口列表（默认 `https://haipan-api.cjhong.top`），启动先读 SharedPreferences 缓存、后台再向任意可达入口拉取 `/tunnel/endpoints`；提供 `ping()` 延迟探测、`setActive()` 切换、`parseBase()` 输入归一化。
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
- **后端已部署（2026-11-23 11:20）**：`server.js` 上传到 `/vol1/1000/docker/haipan-api/`，旧文件备份为 `server.js.bak-2043`，`docker compose up -d --build` 重建成功。
  - `http://127.0.0.1:18080/health` → `{"ok":true,...}`
  - `https://haipan-api.cjhong.top/health` → `ok=true`
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
- 主机：`192.168.6.137`，用户 `lime`，系统 Debian 12 + Docker Compose v2.40.3。
- 目录：`/vol1/1000/docker/haipan-api`（`data/` 为持久化卷，容器内 `node` uid 1000 可写）。
- 端口：宿主机 **18080** → 容器 8080，避开已有服务的 8080。
- Dockerfile 基础镜像改为 `docker.m.daocloud.io/library/node:20-alpine`：飞牛默认镜像源 `docker.fnnas.com` 对 Docker Hub 返回 401。
- 启动：`cd /vol1/1000/docker/haipan-api && sudo docker compose up -d --build`，容器 `haipan-api`，`restart: unless-stopped`。
- 本机验证：`/gates` 返回 401、`/device/register` 空请求返回 400、日志 `haipan api listening on :8080`。
- 公网：改用新域名 `haipan-api.cjhong.top`（原 `gdouapi.cjhong.top` 仍绑定旧 Worker 白名单，保留不动）。飞牛隧道应用 `com.dustinky.tunnel` 把新域名指向 `http://127.0.0.1:18080`。

### 验证
- `flutter analyze` 无问题、`flutter test` 通过、build 2033 / 2034 / 2035 打包成功（22.8MB）。
- build 2034 把云端地址改为 `https://haipan-api.cjhong.top`。
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
- **重抓结果**（2026-2027-1，账号 202411413203）：
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
策略变化：云端只管理「抢课白名单」与「更新黑名单」；「调试」改回「连点版本号 5 次」本地开关；「用户统计」仅管理员账号（202411413203）可见。
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
- 每个连接先 `UsageTracker.tokenFor(xh)` 取会话，`WebSocket.connect(wss://haipan-api.cjhong.top/tunnel?... , headers: authorization)`；首次失败作废会话并重认证一次。
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

