# backend · 云端后端（Node 20 + Docker）

「海畔」的云端能力：设备认证与令牌、APP 准入白名单、更新黑名单、使用统计、公网入口下发与 WebSocket 隧道。部署在飞牛 NAS，由 Cloudflare Tunnel（主）与 ME Frp（备）对外。

## 接口

| 方法 | 路径 | 鉴权 | 说明 |
|---|---|---|---|
| POST | `/device/register` | 无（白名单校验） | 登记设备公钥；公钥不一致时覆盖旧绑定并作废该学号旧会话（单设备生效） |
| POST | `/auth/challenge` | 无 | 一次性挑战码（2 分钟） |
| POST | `/auth/verify` | 无 | 验签并签发 30 分钟令牌 |
| GET | `/health` | 无 | 健康检查 |
| GET/POST | `/tunnel/endpoints` | 令牌 | 读取/更新公网入口列表 |
| GET | `/gates` | 令牌 | APP 准入与更新黑名单 |
| GET | `/permission` | 令牌 | 当前账号权限 |
| GET/POST | `/notes` | 管理员令牌 | 学号备注 |
| POST | `/perm` | 管理员令牌 | 名单增删、重置设备 |
| GET/POST | `/settings` | 管理员令牌 | 运行开关（设备自动换绑） |
| WS | `/tunnel` | 令牌 | 隧道转发 |

## 文件

| 文件 | 说明 |
|---|---|
| [server.js](server.js) | 当前全部逻辑：认证、令牌、名单、备注、隧道 |
| [docker-compose.yml](docker-compose.yml) | NAS 部署定义（18080→8080，数据卷 `./data`） |
| [Dockerfile](Dockerfile) | Node 20 Alpine，`server.js` 构建进镜像 |
| `data/haipan.json` | 运行时数据：设备公钥、名单、备注、入口配置（不进仓库） |
| [worker.js](worker.js) / [wrangler.toml](wrangler.toml) | 早期 Cloudflare Worker 方案，保留作历史，不再部署 |

## 部署

在 NAS 的 compose 目录（`/vol1/1000/docker/haipan-api`）执行：

```bash
cp server.js server.js.bak-$(date +%m%d)
docker compose up -d --build
docker exec haipan-api grep -c "<本次改动标记>" /app/server.js
```

> 代码构建进镜像，`docker restart` 不会更新；必须 `--build`。目录以 `docker inspect` 的 `com.docker.compose.project.working_dir` 为准。

管理员学号由 compose 的 `ADMIN` 环境变量指定；生产数据与凭据不要写入公开文档。
