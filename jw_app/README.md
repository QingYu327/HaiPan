# 海畔 · 客户端

基于 Flutter + Riverpod 的广东海洋大学教务客户端，覆盖课表、成绩、考试、学业、排名、空教室与选课等高频场景。**仅用于学习交流**，与学校官方无关，请以教务系统官方数据为准。

当前版本：`1.0.1+4144`。

## 功能

- **课表**：周视图、左右滑切周、学期切换、实践课、当前周标记、今日高亮、离线缓存
- **成绩**：按学期查看成绩 / 绩点 / 加权平均，单科成绩构成（平时 / 期末 / 总评）
- **考试**：按时间排序、剩余天数倒计时、考场与座位、考前提醒
- **学业**：修读进度、分类明细、已修 / 在读 / 未修状态
- **绩点排名**：按统计范围、学年学期、成绩性质查询
- **空教室**：校区 / 楼栋 / 类别筛选，周次 / 星期 / 节次多选，收藏常用教室
- **选课**：课程列表、教学班详情与提交（按学校接口能力）
- **提醒与桌面组件**：原生 AlarmManager 课程/考试提醒；「今日课表」「课表 + 考试」两种组件
- **登录**：原生统一身份认证表单；验证码 / 短信 / 企业微信多因子；WebView 认证页兜底
- **校外访问**：校园网自动直连；校外经自建加密隧道，公网通道按学号准入
- **更新**：GitHub Releases 检查、应用内下载 APK、覆盖安装
- **体验**：顶部灵动岛通知、页面柔和过渡、首启引导、明暗模式、字号与背景设置、分级日志与意见反馈

## 技术栈

- Flutter / Dart · Riverpod（状态管理）
- Dio + PersistCookieJar（正方纯 Cookie 鉴权）+ webview_flutter（认证页兜底）
- Android Keystore（EC P-256 设备密钥、AES 密码加密、安全存储）
- 原生 MethodChannel：认证、代理、通知、桌面组件、安装器
- 本地缓存：SharedPreferences / 应用私有目录

## 构建

```powershell
flutter pub get
flutter analyze
.\tool\check_version.ps1
flutter build apk --release --target-platform android-arm64 --build-number=4144
```

> 构建号必须大于手机已安装包的 `versionCode`。`android/gradle.properties` 已关闭单 ABI 偏移，`versionCode` 严格等于 `--build-number`。

## 版本与更新

- 版本号格式：`1.0.1+<构建号>`，Release 标签 `v1.0.1+<构建号>`
- Dart 侧不手写版本常量，统一由 `lib/util/build_info.dart` 读取安装包 `versionName` / `versionCode`
- `lib/api/update_api.dart` 返回 `UpdateCheckResult`：`hasUpdate` 控制首页弹窗，`isCurrent` 控制更新页置灰展示
- 发布前用 `tool/check_version.ps1` 校验 pubspec 与 tag 一致

## 签名（务必妥善保管）

- `android/upload-keystore.jks`（RSA2048，CN=XIUHONG）
- `android/key.properties`（storeFile / storePassword / keyAlias / keyPassword）

两者均被 `.gitignore` 忽略，需另行备份；后续发布必须沿用同一密钥，否则用户无法覆盖安装。

## 目录结构

```
jw_app/
├── lib/
│   ├── api/            # 教务接口、统一认证、设备认证、更新
│   ├── models/         # 数据模型
│   ├── providers/      # Riverpod 状态与会话
│   ├── theme/          # 水墨主题与设计令牌
│   ├── ui/             # 登录/课表/成绩/考试/学业/排名/空教室/我的/设置
│   ├── util/           # 隧道、缓存、日志、提醒、版本信息、更新下载
│   └── main.dart
├── android/            # Android 工程（cn.gdou.xiuhong）
├── assets/             # 校徽 / 头像 / 应用图标
├── tool/               # 发布前版本检查
├── README.md
└── RELEASE_NOTES.md    # v1.0.0 历史发布说明
```

## 隐私与安全

- 账号密码只用于登录学校教务系统，不上传到第三方服务器；密码仅在提交时加密使用，不落盘
- 登录会话使用教务 Cookie 与本机加密存储；清除数据会回到登录页
- 公网通道只保存设备公钥、学号与准入名单，不保存成绩与课表全文
- 更新检测使用 GitHub 公共 Releases，不内嵌任何令牌

## 版本

当前以根目录 [README.md](../README.md) 与 [docs/PROJECT.md](../docs/PROJECT.md) 为准；v1.0.0 历史说明见 [RELEASE_NOTES.md](./RELEASE_NOTES.md)。
