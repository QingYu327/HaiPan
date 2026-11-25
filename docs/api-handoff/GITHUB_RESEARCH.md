# 正方教务开源调研 + 本学校接口映射

> 调研目的：为「智慧校园教务 APP」的**课表接入**找成熟可复用的开源方案，并锁定成绩/课表/绩点排名/学业情况/选课各功能的真实接口。
> 调研方式：GitHub 搜索（github-search skill）+ 本机 Edge CDP 抓取的菜单结构（edge-cdp 连接 `127.0.0.1:57184`）。

---

## 一、课表接入开源方案对比（GitHub 搜索结果）

| 仓库 | Stars | 语言/平台 | 适配教务 | 最近更新 | 可复用点 |
|---|---|---|---|---|---|
| **HF-CYGG/Dawn-Course** | 33 | Kotlin + Compose（Android） | **新正方 / 强智 / 青果** | 2026-08-25 | **最贴合需求**：课表解析用 WebView+JS 脚本（QuickJS），云端脚本可更新；Clean 架构、Room、WorkManager 后台、桌面小组件。解析脚本 `app/src/main/assets/js/` 可直接借鉴 |
| openschoolcn/zfn_api | 263 | Python | 新正方 | 2025-01 | **API 契约最佳参考**：覆盖 登录/个人信息/成绩/考试/课表/学业生涯/选课/退课/空教室，附完整返回字段 + 状态码 |
| FarmerChillax/new-school-sdk | 118 | Python | 新正方 | 2026-08-26 | 最新 SDK，多种登录方式，可作为 API 层参考 |
| ceilf6/Auto_courseGrabber | 869 | 脚本（多省市实测） | 正方 | 2026-07-28 | **抢课本模块参考**：并发选课、课程名/课号检索、时间/教师筛选、换课、定时开抢、可视化控制台 |
| whliao5am/zfnew | 139 | — | 新版正方 | 2024-07 | 课表 / 通知 / 抢课 |
| lndj/Lcrawl | 119 | — | 正方 | 2025-06 | 爬虫 |
| znjhahaha/zhengfangqk | 20 | TypeScript | — | 2026-01 | 抢课+成绩+课表，跨端参考 |

### 结论（课表接入）
- **首选复用 `Dawn-Course` 的正方解析脚本**（JS 解析 正方课表 HTML → 结构化课程对象），因为它已经验证过新正方的解析逻辑，且支持云端脚本热更新（教务改版后只更脚本不动 APP）。
- 若学校 正方 暴露结构化 JSON 接口，则直接走 `zfn_api` 的 `get_schedule` 思路（直接 HTTP 调用，无需 WebView）。
- 二者可并存：优先 API（快），API 不可用/返回 HTML 时回退 JS 解析。

---

## 二、本学校（广东海洋大学·正方）接口映射（CDP 菜单抓取 + zfn_api 对齐）

| 功能 | 菜单 URL（gnmkdm 模块） | zfn_api 对应 | 关键返回字段 |
|---|---|---|---|
| 学生成绩查询 | `/cjcx_cxDgXscj.html` | `get_grade(year,term)` | course_id, title, teacher, class_name, credit, category, grade, grade_point, nature |
| 个人课表查询 | `/xskbcx_cxXskbcxIndex.html` | `get_schedule(year,term)` | weekday, time, sessions, list_sessions, weeks, list_weeks, place, campus, evaluation_mode |
| 平均学分绩点排名 | `/cjpmtj_cxPjxfjdpmcxIndex.html` | （绩点排名） | 绩点、排名、同专业/同年级百分位 |
| 学生学业情况查询 | `/xsxyqk_cxXsxyqkIndex.html` | `get_academia()` | situation(修读情况), display_term, max_grade, category |
| 自主选课（核心） | `/zzxkyzb_cxZzxkYzbIndex.html`（gnmkdm=N253512） | `get_block_courses` / 选课 / 退课 | class_id, do_id, teacher_id, kklxdm, capacity, selected_number, optional |
| 考试安排 | `/kscx_cxXsksxxIndex.html` | `get_exam_schedule` | time, location, zwh, ksfs, sjbh |
| 空教室查询 | （选课/查询类，待抓） | `get_empty_classroom` | 楼栋、节次、空余教室 |

