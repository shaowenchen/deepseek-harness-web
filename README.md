# deepseek-harness-web

DeepSeek Harness 的 Web UI 容器化部署（支持 Railway）。

## 快速开始

```bash
cp .env.example .env
# 编辑 .env，填入 API_KEY
mkdir -p data workspace
docker compose up -d --build
docker compose logs -f dsh-web
```

## 访问

1. 从启动日志复制 URL（含 `?token=...`）：
   ```
   dsh web: http://127.0.0.1:3080/?token=xxxx
   ```
2. 换成本机地址或域名端口，例如 `https://chat.example.com:8443/?token=xxxx`
3. 域名访问时，在 `.env` 设 `TRUSTED_HOST`（与浏览器地址栏 Host 一致，可带端口）

## 环境变量

| 变量 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `API_KEY` | 是 | — | 模型 API Key |
| `BASE_URL` | 否 | 空 | 自定义 OpenAI 兼容网关（设了则 `MODEL` 必填） |
| `MODEL` | 条件 | 空 | 自定义模型 id |
| `PORT` | 否 | `3080` | 宿主机映射端口 |
| `TRUSTED_HOST` | 域名时 | 空 | 信任的 Host，可带端口 |
| `WORKSPACE_DIR` | 否 | `default` | 首次启动在 `/root` 预建的默认工作区目录 |
| `LOG_LEVEL` | 否 | 空 | `debug` 时打印更细的同步日志 |

### 模型路由

- 不设 `BASE_URL` → 走官方 DeepSeek（`API_KEY` 即 DeepSeek Key）
- 设 `BASE_URL` + `MODEL` → 写入 `data/settings.yaml` 的自定义路由并设为默认模型

### S3 数据持久化（可选）

| 变量 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `S3_BUCKET` | 是* | 空 | 桶名，设置了才启用同步 |
| `S3_PATH` | 否 | 空 | 桶内子路径前缀 |
| `S3_ENDPOINT` | 是* | 空 | 如 `https://ks3-cn-beijing.ksyuncs.com` |
| `S3_ACCESS_KEY` | 是* | 空 | Access Key |
| `S3_SECRET_KEY` | 是* | 空 | Secret Key |
| `S3_REGION` | 否 | 空 | 如 `cn-beijing` |
| `S3_PATH_STYLE` | 否 | `0` | `0` 虚拟主机风格（AWS/金山云）；`1` path-style（MinIO/自建） |

*设 `S3_BUCKET` 时必填。

**同步机制**：启动时把桶拉取到容器工作区 `/root`，之后监听 `/root` 变化，有改动才双向同步（本地变更上传、远端新增下载、本地删除回传），退出时最终回传。无需 FUSE，Railway 等平台可用，对金山云 KS3 已验证。

## 目录映射

| 宿主机 | 容器 | 用途 |
|---|---|---|
| `./data` | `/dsh` | 配置与状态 |
| `./workspace` | `/root` | 工作区（dsh 实际读写目录；配了 S3 时同步到桶） |

镜像：`shaowenchen/deepseek-harness-web:latest`
