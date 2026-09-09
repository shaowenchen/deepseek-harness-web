# deepseek-harness-web · 容器化部署 dsh Web

用 Docker 部署 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的 **`dsh web`**，浏览器直接使用。

## 快速开始

```bash
cp .env.example .env   # 填 API_KEY
docker compose up -d --build
open http://localhost:3080
```

启动日志里会打印带 `token` 的 URL。一般打开 `http://localhost:3080` 即可；若校验失败，从 `docker compose logs dsh-web` 复制完整 URL。

## 环境变量

| 变量 | 必填 | 默认 | 说明 |
|---|---|---|---|
| `API_KEY` | ✅ | — | 模型 API Key |
| `PORT` | | `3080` | 宿主机端口 |
| `BASE_URL` | | 官方默认 | 可选 API 端点（兼容网关） |
| `TRUSTED_HOST` | | 空 | 反代域名，如 `chat.example.com` |

## 项目结构

```
├── Dockerfile / docker-compose.yml / Makefile
├── .env.example
├── scripts/entrypoint.sh
├── deploy/nginx.conf.example
└── dsh/cordis.patch.yml   # 让 web 监听 0.0.0.0
```

## 为什么需要 `dsh/cordis.patch.yml`

`dsh web` 默认只绑回环，且拒绝 `--host 0.0.0.0`。容器对外服务靠 home 级补丁把 `webserver.host` 改成 `0.0.0.0`。仍有启动 token 门控，但不要把端口裸暴露到公网。

## 数据持久化

命名卷 `dsh-data` → `$DSH_HOME`（`/dsh`），会话与设置会保留。

## 反向代理（可选）

`.env` 设 `TRUSTED_HOST=chat.example.com`，示例见 [`deploy/nginx.conf.example`](deploy/nginx.conf.example)。必须保留 `Host` 与 WebSocket 升级。

## 高级用法

模型细节可在 Web「Models」页改，或编辑数据卷里的 `settings.yaml`。挂载工作目录：

```yaml
volumes:
  - dsh-data:/dsh
  - ./workspace:/workspace
```

## 常用命令

```bash
make up / make logs / make down / make clean
```