> 说明：菜单 URL 需要通过 `?gnmkdm=xxx` 带模块码访问。**已确认所有数据 POST 仅依赖登录 Cookie，无 token、无 CSRF、无 `_t` 防重放时间戳**（选课批量快选仅传 `xkkz_id`）。具体字段与报文已由 CDP 实抓 + 静态 JS 分析确认，见 `api_docs.json`。

---

## 三、APP 功能模块 × 开源复用策略

1. **首页 / 课表**（UI 优化，非原页面）
   - 数据：调用 `/xskbcx_cxXskbcxIndex.html` 接口 → 解析（API JSON 优先，HTML 回退 Dawn-Course 脚本）。
   - UI：周视图/日视图卡片、周次切换、调课识别、上课提醒（WorkManager/本地通知）。
2. **学业**
   - 成绩总览：`/cjcx_cxDgXscj.html` → GPA 柱状图 + 趋势。
   - 绩点排名：`/cjpmtj_cxPjxfjdpmcxIndex.html` → 排名百分位。
   - 学业情况：`/xsxyqk_cxXsxyqkIndex.html` → 学分进度条、毕业预警红绿灯。
3. **工具**
   - 空教室（按楼栋/节次）、GPA 计算器（输入预期分反算卷面）、教学评价批量打分（一键高分提交，带防漏校验）。
4. **抢课（核心）**
   - **开放检测**：后台定时轮询 `/zzxkyzb_cxZzxkYzbIndex.html`，识别 `iskxk=1`（选课开启）→ 系统通知栏推送「选课已开放，可开始抢课」。
   - **内置抢课**：APP 内配置「目标课程 + 教师 + 优先级 + 备选方案 + 定时触发」，直接构造选课 POST（并发、QPS 限流、指数退避），参考 `Auto_courseGrabber`。
   - 实时日志 + flutter_local_notifications 推送结果。
5. **我的**：多账号切换、成就徽章墙（GPA/抢课成功率自动发放）、通知公告列表。

---

## 四、技术约束落地
- **CDP 仅开发期**：用 Playwright/edge-cdp 连已登录 Edge 抓接口，输出 `api_docs.json`；运行期 APP 直连 HTTP 接口，不依赖浏览器。
- **验证码**：登录用「首次手动输码抓 Cookie 复用」(B 方案)；选课若验码再切 OCR(A)。
- **数据展示**：所有数据经接口获取后在 APP 前端自定义 UI 渲染，绝不展示原教务页面。

---

## 五、下一步建议
1. **接口已基本校准完成**（见第六、八节 + `api_docs.json`）：绩点排名 / 学业情况 / 考试 三项真实返回已实抓确认，成绩/课表/选课早已确认。
2. **课表解析路线已定**：本校 正方 课表接口返回**结构化 JSON**（`data.kbList` 等），**直接走 API 解析，不需要移植 Dawn-Course 的 HTML 解析脚本**。Dawn-Course 仅作字段命名参考即可。
3. 开始落地：先搭 Flutter 工程 + 网络层（Cookie 会话、无 token） + 登录（RSA+captcha 首次手动），再按「课表 → 成绩 → 学业 → 抢课开放检测 → 内置抢课」顺序实现。

---

## 六、2026-08-29 进展（静态 JS 分析 + 用户核地址）
- **用户直接访问确认了 3 个核心页面 URL + gnmkdm**：成绩 `N305005`、课表 `N2151`、绩点排名 `N309106`，均无 404 风险。
- **数据接口从功能 JS 静态分析抠出（capture_apis_v4 产出 js_cj.txt / js_kb.txt / js_xk.txt）**，已写入 `devkit/api_docs.json`（confirmed 版）：
  - **成绩**：POST `cjcx_cxDgXscj.html?doType=query`，body `{xnm,xqm,zd_fzdm:N305005-xs,...}` → jqGrid JSON `{rows:[...]}`。
  - **课表**：POST `kbcx/xskbcx_cxXsgrkb.html`，body `{xnm,xqm,kzlx:'ck',...}` → **JSON**（`kbList`/`sjkList`/`xsxx` 等），**确认无需 HTML 解析**。
  - **选课开放检测**：GET 选课页 HTML 取 `#iskxk`，`== '1'` 即开放、`'0'` 锁定（已确认）。
  - **选课-课程列表**：POST `zzxkyzb_cxZzxkYzbPartDisplay.html` `{xkkz_id,kklxdm,...}`。
  - **选课-教学班列表**：POST `zzxkyzbjk_cxJxbWithKchZzxkYzb.html` `{kch_id,xkkz_id,...}` → JSON 含 `jxb_id`。
  - **选课-批量快选**：POST `zzxkyzb_xkZzxkyzbQuickly.html` `{xkkz_id}` → `{flag,msg}`。**关键：无 token / 无 _t，仅 xkkz_id**。
  - **选课-单教学班选课（定向抢课目标端点）**：`zzxkyzb_xkZzxkyzb.html`（推断，待实抓确认）。
