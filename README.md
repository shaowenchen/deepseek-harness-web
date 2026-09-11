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

\* Required when `S3_BUCKET` is set.

**How sync works.** On boot the bucket is pulled into the container workspace `/root` — but only for files missing locally, so the volume-persisted copy stays authoritative (a boot pull that overwrote live session logs is what corrupted them across restarts). Afterwards the daemon watches `/root` and runs a bidirectional pass on changes — local changes upload, remote additions download, local deletions propagate back — with a final flush on graceful shutdown. No FUSE required, so it works on Railway and similar platforms.

**What is synced, what is not.** The bucket mirrors user data and durable config: the workspace (`WORKSPACE_DIR`, e.g. `default/`), files the user creates under `/root`, and chat history (`.dsh/sessions`, uploaded for backup and only pulled when missing locally — never overwritten mid-write). Everything dsh regenerates from the image is **excluded** from sync: the plugin runtime (`.dsh/profiles`), caches (`.npm`, `.cache`, `.local`, `.config`), and env/image-derived config (`settings.yaml`, `cordis.patch.yml`). Excluded objects already in the bucket are pruned by the delete phase.

## Directory layout

| Host | Container | Purpose |
|---|---|---|
| `./home` | `/root` (root user's HOME) | Workspace + dsh config (`/root/.dsh`); a single mount persists everything, and with S3 configured it syncs to the bucket |

## Upgrading dsh

`dsh` is pinned by a single `ARG DSH_VERSION` in the `Dockerfile`. To upgrade:

1. Bump `ARG DSH_VERSION` in `Dockerfile` (e.g. `0.1.2-rc.1`).
2. Push to `master`. CI runs a **browser-global scan before anything is pushed** — it installs `@deepseek-ai/dsh@<version>` and scans its browser bundles for references to the ES2024 `Iterator` global that older browsers lack (the class of bug behind the `0.1.5-alpha.2` "Can't find variable: Iterator" crash).
3. If the scan passes, the image is built and pushed. If it fails, nothing is pushed and the upgrade is blocked.

**Image-is-truth plugin runtime.** dsh's plugin runtime (`$DSH_HOME/profiles`) is rebuilt from the image on every boot — the entrypoint (non-S3) and the sync daemon after its boot pull (S3) wipe it, and dsh regenerates its plugin bundles, `cordis.patch.yml` and dynamic `#include` files from the image's npm packages. Anything installed or changed in the running container is ephemeral and gone on restart. The profile directory is excluded from S3 sync, so stale plugin state (which has caused `"service subprocess has been registered"` and missing-package crashes after upgrades) can never be pulled back. Config that must be durable comes from the environment (`settings.yaml` from `BASE_URL`/`MODEL`) or the image (`cordis.patch.yml`), not from persisted plugin state.

## Model capabilities

Custom provider models (via `BASE_URL` + `MODEL`) are generated with:

- **Thinking strength** — all seven pi-ai levels selectable in the UI (`off` / `minimal` / `low` / `medium` / `high` / `xhigh` / `max`), default `off` (thinking closed).
- **Image input** — `defaultInput: [text, image]` declares image support for every model under the gateway. This is a claim, not a check: a model whose gateway refuses images will be rejected mid-turn. To narrow per-model, declare the model's `input` field once the true vision set is known.

Image: `shaowenchen/deepseek-harness-web:latest`
