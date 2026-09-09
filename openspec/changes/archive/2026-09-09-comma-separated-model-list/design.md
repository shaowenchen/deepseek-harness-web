## Context

`scripts/sync-provider.sh` is a POSIX `/bin/sh` script that runs once per container boot (see `scripts/entrypoint.sh`). It currently treats `MODEL` as a single model id and emits exactly one `- id:` entry plus an `agent-default-model`. See proposal.md for motivation and specs/model-routing/spec.md for the required behavior.

## Goals / Non-Goals

- **Goals**: Comma-separated `MODEL` support with byte-identical single-model output; zero changes to the Docker image, compose file, or S3 sync.
- **Non-Goals**: No new env vars (no `DEFAULT_MODEL`, no `PROVIDER_ID` — out of scope per the exploration); no support for escaping commas inside a model id.

## Decisions

**1. Split and trim with an IFS loop, not sed/awk.**
The script must stay POSIX-sh portable (the container runs `sh`, not bash). With `IFS=,` set, a `for id in $MODEL` word-splitting loop yields one field per comma segment — a single-variable `read` cannot split fields, and a `while read` pipeline would lose state to a subshell. Each id is whitespace-trimmed and empty segments are skipped; `set -f` guards model ids against glob expansion. Trimming uses the existing `sed` idiom already in the file.

**2. Default model = first non-empty id.**
When the list is `a,b,c`, `agent-default-model.model` is `a`. Chosen over "last id" or a dedicated `DEFAULT_MODEL` var because it keeps the env surface unchanged — the user's earlier decision was deliberately minimal ("只加多模型, 默认取第一个").

**3. Backward compatibility is a hard requirement, verified by diff.**
Single `MODEL="a"` must produce output identical to the current script. The implementation routes both cases through the same emission code, so the single-model path isn't a special case that can drift. Verification: run the script with a single model before and after, diff the generated `settings.yaml`.

**4. Each model id goes through the existing `yaml_quote`.**
The existing helper (single-quote + `''` escaping) is reused per id, preserving the current quoting behavior exactly.

## Risks / Trade-offs

- Model ids containing literal commas are unsupported → mitigation: accepted limitation; no realistic model id contains a comma. Note in README.
- Splitting on `,` inside the managed block could collide with a comma-bearing YAML value in user settings → mitigation: only `MODEL` is split; the managed block rewrite is unchanged.

## Migration Plan

Deploy by rebuilding the image (`docker compose up -d --build`). Rollback is reverting the commit and rebuilding — no data migration or state to preserve; `settings.yaml` is regenerated on boot either way.

## Open Questions

None.
