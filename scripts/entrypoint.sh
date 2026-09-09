#!/bin/sh
set -eu

# Map short .env names to what the runtime expects.
if [ -n "${BASE_URL:-}" ]; then
  export DEEPSEEK_BASE_URL="$BASE_URL"
fi

set -- dsh --profile web --no-open

if [ -n "${DSH_TRUSTED_HOST:-}" ]; then
  OLDIFS=$IFS
  IFS=','
  for host in $DSH_TRUSTED_HOST; do
    host=$(printf '%s' "$host" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$host" ]; then
      set -- "$@" --trusted-host "$host"
    fi
  done
  IFS=$OLDIFS
fi

exec "$@"
