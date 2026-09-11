#!/bin/sh
# Merge a managed custom OpenAI-compatible provider into $DSH_HOME/settings.yaml.
# Env: BASE_URL, MODEL (required when BASE_URL is set; comma-separated list),
# API_KEY (referenced as apiKeyEnv). The first model id becomes the default.
set -eu

settings="${DSH_HOME:?DSH_HOME required}/settings.yaml"
begin='# >>> dsh-web-managed'
end='# <<< dsh-web-managed'

yaml_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/''/g")"
}

strip_managed() {
  if [ ! -f "$settings" ]; then
    return 0
  fi
  awk -v b="$begin" -v e="$end" '
    $0 == b { skip=1; next }
    skip && $0 == e { skip=0; next }
    !skip { print }
  ' "$settings" > "$settings.tmp"
  mv "$settings.tmp" "$settings"
  [ -s "$settings" ] || rm -f "$settings"
}

# Remove hand-written top-level sections that dsh-web-managed owns, so the
# managed block written below is the only declaration of those keys. A second
# `llm-pi-ai` (e.g. one added through the web UI) would be a duplicate YAML
# map key and dsh rejects the whole document.
strip_keys() {
  if [ ! -f "$settings" ]; then
    return 0
  fi
  awk '
    BEGIN { skip=0 }
    {
      if (skip) {
        if ($0 ~ /^[[:space:]]/ || $0 ~ /^$/ || $0 ~ /^#/) { next }
        skip=0
      }
      if ($0 == "llm-pi-ai:" || $0 == "agent-default-model:") { skip=1; next }
      print
    }
  ' "$settings" > "$settings.tmp"
  mv "$settings.tmp" "$settings"
  [ -s "$settings" ] || rm -f "$settings"
}

if [ -z "${BASE_URL:-}" ]; then
  # No custom route: clear the managed block and any leftover llm-pi-ai /
  # agent-default-model keys so dsh falls back to its defaults cleanly.
  strip_managed
  strip_keys
  exit 0
fi

if [ -z "${MODEL:-}" ]; then
  echo "sync-provider: MODEL is required when BASE_URL is set" >&2
  exit 1
fi

if [ -z "${API_KEY:-}" ]; then
  echo "sync-provider: API_KEY is required when BASE_URL is set" >&2
  exit 1
fi

mkdir -p "$DSH_HOME"
strip_managed
strip_keys

base_q=$(yaml_quote "$BASE_URL")

# Split MODEL on commas via IFS word-splitting (sh-portable), trimming each id
# and dropping empty segments; the first non-empty id becomes the default.
models_block=
first_model=
old_ifs=$IFS
set -f
IFS=','
for id in $MODEL; do
  id=$(printf '%s' "$id" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -n "$id" ] || continue
  if [ -z "$first_model" ]; then
    first_model=$id
  fi
  models_block="${models_block}
        - id: $(yaml_quote "$id")
          # Selectable thinking strength — all seven pi-ai levels. "off" sends
          # no reasoning field and is the provider default (see reasoning: off
          # below); the rest map to OpenAI-compatible wire spellings. Declaring
          # reasoningEfforts opts this model into the selectable-thinking UI,
          # so compat.supportsReasoningEffort is set.
          reasoningEfforts:
            off: null
            minimal: minimal_effort
            low: low_effort
            medium: medium_effort
            high: high_effort
            xhigh: xhigh_effort
            max: max_effort
          compat:
            supportsReasoningEffort: true"
done
set +f
IFS=$old_ifs

if [ -z "$first_model" ]; then
  echo "sync-provider: MODEL contains no model ids" >&2
  exit 1
fi
default_q=$(yaml_quote "$first_model")

{
  if [ -f "$settings" ]; then
    cat "$settings"
    printf '\n'
  fi
  cat <<EOF
$begin
llm-pi-ai:
  providers:
    custom:
      displayName: Custom
      apiKeyEnv: API_KEY
      api: openai-completions
      baseURL: $base_q
      # Provider-wide default thinking strength for every model below (off = closed).
      reasoning: off
      # All models under this gateway declare image support. This is a claim
      # about the endpoint, not a check: a model that actually refuses images
      # will be rejected by the provider mid-turn. Narrow per-model with the
      # model's 'input' field once the true vision set is known.
      defaultInput: [text, image]
      models:$models_block
agent-default-model:
  provider: custom
  model: $default_q
$end
EOF
} > "$settings.tmp"
mv "$settings.tmp" "$settings"
