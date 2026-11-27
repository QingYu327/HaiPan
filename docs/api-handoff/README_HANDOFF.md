# 教务系统接口移交包（正方 zftal-ui）

> 本包是**接口层交付物**，供下一位 AI 基于此开发「直连 HTTP 接口、不依赖浏览器」的独立教务 APP（Flutter）。
> 当前状态：**接口已基本校准完成**，权威契约见 `api_docs.json`。

---

## 一、核心结论（已确认）

- **鉴权**：纯 Cookie 会话（`JSESSIONID`），**无 token、无 CSRF、无 `_t` 防重放时间戳**。选课批量快选仅传 `xkkz_id`。
- **登录**：RSA 公钥加密密码 + 图形验证码（`rtk`）；首次手动登录后 APP 复用 Cookie。
- **请求头**：数据 POST 通常带 `X-Requested-With: XMLHttpRequest` + `Referer`（正方 `$.post` 自动带）；APP 用 Dio 发 POST 时带上即可。
- **课表返回结构化 JSON**（`kbList` / `sjkList` / `xsxx` 等），APP 直接解析，**不需要 HTML 解析脚本**。
- **学期码**：`xqm=3`=第一学期(秋)，`xqm=12`=第二学期(春)；`xnm`=学年如 `2026`。已从真实响应证实。

## 二、接口总览（`api_docs.json` 为权威）

| 功能 | gnmkdm | 数据接口 | 方法 | 状态 |
|---|---|---|---|---|
| 成绩查询 | N305005 | `/cjcx/cjcx_cxDgXscj.html?doType=query` | POST | ✅ url+body 确认（静态JS） |
| 个人课表 | N2151 | `/kbcx/xskbcx_cxXsgrkb.html` | POST | ✅ url+body+**响应JSON** 确认 |
| 平均学分绩点排名 | N309106 | `/cjpmtj/cjpmtj_cxPjxfjdpmcxIndex.html?doType=query` | POST | ✅ url+paramMap+列 确认（实抓JS） |
| 考试安排 | N358105 | `/kwgl/kscx_cxXsksxxIndex.html?doType=query` | POST | ✅ **实抓报文** 确认 |
| 学业情况 | N105515 | `/xsxy/xsxyqk_cxJxzxjhxfyqKcxx.html` + `...cxFKcxx.html` | POST | ✅ **实抓真实成绩** 确认 |
| 自主选课·列表/开放检测 | N253512 | GET 选课页取 `#iskxk`(1开放/0锁定) | GET | ✅ 确认 |
| 自主选课·批量快选（抢课主链路） | N253512 | `/xsxk/zzxkyzb_xkZzxkyzbQuickly.html` | POST | ✅ 仅 `xkkz_id`，可并发 |
| 自主选课·单教学班选课（定向抢课） | N253512 | `/xsxk/zzxkyzb_xkZzxkyzb.html` | POST | ⏳ **推断(高置信)**，待选课开放 2 分钟确认 |

唯一未 100% 落地的是「单教学班选课」端点——其函数定义体只在选课**开放时**才加载，当前 `iskxk=0` 锁定无法触发。端点与 4 个参数（jxb_id/do_jxb_id/kch_id/jxbzls）+ xkkz_id 已据标准正方与调用签名高度确认，下一位 AI 在选课开放时点任一课程行即可在 Network 里看到真实报文。

## 三、常驻调试桥代理（关键：只授权一次）

每次重连桥都会逼 Edge 重新弹「确认授权」。本包自带 **`tools/bridge_daemon.js`**：它只与 57184 桥握**一次**手，之后在本地 `127.0.0.1:9223` 暴露**标准 CDP**（HTTP+WS）。所有抓取脚本连本地 9223，**复用同一条长连接，不再反复申请授权**。

```bash
# 1) 启动常驻代理（后台），Edge 弹「确认授权」点一次即可
cd 教务移交包/jw-api-handoff
NODE_PATH='C:\Users\Lime\.workbuddy\binaries\node\workspace\node_modules' \
  node tools/bridge_daemon.js
# 日志见 BRIDGE_CONNECTED 即成功；桥断开会自动重连重试

# 2) 之后任意校准脚本都连本地 9223，无需再次授权
NODE_PATH='C:\Users\Lime\.workbuddy\binaries\node\workspace\node_modules' \
  node tools/calibrate2.js     # 抓 绩点/考试/学业/选课 真实 XHR
```

> 依赖 `ws`：已装在隔离环境 `C:\Users\Lime\.workbuddy\binaries\node\workspace\node_modules`（用 `npm install ws` 装的，未污染用户环境）。换机器时 `npm install ws` 即可。

## 四、文件清单

| 文件 | 作用 |
|---|---|
| `api_docs.json` | **接口契约（权威）**：含已确认/推断标注、请求体、响应字段、证据来源 |
| `GITHUB_RESEARCH.md` | GitHub 调研 + 接口映射 + 校准结论 |
| `evidence/js_cj.txt` `js_kb.txt` `js_xk.txt` | 成绩/课表/选课功能页 JS 全文（早期静态分析证据） |
| `calibration/cjpmtj.js` `zzxkYzb.js` | 本次实抓的绩点排名/选课 JS 全文（含 paramMap、chooseCoursesQuickly 等） |
| `calibration/kscx.json` `xsxy.json` `cjpmtj_full.json` | 考试/学业/**绩点排名** 真实报文（实抓） |
| `calibration/xsxk.html` `xsxk_*.json` | 选课页/脚本扫描产物 |
| `tools/bridge_daemon.js` | **常驻调试桥代理**（只授权一次，本地 9223 标准 CDP） |
| `tools/calibrate2.js` `calibrate3.js` `calibrate4.js` `calibrate5.js` `calibrate6.js` | 各轮校准脚本（抓 XHR / 抓 JS / 扫端点） |
| `tools/edge_cdp_lib.js` | 零依赖 Edge CDP 桥客户端（备用） |
| `tools/capture_apis*.js` `api_explorer.py` | 历史抓取/勘探脚本（参考） |

## 五、关键坑（务必告知下一位 AI）

- 桥端口 **57184** 是自定义 WS 桥：HTTP 探活返回 404 属正常；WS 握手路径 `/devtools/browser/__bridge__`，成功返回 101。
- 桥**同刻仅一个 WS 连接**：因此务必用 `bridge_daemon.js` 常驻代理，不要每次跑脚本新开连接（否则反复弹授权）。
- 会话过期会 302 到登录页：校准前确认用户已登录教务。
- 选课接口当前 `iskxk=0`（锁定），单教学班选课 live 点击需等到选课开放。
- 绩点排名 jqGrid 初始 `datatype:"local"`，要点「查询」才发 `doType=query`（端点/paramMap 已从 JS 确认）。
- 学业情况 `xfyqjd_id` 是动态值，APP 须先从页面隐藏域/首屏取得再传。

## 六、APP 开发建议（给下一位 AI）

顺序：网络层（Cookie 会话 + 请求头）→ 登录（RSA + captcha 首登复用）→ 课表（JSON 直解）→ 成绩 → 学业情况 → 绩点排名 → 选课开放检测推送 → 内置抢课（并发 POST）。
三条主链路（课表/成绩/选课批量快选）已无技术悬念可直接写；单教学班定向抢课待选课开放 2 分钟实抓确认后即可接上。
