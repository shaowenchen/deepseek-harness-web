# deepseek-harness-web

```bash
cp .env.example .env
mkdir -p data workspace
docker compose up -d --build
```

| 变量 | 说明 |
|---|---|
| `API_KEY` | 必填 |
| `TOKEN` | 必填，登录令牌 |
| `PORT` | 默认 `3080` |

- `./data` → `/dsh`（配置与会话）
- `./workspace` → `/workspace`（工作目录）

镜像：`shaowenchen/deepseek-harness-web:latest`  
若容器退出：`docker compose logs dsh-web`
