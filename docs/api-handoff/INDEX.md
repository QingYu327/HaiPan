# api-handoff · 教务接口移交与校准资料

本项目最早的「接口层交付物」：从已登录网页抓包逆向正方教务（zftal-ui）的接口契约，供客户端直连 HTTP 使用。

## 文件

| 文件 | 内容 |
|---|---|
| [README_HANDOFF.md](README_HANDOFF.md) | 移交总说明：鉴权结论、8 组功能接口总览、调试桥与抓取方法 |
| [api_docs.json](api_docs.json) | **权威契约**：`meta / auth / endpoints` 三段，含 URL、参数、响应字段 |
| [GITHUB_RESEARCH.md](GITHUB_RESEARCH.md) | 正方教务开源方案调研（Dawn-Course / zfn_api / 抢课脚本等）与本校接口映射 |
| `calibration/` | 抓包校准样本：各接口的 JSON/JS 快照（`xsxk*`、`cjpmtj*`、`kscx`、`xsxy`、`zzxkYzb.js`） |
| `evidence/` | 页面脚本取证文本：成绩（`js_cj.txt`）、课表（`js_kb.txt`）、选课（`js_xk.txt`） |

## 说明

- 校准样本是「现场证据」，字段语义以 `api_docs.json` 与实际响应核对为准；抓包值里的空格、大小写等隐形字符使用前要清洗。
- `README_HANDOFF.md` 提到的 `tools/bridge_daemon.js` 属当时的独立移交包，**未随本项目归档**；相关脚本目录已在 2026-11 清理。
- 早期 `api-captures/` 抓包样本已在 2026-11 清理；接口契约以 `api_docs.json` 为准，校准样本见 `calibration/`。
