# docs · 文档索引

「海畔」的开发文档与知识库。开工前先读 `PROJECT_SUMMARY.md`，需要接口细节再按模块查；代码现状以 `PROJECT.md` 为准。

当前基线：`1.0.1+4146`（2026-11-27）。

## 文档清单

| 文档 | 内容 |
|---|---|
| [PROJECT.md](PROJECT.md) | 当前代码现状：功能清单、目录、登录链路、更新源、构建发布 |
| [PROJECT_SUMMARY.md](PROJECT_SUMMARY.md) | 项目总结：架构、关键决策、实测经验、开发流程、环境约定 |
| [ARCHITECTURE.md](ARCHITECTURE.md) | 技术架构：客户端分层、认证、隧道、缓存、小部件、后端 API、部署与发布 |
| [LESSONS_LEARNED.md](LESSONS_LEARNED.md) | 经验教训：认证恢复、隧道、部署、小部件、数据口径、协作流程 |
| [modification_log.md](modification_log.md) | 历次改动记录（Batch 制，最新在前，已到 Batch85） |
| [select_course_api.md](select_course_api.md) | 选课 / 抢课接口：课程列表、教学班、提交与 `flag` 语义 |
| [empty_classroom_api.md](empty_classroom_api.md) | 空教室查询接口：请求参数、jqGrid 响应、分页 |
| [release_notes_v1.0.1.md](release_notes_v1.0.1.md) | v1.0.1 用户向更新日志 |
| [api-handoff/](api-handoff/INDEX.md) | 教务接口移交与校准资料（权威契约 `api_docs.json`、GitHub 调研、抓包校准） |
| [specs/](specs/INDEX.md) | 设计文档（2026-08-29 初版设计） |
| [notes/](notes/INDEX.md) | 开发过程记录（抢课脚本 CDP 调试实录） |

## 站外文档

- 官网源文件：`site/index.html`、`site/docs.html`、`site/notes.html`
- 官网仓库：GitHub [QingYu327/haipan-website](https://github.com/QingYu327/haipan-website)（Netlify）、Gitee 镜像
- 根 [README.md](../README.md) 是总入口；客户端细节见 [jw_app/README.md](../jw_app/README.md)

## 维护约定

- **每次改动**：完成即写 `modification_log.md`（日期 + Batch + 范围 + 文件 + 决策 + 验证 + 部署结果），新批次放最上方。
- **架构/流程变化**：同步更新 `ARCHITECTURE.md` 与 `PROJECT.md`，保证文档描述现状而不是历史。
- **新踩坑/新结论**：写入 `LESSONS_LEARNED.md`；不要只留在对话里。
- **版本/更新变化**：同步 `PROJECT.md` §6、`jw_app/README.md` 与根 README 的版本说明。
- **官网变化**：同步 `site/` 与官网仓库，三页导航、版本标签、下载资产名保持一致。
- **敏感信息**：仅放 `.secrets/`（已 gitignore），文档与提交中一律脱敏。

## 说明

- `modification_log.md` 中的历史路径按当时原样保留，不随后续目录整理改写
- 涉及签名口令等敏感内容已脱敏，仅以 `jw_app/android/key.properties` 指代
