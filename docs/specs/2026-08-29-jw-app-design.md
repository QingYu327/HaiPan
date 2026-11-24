# GDOU 教务 APP（jw_app）设计文档

日期：2026-08-29
状态：已确认（用户批准方案，UI 风格按"现代化"要求调整）

## 1. 目标

面向广东海洋大学学生的教务 APP（Flutter，首版 Android），直连正方教务 HTTP 接口（`https://jw.gdou.edu.cn`），不依赖浏览器/WebView，全部数据用自定义 UI 渲染。

接口契约来源：`jw-api-handoff/api_docs.json`（权威）。

## 2. 范围

全部 8 组功能：

| 模块 | 接口 | 状态 |
|---|---|---|
| 登录 | `/xtgl/login_slogin.html` + `login_getPublicKey.html` + `zfcaptchaLogin` | 已知端点，登录 POST 报文未实抓 → 防御式实现（解析登录页表单，动态取 hidden 字段） |
| 课表 | `/kbcx/xskbcx_cxXsgrkb.html` | ✅ confirmed（JSON 直解） |
| 成绩 | `/cjcx/cjcx_cxDgXscj.html?doType=query` | ✅ confirmed |
| 绩点排名 | `/cjpmtj/cjpmtj_cxPjxfjdpmcxIndex.html?doType=query` | ✅ confirmed；radio 值运行时从页面解析 |
| 考试安排 | `/kwgl/kscx_cxXsksxxIndex.html?doType=query` | ✅ confirmed（items 可能空=无考试） |
| 学业情况 | `/xsxy/xsxyqk_cxJxzxjhxfyqKcxx.html` + `cxFKcxx.html` | ✅ confirmed；`xfyqjd_id` 运行时从页面 HTML 提取 |
| 选课列表/开放检测 | 选课页 HTML 取 `#iskxk` | ✅ confirmed |
| 抢课 | 批量快选 `zzxkyzb_xkZzxkyzbQuickly.html`（✅）；单教学班 `zzxkyzb_xkZzxkyzb.html`（⏳ 推断） | 单教学班选课留占位，待选课开放实抓后补 |

## 3. 技术选型

- Flutter 3.47.x stable（安装于 `D:\flutter`），仅 Android 平台
- 状态管理：flutter_riverpod（AsyncNotifier）
- 网络：dio + dio_cookie_manager + cookie_jar（PersistCookieJar 持久化会话）
- 加密：pointycastle（RSA PKCS1 v1.5，modulus/exponent hex）
- 本地缓存：shared_preferences（模块级 JSON 落盘）
- 其他：uuid（rtk）、intl（周次/日期）

## 4. 架构

```
jw_app/lib/
├── main.dart            # ProviderScope + MaterialApp + 路由（登录门卫）
├── theme/app_theme.dart # Material 3 海洋蓝主题
├── api/                 # 纯网络层：JwClient(Dio+CookieJar) + 各模块 Api
├── models/              # 数据模型（StudentInfo/CourseEntry/Grade/Exam/RankItem/Academic...）
├── providers/           # Riverpod：session + 各模块 AsyncNotifier（含缓存读写）
├── util/term_utils.dart # 学期(xnm/xqm)与周次解析(zcd 单双周)
└── pages/               # login / home_shell(底部导航) / timetable / grades / exams
                         # / academic / rank / course_select / profile
```

数据流：Page → Provider(AsyncNotifier) → Api(Dio) → 解析为 Model；缓存 key = `模块:xnm:xqm`。

## 5. 会话与鉴权

- 登录：GET 登录页 → 解析表单 hidden 字段 + 验证码 img src → GET 公钥（modulus/exponent）→ RSA 加密密码 → POST 表单（含验证码）→ 校验响应（失败则从 HTML 提取错误文案）
- 会话持久化：PersistCookieJar（文件存储），启动即恢复
- 过期检测：响应 302 至登录页 / 返回登录页 HTML → 全局跳转登录页

## 6. UI / UX（现代化风格）

- Material 3，种子色海洋蓝（呼应海洋大学），tonal surface + 大圆角(16-20dp)，轻阴影
- 底部 NavigationBar 固定 5 Tab：课表 / 成绩 / 考试 / 学业 / 我的
- 课表：周视图网格（7 列×节次），周次切换，课程卡片按课程哈希取色；sjkList（无固定节次实践课）单独列表区
- 成绩：学期分组 + GPA/加权均分头部统计卡
- 学业：按 KCLBMC 分类的学分进度（XDZT: 1未修/3在修/4已修）
- 抢课页：开放检测（轮询 iskxk）+ 批量快选 + 单教学班占位（`TODO` 标注，选课开放后 2 分钟实抓补齐）

## 7. 错误处理与测试

- 网络错误统一 SnackBar；空数据专门空态
- 验证：`flutter analyze` + `flutter build apk --debug` 每次修改后跑通

## 8. 已知风险

- 登录 POST 具体字段未实抓 → 防御式实现，AuthApi 集中便于修正
- 单教学班选课端点未确认 → 占位
- jqGrid showCount=15 需调大（成绩接口传 200）避免分页遗漏
