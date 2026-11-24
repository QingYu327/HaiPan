# 海畔 · GDOU 教务客户端

> 广东海洋大学教务客户端「海畔」的公开展示仓库：保留开发文档与客户端主要源码，
> 不含后端、抓包材料、构建脚本与发布产物。非官方项目，与学校官方无关。

## 功能

课表 / 成绩 / 考试 / 学业进度 / 绩点排名 / 空闲教室 / 选课抢课 / 上课与考试提醒 / 桌面小组件。

安装包只在 [Releases](https://github.com/QingYu327/HaiPan/releases) 提供，源码仓库不含 APK。

## 技术栈

- 客户端：Flutter + Riverpod，Dio + PersistCookieJar，Android Keystore 设备密钥
- 原生能力：AlarmManager 本地提醒、FileProvider 日志附件、桌面小组件（Kotlin）
- 认证：zfdun 滑块 + RSA 密码加密；校外经自托管 WebSocket 隧道访问教务

## 目录

```
docs/                        开发文档（架构、经验、接口、改动记录）
  ARCHITECTURE.md            架构与部署
  LESSONS_LEARNED.md         踩坑与工程纪律
  PROJECT_SUMMARY.md         项目总结
  modification_log.md        历次改动记录（Batch 制）
  select_course_api.md       选课/抢课接口
  empty_classroom_api.md     空闲教室接口
  tcp_tunnel.md              隧道与直连入口
  specs/                     设计文档
jw_app/
  lib/                       客户端主要 Dart 源码
  android/.../kotlin/        原生通道与提醒实现
  pubspec.yaml               依赖清单
```

## 说明

- 本仓库是**裁剪版**：未包含 Gradle 构建配置、资源图片、后端 `server.js`、抓包样本与自动化工具，
  因此不能直接 `flutter build`；完整工程仅本地维护。
- 文档中的域名、IP、学号均已脱敏；示例数据不代表任何真实账号。
- 参考实现仅用于学习交流，请遵守学校教务系统的使用规定，不要用于批量抢课等影响他人的行为。

## 许可

GPL-3.0，见 [LICENSE](LICENSE)。
