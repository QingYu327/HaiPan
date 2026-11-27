# jw_app · 工程入口

「海畔」主工程，包名 `cn.gdou.xiuhong`，版本 `1.0.1+4146`，当前仅 Android。

## 入口

| 事项 | 位置 |
|---|---|
| 应用入口 | `lib/main.dart`（ProviderScope + 会话门卫 + 预热） |
| 网络出口 | `lib/api/jw_client.dart`（Dio + Cookie 持久化 + 隧道代理） |
| 统一认证 | `lib/api/cas_auth.dart`、`lib/ui/login/login_page.dart` |
| WebView 兜底 | `lib/ui/login/sso_login_page.dart` |
| 业务接口 | `lib/api/jw_apis.dart`（课表/成绩/考试/学业/排名/选课/空教室） |
| 设备认证与门控 | `lib/api/usage_api.dart` |
| 版本信息 | `lib/util/build_info.dart`（读取安装包 versionName / versionCode） |
| 更新检查 | `lib/api/update_api.dart`、`lib/ui/profile/update_page.dart` |
| 缓存与状态 | `lib/providers/data_providers.dart`、`session_provider.dart` |
| 原生通道 | `android/app/src/main/kotlin/.../MainActivity.kt` |
| 版本检查脚本 | `tool/check_version.ps1` |

## 目录

```
jw_app/
├─ lib/
│  ├─ api/          auth_api cas_auth jw_apis jw_client update_api usage_api
│  ├─ models/       models.dart（课程/成绩/考试/学业/排名/选课）
│  ├─ providers/    session / settings / data_providers
│  ├─ ui/           login timetable grade exam academic rank select profile home onboarding widgets
│  ├─ util/         build_info campus_tunnel local_cache app_log lesson_notifier secure_store term_utils
│  ├─ theme/        app_theme.dart（水墨视觉 + 暗色）
│  └─ main.dart
├─ android/         包名 cn.gdou.xiuhong；签名文件见下
├─ assets/          school_logo / app_icon / author_avatar
├─ tool/            check_version.ps1
├─ pubspec.yaml     依赖与版本（path_provider_android 锁 2.2.17）
├─ README.md        客户端说明（功能、技术栈、隐私）
└─ RELEASE_NOTES.md v1.0.0 历史发布说明
```

## 构建

```powershell
cd jw_app
flutter pub get
flutter analyze
flutter test
.\tool\check_version.ps1
flutter build apk --release --target-platform android-arm64 --build-number=<递增>
```

产物：`build/app/outputs/flutter-apk/app-release.apk`。
真机：`adb install -r <apk>`；模拟器需 `--target-platform android-x64`。

## 版本与发布

1. 修改 `pubspec.yaml` 的 `version`（正式线固定 `1.0.1`，只递增 `+构建号`）。
2. 运行 `.\tool\check_version.ps1 -Tag v1.0.1+<构建号>`。
3. 构建 APK，安装真机验收。
4. 在 GitHub `QingYu327/HaiPan` 创建同名 tag 的 Release，上传 APK，资产名固定 `haipan-app-release.apk`，标记 latest。
5. 运行日志追加到 `docs/modification_log.md`。

> Dart 侧不再维护 `appVersion` / `appBuild` 常量；版本判断以安装包实际 `versionCode` 为准。

## 签名（务必妥善保管）

| 文件 | 说明 |
|---|---|
| `android/upload-keystore.jks` | 正式签名密钥（RSA2048，CN=XIUHONG），**丢失则无法覆盖安装旧版本** |
| `android/key.properties` | storeFile / storePassword / keyAlias / keyPassword |

两者均被 `.gitignore` 忽略、不入库，请另行备份。`android/local.properties` 为机器相关 SDK 路径，由 Flutter 自动生成。
