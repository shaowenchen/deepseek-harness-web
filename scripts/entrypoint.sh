#!/bin/sh
set -eu

# Resolve DEEPSEEK_API_KEY from a mounted secret file when the env var is empty.
if [ -z "${DEEPSEEK_API_KEY:-}" ] && [ -n "${DEEPSEEK_API_KEY_FILE:-}" ] && [ -f "$DEEPSEEK_API_KEY_FILE" ]; then
  DEEPSEEK_API_KEY="$(tr -d '\r\n' < "$DEEPSEEK_API_KEY_FILE")"
  export DEEPSEEK_API_KEY
fi

# Accept DSH_TRUSTED_HOST (documented) or DSH_TRUSTED_HOSTS (comma-separated list).
TRUSTED_HOSTS="${DSH_TRUSTED_HOSTS:-${DSH_TRUSTED_HOST:-}}"

set -- dsh --profile web --no-open

if [ -n "$TRUSTED_HOSTS" ]; then
  OLDIFS=$IFS
  IFS=','
  for host in $TRUSTED_HOSTS; do
    host=$(printf '%s' "$host" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$host" ]; then
      set -- "$@" --trusted-host "$host"
    fi
  done
  IFS=$OLDIFS
fi

python3 /opt/dsh-web/sync-llm-settings.py

exec "$@"
