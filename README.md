# 海畔 · 课表 APP

广东海洋大学教务客户端「海畔」的整体工程：Flutter 客户端 + 自托管 Node 后端（NAS + Docker）+ 三页静态官网 + 开发文档与抓包材料。

> 学习交流用途的非官方项目，与学校官方无关，请以教务系统官方数据为准。

- 当前版本：`1.0.1+4145`（正式线固定 `1.0.1`，只递增构建号）
- 技术文档：[docs/PROJECT.md](docs/PROJECT.md)（现状）、[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)（架构）、[docs/LESSONS_LEARNED.md](docs/LESSONS_LEARNED.md)（经验）
- 官网：[site/index.html](site/index.html)，线上仓库 [QingYu327/haipan-website](https://github.com/QingYu327/haipan-website)（Netlify 自动部署）

## 1. 目录总览

```
haipan app/
├─ README.md                  本文件：定位、入口、目录、约定
├─ jw_app/                    Flutter 客户端主工程
│  ├─ INDEX.md                工程入口、构建、签名、发布说明
│  ├─ README.md               客户端功能与技术栈
│  ├─ lib/ android/ assets/
│  ├─ tool/check_version.ps1  发布前 pubspec / tag 一致性检查
│  └─ RELEASE_NOTES.md        v1.0.0 历史发布说明
├─ backend/                   云端后端（Node + Docker，部署在 NAS）
│  └─ INDEX.md                server.js / Docker / NAS 部署
├─ site/                      官网源文件（首页 + 文档 + 注意事项）
│  ├─ index.html
│  ├─ docs.html
│  ├─ notes.html
│  └─ assets/                 pages.css / pages.js / app-icon.png
├─ docs/                      开发知识库
│  ├─ INDEX.md                文档总索引
│  ├─ PROJECT.md              当前代码现状说明书
│  ├─ PROJECT_SUMMARY.md      项目总结（开工必读）
│  ├─ ARCHITECTURE.md         技术架构与部署
│  ├─ LESSONS_LEARNED.md      经验教训
│  ├─ modification_log.md     历次改动记录（Batch 制）
│  └─ api-handoff/            接口移交与校准（权威契约 api_docs.json）
├─ design/                    设计素材
└─ LICENSE
```

## 2. 一键上手

```powershell
# 客户端（jw_app/）
cd jw_app
flutter pub get
flutter analyze
.\tool\check_version.ps1
flutter build apk --release --target-platform android-arm64 --build-number=4144

# 云端后端（backend/，在 NAS 的 compose 目录执行）
docker compose up -d --build
```

> 后端代码构建进镜像：改了 `server.js` 必须 `--build`，`docker restart` 不会生效。
> 版本号与构建号以安装包为准，Dart 侧不再手写 `appVersion` / `appBuild`；详见 [docs/PROJECT.md](docs/PROJECT.md) §6。

## 3. 功能与形态

| 维度 | 内容 |
|---|---|
| 客户端 | 课表 / 成绩 / 考试 / 学业 / 绩点排名 / 空教室 / 选课抢课 / 提醒与桌面组件 / 检查更新 / 意见反馈 / 设置与日志 |
| 登录 | 原生统一身份认证表单（学号 + 密码 + 验证码 / 多因子）；WebView 认证页兜底；校外经自建隧道 |
| 后端 | 设备认证与令牌、APP 准入白名单、更新黑名单、使用统计、隧道入口下发、WebSocket 隧道 |
| 技术栈 | Flutter / Dart、Riverpod、Dio + PersistCookieJar、Android Keystore、webview_flutter；Node + Docker |
| 官网 | 首页、使用文档、注意事项三页；静态部署，无构建步骤 |

## 4. 版本与发布

- Release 标签格式：`v1.0.1+<构建号>`，例如 `v1.0.1+4145`
- APK 资产名固定为 `haipan-app-release.apk`，官网下载直链依赖该名称
- 发布前运行 `jw_app/tool/check_version.ps1 -Tag v1.0.1+<构建号>`，确保 pubspec、tag 一致
- Release 需要标记为 latest；客户端更新页读取 GitHub `releases/latest`
- 应用内版本来自安装包 `versionName` / `versionCode`，不再依赖源码常量

## 5. 官网

`site/` 是官网源文件，推送后在 Netlify 自动构建：

- 首页：功能、网络、手册入口、下载、免责声明
- 使用文档：安装更新、登录、课表、成绩、考试、空教室、提醒、常见问题
- 注意事项：非官方声明、账号与设备、隐私、公网通道、使用边界、下载安全

同步仓库：GitHub `QingYu327/haipan-website`、Gitee `heaven-does-not-move/haipan-website`。

## 6. 约定

- 包名 `cn.gdou.xiuhong`，应用名「海畔」
- 签名密钥 `jw_app/android/upload-keystore.jks` 与 `jw_app/android/key.properties` 均不入库，需单独备份；换签名会导致老用户无法覆盖安装
- 详细工程纪律与踩坑见 [docs/PROJECT_SUMMARY.md](docs/PROJECT_SUMMARY.md)
- 历史改动记录中的路径保持当时原样，不随后续目录整理改写
