# deepseek-harness-web

Docker 部署 [dsh web](https://github.com/deepseek-ai/deepseek-harness)。

```bash
cp .env.example .env   # 填 API_KEY
docker compose up -d
open http://localhost:3080
```

| 变量 | 说明 |
|---|---|
| `API_KEY` | 必填 |
| `PORT` | 默认 `3080` |

镜像：`shaowenchen/deepseek-harness-web:latest`  
本地构建：`docker compose up -d --build`
