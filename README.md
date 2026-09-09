# deepseek-harness-web

```bash
cp .env.example .env
mkdir -p data workspace
docker compose up -d --build
```

| 变量 | 说明 |
|---|---|
| `API_KEY` | 必填 |
| `TOKEN` | 登录令牌，默认 `dsh` |
| `PORT` | 默认 `3080` |

- `./data` → `/dsh`
- `./workspace` → `/workspace`

镜像：`shaowenchen/deepseek-harness-web:latest`
