# deepseek-harness-web

用 Docker 跑 dsh web（含登录门）。

## 使用

```bash
cp .env.example .env   # 至少填 API_KEY
mkdir -p data workspace
docker compose up -d
```

浏览器打开：http://localhost:3080  
登录令牌默认是 `dsh`（可用环境变量 `TOKEN` 修改）。

本地构建镜像：

```bash
docker compose up -d --build
```

## 环境变量

与 `docker-compose.yml` 一致：

| 变量 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `API_KEY` | 是 | — | 写入容器 `DEEPSEEK_API_KEY` |
| `TOKEN` | 否 | `dsh` | 写入容器 `DSH_AUTH_TOKEN`，登录用 |
| `PORT` | 否 | `3080` | 宿主机端口，映射到容器 `3080` |

## 目录挂载

| 宿主机 | 容器 | 用途 |
|---|---|---|
| `./data` | `/dsh` | dsh 配置、会话、插件数据（`$DSH_HOME`） |
| `./workspace` | `/workspace` | 工作目录 |

`data/`、`workspace/` 已在 `.gitignore`。

## 镜像与 CI

- 镜像：`shaowenchen/deepseek-harness-web:latest`（另有 `master`）
- push `master` 或手动 Run workflow 会构建并推到 Docker Hub
- 仓库 Secret：`DOCKERHUB_TOKEN`

## 常用命令

```bash
docker compose logs -f dsh-web
docker compose restart
docker compose down
```
