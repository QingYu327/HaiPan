# 选课（自主选课 ZzxkYzb）接口文档

> 依据实时抓包与源码逆向整理（教务系统 `jw.gdou.edu.cn`，`gnmkdm=N253512`）。
> 用途：实现 App「抢课」功能的课程列表 / 教学班 / 选课提交。
> 逆向原始材料已在 2026-11 清理，不再随仓库提供；接口细节以本文与 `api-handoff/api_docs.json` 为准。

## 0. 通用约定
- 所有接口均为 **POST**，带 `gnmkdm=N253512`（URL 查询参数）。
- 需携带教务系统登录 Cookie 会话。
- **防重令牌**：每次查询课程列表会返回/使用 `xkkz_xh`（64 位十六进制）。抢课循环里需**每轮实时获取**。
- **不同开课类型（`kklxdm`）属于不同批次（`xkkz_id` 不同）**，如：
  - 主修课程：`kklxdm=01`，`xkkz_id=5A13332652576211E063768926D25E14`
  - 网络课：`kklxdm=10`，`xkkz_id=5A13332652636211E063768926D25E14`
  - （以当次返回为准，勿写死）
- 公共上下文参数（来自页面隐藏域）：`xkxnm=2026`、`xkxqm=3`、`njdm_id=2024`、`zyh_id=1413`、`bh_id`、`ccdm`、`xz` 等，按学生信息传入。

## 1. 课程列表
```
POST /xsxk/zzxkyzb_cxZzxkYzbPartDisplay.html?gnmkdm=N253512
```
关键参数：
```
xkkz_id=...      kklxdm=01(主修)/10(网络课)   kspage=1   jspage=10
xkxnm=2026       xkxqm=3       xkkz_xh=<令牌>         rwlx=1(?) ...
njdm_id=2024     zyh_id=1413   xqh_id=1      jg_id=14
jxbzb=          (教学班串，可为空)
```
返回：
```json
{ "flag":"1",
  "tmpList":[
    { "jxb_id":"...", "kch":"14161506x0", "kch_id":"14161506x0",
      "kcmc":"决策理论与方法", "jxbmc":"(2026-2027-1)-...-01",
      "jxbxf":"2.0", "jxbzls":"1", "kklxdm":"01", "ywzrs"/"yxzrs":"..", "kcrow":"5" }
  ],
  "sfxsjc":"1" }
```

## 2. 教学班明细（含加密提交 id / 余量 / 时间地点）
```
POST /xsxk/zzxkyzbjk_cxJxbWithKchZzxkYzb.html?gnmkdm=N253512
```
关键参数（复用上下文）：
```
kch_id=...   kklxdm=...   xkkz_id=...   xkxnm/xkxqm/njdm_id/zyh_id/xklc ...
```
返回：
```json
[ { "jxb_id":"...", "do_jxb_id":"<64位加密教学班id>",
    "jxbrl":"67"(容量), "yxzrs":"59"(已选), "jxdd":"教室",
    "sksj":"星期一第1-2节{1-8周}...", "jsxx":"教师",
    "kcxzmc":"任选", "kcgsmc":"...类", "xqumc":"湖光校区" } ]
```
> `do_jxb_id` 是**选课提交**的关键入参（`jxb_ids`）。

## 3. 选课提交
```
POST /xsxk/zzxkyzbjk_xkBcZyZzxkYzb.html?gnmkdm=N253512
```
参数：
```
jxb_ids=<do_jxb_id>
kch_id=...
kcmc=<urlencode 课程名，如 (w334900002)(网络课)现代科学技术导论 - 1.5 学分>
rwlx=2   rlkz=0   cdrlkz=0   rlzlkz=1   sxbj=1   xxkbj=0   qz=0   cxbj=0
xkkz_id=...   kklxdm=01|10   njdm_id=2024   zyh_id=1413
xklc=1|3      xkxnm=2026     xkxqm=3        jcxx_id=
```
返回 `flag` 语义：
| flag | 含义 |
|------|------|
| `1`  | 选课成功 |
| `3`  | 选课成功（免费学分已达上限） |
| `0`  | 失败，`msg` 给原因（例：`未缴费，不可选课！`） |
| `6`  | 已选中 |
| `-1` | 容量超出，`msg="fzjxb,jxb_id,yxzrs,blyxrs"` |

## 4. 其它相关接口（逆向确认）
- 开课院系：`POST /xkgl/common_queryKkbmPaged.html?gnmkdm=N253512`
- 校区/专业/课程性质/类别等公共筛选：`/xkgl/common_queryXquListPaged|queryZyPaged|queryKcxzPaged|queryKclbListPaged|queryKcgsPaged|querySkjcList`
- 选课资格/提示：`POST /xsxk/zzxkyzb_cxZkcZzxkYzb.html`、`zzxkyzb_cxXsXktsxx.html`
- 已选课程：`POST /xsxk/zzxkyzb_cxZzxkYzbChoosedDisplay.html`
- 冲突/规则预检（前端提交前）：`POST /xsxk/zzxkyzb_cxXkTitleMsg.html`（`jxb_ids=do_jxb_id` 等）

## 5. 抢课推荐流程（App 内）
每轮抢课循环（避免频繁，受风控限制）：
1. 查列表 `cxZzxkYzbPartDisplay`（拿 `xkkz_xh` 令牌与目标课程 `jxb_id/kch_id`）。
2. 查教学班 `cxJxbWithKchZzxkYzb`（拿 `do_jxb_id` 与余量）。
3. 若有余量 → 提交 `xkBcZyZzxkYzb`，解析 `flag`。
4. `flag=0` 且 `msg` 含"缴费" → 提示用户需缴费；`-1` 满员 → 稍后重试；`1/3/6` → 成功/已选。

> 注意：提交前务必携带当前批次对应的 `xkkz_id`（与所查列表一致），并紧跟最新 `xkkz_xh`。