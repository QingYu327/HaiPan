# jw_app · Flutter 客户端

「海畔」的主工程，包名 `cn.gdou.xiuhong`，版本 `1.0.0+1`，仅 Android。

## 入口

| 事项 | 位置 |
|---|---|
| 应用入口 | `lib/main.dart`（ProviderScope + 登录门卫） |
| 网络出口 | `lib/api/jw_client.dart`（Dio + Cookie 持久化 + 会话过期识别） |
| 业务接口 | `lib/api/jw_apis.dart`（课表/成绩/考试/学业/排名/选课/空教室） |
| 缓存与状态 | `lib/providers/data_providers.dart`、`session_provider.dart` |
| 灵动岛提示 | `lib/ui/widgets/app_notification.dart` |
| 原生通道 | `android/app/src/main/kotlin/.../MainActivity.kt`（notify / nav / secure） |
| 构建配置 | `android/app/build.gradle.kts`、`pubspec.yaml` |

## 目录

```
jw_app/
├─ lib/
│  ├─ api/          auth_api  jw_apis  jw_client  update_api  usage_api
│  ├─ models/       models.dart（课程/成绩/考试/学业/排名/选课）
│  ├─ providers/    session / settings / data_providers
│  ├─ ui/           login timetable grade exam academic rank select profile home onboarding widgets
│  ├─ util/         local_cache app_log lesson_notifier apk_installer secure_store term_utils
│  ├─ theme/        app_theme.dart（Material 3 海洋蓝 + 暗色）
│  └─ main.dart
├─ android/         包名 cn.gdou.xiuhong；签名文件见下
├─ assets/          school_logo / app_icon / author_avatar
├─ pubspec.yaml     依赖与版本（path_provider_android 锁 2.2.17）
├─ README.md        客户端说明（功能、技术栈、隐私）
└─ RELEASE_NOTES.md v1.0.0 发布说明
```

## 构建

```bash
cd jw_app
flutter pub get
flutter analyze
flutter build apk --release
```

> 2026-11-22 整理时已清理 `.dart_tool/`、`build/`、`.idea/` 与根目录 `.pub-cache/`（合计约 748 MB，均为可再生缓存）。首次构建前必须先 `flutter pub get`。

## 签名（务必妥善保管）

| 文件 | 说明 |
|---|---|
| `android/upload-keystore.jks` | 正式签名密钥（RSA2048，CN=XIUHONG），**丢失则无法覆盖安装旧版本** |
| `android/key.properties` | storeFile / storePassword / keyAlias / keyPassword |

两者均被 `.gitignore` 忽略、不入库，仅存于本机，请另行备份。`android/local.properties` 为机器相关 SDK 路径，由 Flutter 自动生成。
