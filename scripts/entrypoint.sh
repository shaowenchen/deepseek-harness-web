#!/bin/sh
set -eu

if [ -n "${BASE_URL:-}" ]; then
  export DEEPSEEK_BASE_URL="$BASE_URL"
fi

exec dsh --profile web --no-open "$@"
