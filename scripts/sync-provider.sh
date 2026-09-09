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

if [ -z "${BASE_URL:-}" ]; then
  strip_managed
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
        - id: $(yaml_quote "$id")"
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
      models:$models_block
agent-default-model:
  provider: custom
  model: $default_q
$end
EOF
} > "$settings.tmp"
mv "$settings.tmp" "$settings"
