## 1. Core Implementation

- [x] 1.1 In `scripts/sync-provider.sh`, split `MODEL` into a list on commas, trimming whitespace and dropping empty segments (POSIX-sh IFS loop per design.md)
- [x] 1.2 Emit one `- id:` YAML entry per model id in the custom provider's `models` list, each through the existing `yaml_quote` helper
- [x] 1.3 Set `agent-default-model.model` to the first non-empty model id
- [x] 1.4 Keep the single-model path byte-identical to current output (no behavioral branching; route through the same emission code)

## 2. Documentation

- [x] 2.1 Update `README.md` — document comma-separated `MODEL` semantics in the env var table and Model routing section
- [x] 2.2 Update `.env.example` — note that `MODEL` accepts a comma-separated list

## 3. Verification

- [x] 3.1 Run `sync-provider.sh` with `MODEL="a"` before and after the change; diff generated `settings.yaml` for byte-identical output
- [x] 3.2 Run with `MODEL="deepseek-chat,deepseek-reasoner"`; confirm both entries in `models` and `agent-default-model.model: deepseek-chat`
- [x] 3.3 Run with `MODEL=" a ,, b "`; confirm only `a` and `b` are written
- [x] 3.4 Run with `BASE_URL` unset; confirm the managed block is still removed cleanly
