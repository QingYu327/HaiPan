# backend · 云端后端

「海畔」的云端服务，Node 20 + Docker，部署在飞牛 NAS。

- 接口、文件、部署步骤见 [README.md](README.md)
- 架构与认证/隧道说明见 [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md)
- 历史 Cloudflare Worker 方案（`worker.js` / `wrangler.toml`）保留，不再部署

> 部署目录：`/vol1/1000/docker/haipan-api`；容器 `haipan-api`；宿主端口 18080。
> 改代码后必须 `docker compose up -d --build`，`docker restart` 不生效。
