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
| `PORT` | 否 | `3080` | 容器映射到宿主机的端口 |
| `TRUSTED_HOST` | 域名访问时建议设 | 空 | 传给 `--trusted-host`，如 `chat.example.com` 或 `chat.example.com:8443` |

## 目录

| 宿主机 | 容器 |
|---|---|
| `./data` | `/dsh` |
| `./workspace` | `/workspace` |

镜像：`shaowenchen/deepseek-harness-web:latest`
