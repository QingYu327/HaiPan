# 海畔 · 广东海洋大学教务客户端（非官方）

一个基于 Flutter + Riverpod 的广东海洋大学教务系统 App，覆盖课表、成绩、考试、学业与排名等高频场景。**仅用于学习交流**，与学校官方无关，请以教务系统官方数据为准。

## 功能

- **课表**：周视图，左右滑动切周，颜色区分课程，可离线缓存查看
- **成绩**：按学期查看成绩、绩点与加权，成绩构成明细（平时/期末）弹窗
- **考试**：考试安排按时间排序、距今天数倒计时
- **学业**：修读进度（已获得 / 最低修读要求学分）、分类课程明细
- **绩点排名**：按统计范围 / 学年学期 / 成绩性质查询
- **个人信息**：年级 / 院系 / 专业 / 班级，校徽
- **离线模式**：课表、成绩、考试、学业均本地缓存，断网可查看
- **检查更新**：GitHub Releases 检测，支持直接下载 APK 并跳转安装
- **设置**：明暗模式、全局字体；维护区含运行日志（可按模块过滤、按天数自动清理）与清理缓存
- **舒适体验**：顶部灵动岛通知、页面柔和过渡、首启功能引导

## 技术栈

- Flutter / Dart · Riverpod（状态管理）
- Dio + PersistCookieJar（正方教务纯 Cookie 鉴权）
- SharedPreferences / path_provider（本地缓存与设置）
- 登录含 zfdun 滑块验证 + RSA 密码加密（pointycastle）

## 构建

```
flutter pub get
flutter build apk --release
```

> 沙箱/镜像环境相关约定见仓库内说明（Gradle 采用腾讯/阿里云镜像；path_provider_android 锁定 2.2.17 等）。

### ⚠️ 正式版签名（务必妥善保管）

- 签名密钥：`android/upload-keystore.jks`（RSA2048，CN=XIUHONG）
- 签名配置：`android/key.properties`（storeFile / storePassword / keyAlias / keyPassword）

> **`key.properties`、`*.jks` 均已被 `.gitignore` 忽略，不会入库，口令仅存于本机。** 请把这两个文件另行备份；后续发布必须沿用同一密钥签名，否则用户无法覆盖安装旧版本。

## 目录结构

```
jw_app/
├── lib/
│   ├── api/            # 教务接口封装（auth / client / jw_apis / update）
│   ├── models/         # 数据模型
│   ├── providers/      # Riverpod 状态（session / settings / data_providers）
│   ├── theme/          # 全局主题（含暗色）
│   ├── ui/             # 页面：登录/课表/成绩/考试/学业/排名/选择/我的/设置/关于/引导/日志
│   ├── util/           # 工具：离线缓存、日志、APK 安装、学期解析
│   └── main.dart
├── android/            # Android 工程（包名 cn.gdou.xiuhong）
└── assets/             # 校徽 / 头像资源
```

## 隐私与安全

- 账号密码仅在本地、用于登录学校教务系统，不会上传至任何服务器
- 登录会话走教务 Cookie，凭据持久化于本机；清除缓存可回到登录页
- 更新检测使用 GitHub 公共 Releases，不内嵌任何令牌

## 版本

详见 [RELEASE_NOTES.md](./RELEASE_NOTES.md)。