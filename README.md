# DeepSeek Harness Web

**Run DeepSeek Harness — DeepSeek's open-source AI coding agent — as a self-hosted web application in a single container.**

One image, one command, and you get a full harness workspace with a web UI, secure model routing, and durable storage that survives even the most ephemeral of platforms.

## Why this exists

DeepSeek Harness is a powerful agentic coding tool, but running its web interface comfortably means dealing with a persistent workspace, model credentials, and a UI that has to survive restarts. This project packages all of that into a single, self-contained container:

- **Works out of the box** — official DeepSeek routing from a single `API_KEY`.
- **Bring any model** — point `BASE_URL` and `MODEL` at any OpenAI-compatible gateway and it automatically becomes the default model.
- **Persistent anywhere** — a zero-FUSE, bidirectional S3 sync keeps your workspace intact on platforms with ephemeral filesystems (Railway and the like). Verified against Kingsoft Cloud KS3.
- **Self-healing** — the entrypoint keeps the harness alive across plugin-driven restarts, so a plugin install no longer takes the container down with it.
- **Secure by default** — credentials live only in environment variables, cache directories are kept out of the bucket, and sensitive files are created with owner-only permissions.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     dsh-web container                       │
│                                                             │
│  entrypoint.sh  ──  PID 1, auto-restart loop                │
│    ├─ sync-provider.sh   model routing → settings.yaml      │
│    ├─ sync-workspace.sh  boot pull + graceful exit flush    │
│    ├─ s3-sync.mjs        live bidirectional sync daemon     │
│    └─ dsh web            DeepSeek Harness web UI            │
│                                                             │
│  /root  ⇄  ./home (bind mount)   ⇄   S3 bucket (optional)   │
└─────────────────────────────────────────────────────────────┘
```

## Quick start

```bash
cp .env.example .env
# edit .env, set API_KEY
mkdir -p home
docker compose up -d --build
docker compose logs -f dsh-web
```

## Access

1. Copy the URL from the startup logs (it includes the token):
   ```
   dsh web: http://127.0.0.1:3080/?token=xxxx
   ```
2. Replace the address with your host or domain:port, e.g. `https://chat.example.com:8443/?token=xxxx`.
3. For domain access, set `TRUSTED_HOST` in `.env` to match the browser's Host header (may include a port).

## Configuration

### Core

| Variable | Required | Default | Description |
|---|---|---|---|
| `API_KEY` | yes | — | Model API key |
| `BASE_URL` | no | empty | Custom OpenAI-compatible gateway (when set, `MODEL` is required) |
| `MODEL` | conditional | empty | Custom model id(s) — comma-separated list; the first id is the default |
| `PORT` | no | `3080` | Host port mapping |
| `TRUSTED_HOST` | on domain | empty | Trusted Host, may include a port |
| `WORKSPACE_DIR` | no | `default` | Default workspace directory pre-created under `/root` on first boot |
| `LOG_LEVEL` | no | empty | `debug` prints per-file sync details |

### Model routing

- No `BASE_URL` → official DeepSeek (`API_KEY` is the DeepSeek key).
- `BASE_URL` + `MODEL` set → a custom route is written into `/root/.dsh/settings.yaml`. `MODEL` accepts a comma-separated list (e.g. `deepseek-chat,deepseek-reasoner`); every id is registered under the custom provider and the first one becomes the default model.

### S3 persistence (optional)

| Variable | Required | Default | Description |
|---|---|---|---|
| `S3_BUCKET` | yes* | empty | Bucket name; enables sync when set |
| `S3_PATH` | no | empty | Sub-path prefix inside the bucket |
| `S3_ENDPOINT` | yes* | empty | e.g. `https://ks3-cn-beijing.ksyuncs.com` |
| `S3_ACCESS_KEY` | yes* | empty | Access key |
| `S3_SECRET_KEY` | yes* | empty | Secret key |
| `S3_REGION` | no | empty | e.g. `cn-beijing` |
| `S3_PATH_STYLE` | no | `0` | `0` virtual-host style (AWS/Kingsoft); `1` path-style (MinIO/self-hosted) |
| `SYNC_EXCLUDE` | no | `.npm,.cache,.local,.config` | Top-level HOME directories excluded from sync (comma-separated) |

\* Required when `S3_BUCKET` is set.

**How sync works.** On boot the bucket is pulled into the container workspace `/root`; afterwards the daemon watches `/root` and runs a bidirectional pass on changes — local changes upload, remote additions download, local deletions propagate back — with a final flush on graceful shutdown. No FUSE required, so it works on Railway and similar platforms.

## Directory layout

| Host | Container | Purpose |
|---|---|---|
| `./home` | `/root` (root user's HOME) | Workspace + dsh config (`/root/.dsh`); a single mount persists everything, and with S3 configured it syncs to the bucket |

Image: `shaowenchen/deepseek-harness-web:latest`
