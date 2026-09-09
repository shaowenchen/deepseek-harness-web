# deepseek-harness-web

用 Docker 跑 dsh web（含登录门）。

## 使用

```bash
cp .env.example .env   # 至少填 API_KEY
mkdir -p data workspace
docker compose up -d --build
```

打开 http://localhost:3080 ，登录令牌默认：

```text
dsh-web-default-token
```

可用环境变量 `TOKEN` 修改。

## 环境变量

与 `docker-compose.yml` / `entrypoint` 一致：

| 变量 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `API_KEY` | 是 | — | 写入容器 `DEEPSEEK_API_KEY` |
| `TOKEN` | 否 | `dsh-web-default-token` | 写入 `DSH_AUTH_TOKEN`，登录页填写此值 |
| `PORT` | 否 | `3080` | 宿主机端口 → 容器 `3080` |

## 目录挂载

| 宿主机 | 容器 | 用途 |
|---|---|---|
| `./data` | `/dsh` | 配置、会话、凭证（`$DSH_HOME`） |
| `./workspace` | `/workspace` | 工作目录 |

## 镜像与 CI

- 镜像：`shaowenchen/deepseek-harness-web:latest`
- Secret：`DOCKERHUB_TOKEN`

## 常用命令

```bash
docker compose logs -f dsh-web
docker compose restart
docker compose down
```
