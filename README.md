# 海畔 · GDOU 项目

> 广东海洋大学教务客户端「海畔」的整体工程：Flutter 客户端 + 自托管 Node 后端（NAS + Docker）+ 开发文档 + 抓包/脚本材料。
> 学习交流用途的非官方项目，与学校官方无关，请以教务系统官方数据为准。

- 状态：**持续开发**（当前 build 2068，2026-11-23）
- 技术文档：[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)（架构）、[docs/LESSONS_LEARNED.md](docs/LESSONS_LEARNED.md)（经验教训）
- 最近更新：2026-11-23（桌面小部件重做、首启权限、隧道优化、管理员设备重绑）

## 1. 目录总览

```
haipan app/
├─ README.md                  本文件：定位、入口、目录、约定
├─ jw_app/                    Flutter 客户端主工程
│  ├─ INDEX.md                工程入口、构建、签名说明
│  ├─ lib/ android/ assets/
│  ├─ README.md               客户端功能与技术栈
│  └─ RELEASE_NOTES.md        v1.0.0 发布说明
├─ backend/                   云端后端（Node 20 + Docker，部署在 NAS）
│  └─ INDEX.md                server.js / Docker / NAS 部署
├─ api-captures/              接口抓包样本
│  └─ INDEX.md
├─ docs/                      开发知识库
│  ├─ INDEX.md                文档总索引
│  ├─ PROJECT_SUMMARY.md      项目总结（开工必读）
│  ├─ ARCHITECTURE.md         技术架构与部署
│  ├─ LESSONS_LEARNED.md      经验教训
│  ├─ modification_log.md     历次改动记录（Batch 制）
│  ├─ select_course_api.md    选课/抢课接口
│  ├─ empty_classroom_api.md  空教室接口
│  ├─ api-handoff/            接口移交与校准（权威契约 api_docs.json）
│  ├─ specs/                  设计文档
│  └─ notes/                  过程记录（抢课脚本调试实录）
├─ tools/
│  ├─ INDEX.md
│  └─ grab-course/            抢课助手.js（油猴）+ auto_grab.js（CDP）
├─ design/                    设计素材（校徽/院徽/参考图）
├─ 海畔_v1.0.0_arm64.apk       已发布安装包（22.4 MB）
└─ LICENSE
```

## 2. 一键上手

```bash
# 客户端（jw_app/）
cd jw_app
flutter pub get                    # 构建缓存已清理，必须先拉依赖
flutter run                        # 直连设备调试
flutter build apk --release        # 打正式包

# 云端后端（backend/，可选；在 NAS 的 compose 目录执行）
cd backend
docker compose up -d --build
```

> 后端代码是构建进镜像的：改了 `server.js` 必须 `--build`，`docker restart` 不会生效。详见 [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)。

## 3. 功能与形态

| 维度 | 内容 |
|---|---|
| 客户端 | 课表 / 成绩 / 考试 / 学业 / 绩点排名 / 空教室 / 选课抢课 / 检查更新 / 桌面小部件 |
| 后端 | 设备认证与令牌、APP 准入白名单、更新黑名单、使用统计、隧道入口下发与 WebSocket 隧道 |
| 技术栈 | Flutter / Dart、Riverpod、Dio + PersistCookieJar、Android Keystore；Node 20 + Docker + Cloudflare Tunnel / ME Frp |
| 登录 | 校外：设备挑战签名换令牌 → 隧道 → zfdun 滑块 + RSA 密码加密（pointycastle） |

## 4. 约定

- 包名 `cn.gdou.xiuhong`，应用名「海畔」
- 签名密钥 `jw_app/android/upload-keystore.jks` 与 `jw_app/android/key.properties` 均不入库，需单独备份；换签名会导致老用户无法覆盖安装
- 详细工程纪律与踩坑见 [docs/PROJECT_SUMMARY.md](docs/PROJECT_SUMMARY.md)
- 历史改动记录中的路径保持当时原样，未随本次目录整理改写

## 5. 版本

- [v1.0.0 发布说明](jw_app/RELEASE_NOTES.md)
