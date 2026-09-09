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
| `S3_BUCKET` | 否 | 空 | 设置后把桶同步到 `/workspace`（Node SDK 同步，无需 FUSE） |
| `S3_PATH` | 否 | 空 | 桶内子路径 |
| `S3_ENDPOINT` | `S3_BUCKET` 有值时必填 | 空 | S3 endpoint，如 `https://ks3-cn-beijing.ksyuncs.com` |
| `S3_ACCESS_KEY` | 同上 | 空 | Access Key |
| `S3_SECRET_KEY` | 同上 | 空 | Secret Key |
| `S3_PATH_STYLE` | 否 | `0` | `1` 启用 path-style（MinIO / 自建）；`0` 虚拟主机风格（AWS / 金山云 KS3 等官方域名） |
| `S3_REGION` | 否 | 空 | 可选 region，如 `cn-beijing` |
| `LOG_LEVEL` | 否 | 空 | `debug` 时打印每次同步的具体文件与流向（`upload ... -> s3://...`） |

不设 `BASE_URL` 时走官方 DeepSeek（`API_KEY` → `DEEPSEEK_API_KEY`）。  
设了 `BASE_URL` + `MODEL` 时写入 `data/settings.yaml` 的 `llm-pi-ai` 自定义路由，并设为默认模型。

设了 `S3_BUCKET` 时，容器启动用 Node 同步守护进程（`@aws-sdk/client-s3`）把桶内容拉取到 `/workspace`，之后**监听 `/workspace` 变化**，有改动才触发双向同步（本地变更上传、远端新增下载、本地删除回传），退出时做最终回传。**无需 FUSE**，Railway 等任何容器平台都能跑。连接参数与 storage-console 相同，对金山云 KS3 等已验证可用。

## 目录

| 宿主机 | 容器 |
|---|---|
| `./data` | `/dsh` |
| `./workspace` | `/workspace`（未配 S3 时）；配了 S3 时由 Node SDK 同步的本地目录 |

镜像：`shaowenchen/deepseek-harness-web:latest`
