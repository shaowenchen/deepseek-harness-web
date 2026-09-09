# deepseek-harness-web

```bash
cp .env.example .env
mkdir -p data workspace
docker compose up -d --build
```

打开 http://localhost:3080 。启动日志里有带 `token` 的 URL，按需打开。

| 变量 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `API_KEY` | 是 | — | 模型 API Key |
| `PORT` | 否 | `3080` | 宿主机端口 |

- `./data` → `/dsh`
- `./workspace` → `/workspace`

镜像：`shaowenchen/deepseek-harness-web:latest`