- **会话结论**：所有数据 POST 仅依赖 `JSESSIONID` Cookie，无 CSRF token、无防重放时间戳 → APP 运行期直连 HTTP 即可，CDP 仅开发期辅助。
- **桥 WS 仍被卡**：`127.0.0.1:57184` WS 升级不返回 101（桥「同刻仅一 WS 连接」未释放）。恢复后命令：`cd jw-app/devkit && node capture_apis.js 57184 https://jw.gdou.edu.cn`。但页面 URL 已由用户直接确认，静态分析已覆盖大部分接口，实抓仅用于校准绩点排名/学业情况/考试三项 body 与课表字段枚举。

---

## 七、校准闭环状态（2026-08-29 二次校准后）
- ✅ **绩点排名**：实抓 JS `cjpmtj.js` 确认接口 `cjpmtj_cxPjxfjdpmcxIndex.html?doType=query` + `paramMap()`（qsXnxq/zzXnxq/cjxzm/tjfw/cjbjArr）+ colModel（xh/xm/pjxfjd/pm/jgmc/njmc/zymc/bj）。响应为 jqGrid `{items:[...]}`。
- ✅ **考试安排**：**实抓真实报文**（`calibration/kscx.json`）：POST `kscx_cxXsksxxIndex.html?doType=query&gnmkdm=N358105`，body `xnm=2026&xqm=3&...queryModel.showCount=15&...`，响应 `{items:[...],totalCount,...}`。
- ✅ **学业情况**：**实抓真实成绩**（`calibration/xsxy.json`，含真实成绩 思想道德与法治 CJ=87 JD=3.7 XF=2.5 等）：POST `xsxyqk_cxJxzxjhxfyqKcxx.html` / `...cxFKcxx.html`，body `fromXh_id=&xfyqjd_id=<动态>&xh_id=202411413203`，响应 JSON 数组含 KCMC/CJ/JD/XF/XQM 等完整字段。
- ✅ **学期码**：从真实响应证实 `xqm=3`=第一学期(秋)、`xqm=12`=第二学期(春)。
- ⏳ **选课·单教学班选课**：端点 `zzxkyzb_xkZzxkyzb.html` 与参数（jxb_id/do_jxb_id/kch_id/jxbzls + xkkz_id）为**高置信推断**（标准正方 + 调用签名 `chooseCourseZzxk(jxb_id,do_jxb_id,kch_id,jxbzls)` 已确认）。其函数定义体仅在选课**开放时(iskxk=1)**才加载，当前锁定无法触发实抓。下一位 AI 在选课开放时点任一课程行即可在 Network 看到真实报文（约 2 分钟）。

## 八、二次校准关键改进：常驻调试桥代理（只授权一次）
- 痛点：每次跑脚本都新建 WS 连 57184 桥，Edge 把每条新连接当新会话，反复弹「确认授权」。
- 解法：本包 `tools/bridge_daemon.js` 只握**一次**手（用户点一次授权），之后在本地 `127.0.0.1:9223` 暴露**标准 CDP**；所有校准脚本连本地 9223 复用同一条长连接。桥断开自动重连。
- 校准脚本 `calibrate2~6.js` 均走本地代理，不再申请授权，稳定抓到上述真实报文与 JS。
- 依赖 `ws`（隔离安装于 `C:\Users\Lime\.workbuddy\binaries\node\workspace\node_modules`，未污染用户环境）。

---

## 九、仍 pending（仅 1 项，选课开放后 2 分钟可解）
- 选课单教学班选课 `zzxkyzb_xkZzxkyzb.html` 真实报文（当前 iskxk=0 锁定，函数定义未加载）。其余全部已闭环。
