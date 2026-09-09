# deepseek-harness-web · 容器化部署 dsh Web

用 Docker 部署 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的 **`dsh web`** 浏览器界面，直接通过浏览器使用，端口暴露到宿主机，模型相关参数通过环境变量配置。

## 项目结构

```
deepseek-harness-web/
├── Dockerfile              # 容器镜像：Node 24 + dsh CLI
├── docker-compose.yml      # 部署编排：端口暴露 / 环境变量 / 数据卷
├── .env.example            # 模型相关环境变量模板
├── dsh/
│   └── cordis.patch.yml    # 部署补丁：让 web 服务监听 0.0.0.0（见下）
└── README.md
```

## 快速开始

```bash
# 1. 配置环境变量
cp .env.example .env
#    编辑 .env，至少填上 DEEPSEEK_API_KEY

# 2. 构建并启动
docker compose up -d --build

# 3. 打开浏览器
open http://localhost:3080
```

启动后日志里会打印一条带 `token` 的 URL（例如
`dsh web: http://127.0.0.1:3080/?token=...`），这个 token 是首次访问换签名 cookie 用的。
**在浏览器里打开 `http://localhost:3080` 即可开始对话**；如果 token 校验失败，从
`docker compose logs dsh-web` 里复制带 token 的完整 URL 再打开一次。

## 环境变量

| 变量 | 必填 | 默认值 | 说明 |
|---|---|---|---|
| `DEEPSEEK_API_KEY` | ✅ | — | DeepSeek API Key（在 `dsh-llm-deepseek` 适配器中按请求解析） |
| `DEEPSEEK_BASE_URL` | | `https://api.deepseek.com` | API 端点；设了 `$DEEPSEEK_BASE_URL` 就优先生效，可用于 OpenAI 兼容网关 |
| `DSH_PERMISSION_MODE` | | `workspace-write` | 权限模式：`read-only` / `workspace-write` / `danger-full-access` |
| `DSH_WEB_PORT` | | `3080` | 宿主机暴露端口（容器内固定 3080） |
| `DSH_TRUSTED_HOST` | | 空 | 额外允许的浏览器信任 authority（反代域名时用） |
| `DSH_LLM_REASONING_EFFORT` | | `high` | 思考强度：`off` / `low` / `high` / `max` |
| `DSH_LLM_MAX_TOKENS` | | `256000` | 单请求输出 token 上限 |

模型默认是 `deepseek-official` 路由下的 `deepseek-v4-flash`（快速）与
`deepseek-v4-pro`（更强），Web 界面里可直接切换。

## 为什么需要 `dsh/cordis.patch.yml`（0.0.0.0 绑定）

`dsh web` 出于安全默认只监听回环地址，并且 **CLI 会直接拒绝 `--host 0.0.0.0`**
（防止把远程代码执行暴露到网络）。容器要对外提供服务，必须让服务监听所有网卡：

- 项目用 **`$DSH_HOME/cordis.patch.yml`**（home 级补丁层）覆盖 `webserver` 行，
  把 `host` 改为 `0.0.0.0`——该补丁层在官方 bundle 补丁之后合成，因此生效；
- 覆盖 `webserver` 行时必须**完整复述该行拥有的所有配置键**（补丁是整行替换 config）。

> 注意：`0.0.0.0` 绑定 + 浏览器信任链仍然受启动 token 门控（Host API 与
> WebSocket 都需要签名 cookie），不是"裸奔"无鉴权，但**不要**把端口直接暴露到
> 公网，如需公网访问请在前方加反向代理 + 认证（见下文）。

## 数据持久化

`docker-compose.yml` 声明了一个命名卷 `dsh-data`，挂载到 `$DSH_HOME`（`/dsh`），
会话历史、设置、凭据、存储都会持久化。数据卷位置：

```bash
docker volume inspect dsh-web_dsh-data   # 查看宿主机路径
```

## 反向代理（可选）

对外提供服务时建议在前面加 nginx / Caddy，并启用 HTTPS：

```
http://localhost:3080  →  https://chat.example.com
```

如需让 `dsh web` 信任该域名（跨域 / Host 校验），在 `.env` 里设置
`DSH_TRUSTED_HOST=chat.example.com`。⚠️ 反向代理必须保留 `Host` 头与 WebSocket
升级（`/api` 下的 SSE 流）。

## 高级用法

### 自定义模型 / 网关

`dsh` 的模型配置热重载：把 `$DSH_HOME/settings.yaml`（挂在数据卷里）中加：

```yaml
llm-deepseek:
  baseURL: https://your-gateway.example.com
  reasoningEffort: low
  maxTokens: 128000
```

或者直接用 Web 界面左侧「Models / 模型设置」页修改，效果相同且无需重启。

### 挂载宿主机工作目录

默认工作目录（`{{cwd}}`）是容器内的 `/workspace`。把宿主机目录挂进去：

```yaml
    volumes:
      - dsh-data:/dsh
      - ./workspace:/workspace
```

### 手动 docker 运行（不使用 compose）

```bash
docker build -t deepseek-harness-web:local .
docker run -d --name dsh-web \
  -p 3080:3080 \
  -e DEEPSEEK_API_KEY=sk-xxx \
  -v dsh-web-data:/dsh \
  deepseek-harness-web:local
```

## 常用命令

```bash
docker compose up -d --build   # 构建并启动
docker compose logs -f dsh-web # 看日志（含启动 token URL）
docker compose restart         # 重启
docker compose down            # 停止（保留数据卷）
docker compose down -v         # 停止并删除数据卷
```

## 参考

- [deepseek-harness (GitHub)](https://github.com/deepseek-ai/deepseek-harness)
- 默认 home 目录：`~/.dsh`（容器内为 `$DSH_HOME=/dsh`），可用环境变量覆盖
- 配置层次：官方 bundle 补丁 → profile 的 `cordis.patch.yml` → **home 级 `cordis.patch.yml`** → `--patch` 覆盖
