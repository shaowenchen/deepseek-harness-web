## Why

The deployment routes to a custom OpenAI-compatible gateway through a single `MODEL` env var, which writes exactly one model id into the provider's `models` list. Gateways that expose several model ids (routers, multi-model proxies) can only use one of them — the rest require hand-editing `~/.dsh/settings.yaml` inside the container, which is lost on every managed-block rewrite. Supporting a comma-separated list removes that friction for a very common setup.

## What Changes

- `MODEL` now accepts a comma-separated list of model ids, e.g. `MODEL="deepseek-chat,deepseek-reasoner"`.
- `scripts/sync-provider.sh` writes every model id as a separate entry under the custom provider's `models` list.
- The first model id in the list becomes the default model (`agent-default-model`).
- Empty entries and surrounding whitespace are tolerated (`MODEL="a,, b"` → models `a`, `b`).
- Single-model behavior is unchanged: `MODEL="a"` produces byte-identical output to today.

## Capabilities

### New Capabilities
- `model-routing`: translation of the deployment's env vars (`BASE_URL`, `MODEL`, `API_KEY`) into the dsh `settings.yaml` custom provider block and default-model selection, applied idempotently on container boot.

### Modified Capabilities
<!-- No existing specs in openspec/specs/; this is the first capability for this project. -->

## Impact

- `scripts/sync-provider.sh` — the only code change; splitting and YAML emission logic.
- `README.md` and `.env.example` — document the comma-separated `MODEL` semantics.
- No changes to `docker-compose.yml`, the Docker image, or S3 sync.
- Verification: boot the container with `MODEL="a,b,c"`, confirm `settings.yaml` lists all three with `agent-default-model.model = a`, and confirm single-model output is unchanged.
