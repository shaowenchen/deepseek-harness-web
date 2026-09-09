# deepseek-harness-web

```bash
cp .env.example .env
mkdir -p data workspace
docker compose up -d
```

| 变量 | 说明 |
|---|---|
| `API_KEY` | 必填 |
| `TOKEN` | 必填，登录令牌 |
| `PORT` | 默认 `3080` |

数据目录：`./data` → `/dsh`，工作目录：`./workspace` → `/workspace`  
镜像：`shaowenchen/deepseek-harness-web:latest`
