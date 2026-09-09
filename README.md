# deepseek-harness-web

```bash
cp .env.example .env
mkdir -p data workspace
docker compose up -d --build
docker compose logs -f dsh-web
```

## 访问方式

1. 从日志里复制启动 URL（含 `?token=...`）
2. 把 host 换成你的域名和对外端口，例如：

```text
https://chat.example.com:8443/?token=日志里的token
```

3. 域名访问时在 `.env` 设置 `TRUSTED_HOST`（与浏览器地址栏的 Host 一致，可带端口）

## 环境变量

| 变量 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `API_KEY` | 是 | — | 模型 API Key |
| `BASE_URL` | 否 | 空 | 自定义 OpenAI 兼容网关，如 `https://gateway.example/v1` |
| `MODEL` | `BASE_URL` 有值时必填 | 空 | 自定义模型 id |
| `PORT` | 否 | `3080` | 容器映射到宿主机的端口 |
| `TRUSTED_HOST` | 域名访问时建议设 | 空 | 传给 `--trusted-host`，如 `chat.example.com` 或 `chat.example.com:8443` |
| `S3_BUCKET` | 否 | 空 | 设置后把桶同步到 `/workspace`：优先 s3fs 挂载，无 FUSE 时自动降级 Node SDK 同步 |
| `S3_PATH` | 否 | 空 | 桶内子路径 |
| `S3_ENDPOINT` | `S3_BUCKET` 有值时必填 | 空 | S3 endpoint，如 `https://s3.example.com` |
| `S3_ACCESS_KEY` | 同上 | 空 | Access Key |
| `S3_SECRET_KEY` | 同上 | 空 | Secret Key |
| `S3_PATH_STYLE` | 否 | `1` | `1` 启用 path-style（MinIO / 多数兼容盘） |
| `S3_REGION` | 否 | 空 | 可选 region |
| `SYNC_INTERVAL` | 否 | `30` | Node SDK 同步回传间隔（秒） |

不设 `BASE_URL` 时走官方 DeepSeek（`API_KEY` → `DEEPSEEK_API_KEY`）。  
设了 `BASE_URL` + `MODEL` 时写入 `data/settings.yaml` 的 `llm-pi-ai` 自定义路由，并设为默认模型。

设了 `S3_BUCKET` 时，容器启动会**优先用 s3fs 挂载**桶到 `/workspace`（实时文件系统，需要宿主机有 `/dev/fuse` + `SYS_ADMIN`，compose 已配置）。  
**如果 FUSE 不可用**（如 Railway、macOS Docker Desktop），脚本自动降级为 **Node SDK 同步**（`@aws-sdk/client-s3`，与 storage-console 相同的连接参数，对金山云 KS3 等已验证可用）：启动拉取桶内容到 `/workspace`，并按 `SYNC_INTERVAL` 定时双向回传（无需 FUSE，任何容器平台都能跑）。

## 目录

| 宿主机 | 容器 |
|---|---|
| `./data` | `/dsh` |
| `./workspace` | `/workspace`（未配 S3 时）；配了 S3 时：s3fs 挂载 或 Node SDK 同步的本地目录 |

镜像：`shaowenchen/deepseek-harness-web:latest`
