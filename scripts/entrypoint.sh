#!/bin/sh
set -eu

mkdir -p "$DSH_HOME" /root
cp /opt/dsh-web/cordis.patch.yml "$DSH_HOME/cordis.patch.yml"

# Drop leftover auth-gate from older images if present.
rm -rf "$DSH_HOME/profiles/web/node_modules/dsh-auth-gate"
if [ -f "$DSH_HOME/.env" ]; then
  grep -v '^DSH_AUTH_TOKEN=' "$DSH_HOME/.env" > "$DSH_HOME/.env.tmp" || true
  mv "$DSH_HOME/.env.tmp" "$DSH_HOME/.env"
  [ -s "$DSH_HOME/.env" ] || rm -f "$DSH_HOME/.env"
fi

# Custom OpenAI-compatible provider (BASE_URL + MODEL), or clear managed block.
/opt/dsh-web/sync-provider.sh

# Install the dshmarket plugin bundle into the web profile (idempotent).
# shellcheck source=/dev/null
. /opt/dsh-web/install-market.sh

# Official DeepSeek route: only when not using a custom BASE_URL.
if [ -z "${BASE_URL:-}" ] && [ -n "${API_KEY:-}" ] && [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  export DEEPSEEK_API_KEY="$API_KEY"
fi

# Optional: persist /root (workspace) to S3 via Node SDK sync (sets EXIT trap;
# do not exec before dsh).
# shellcheck source=/dev/null
. /opt/dsh-web/sync-workspace.sh

# Seed a default workspace directory so the first-run directory picker in the
# web UI has a ready option. Skipped when S3 is configured (the sync daemon
# owns /root). Override the name with WORKSPACE_DIR.
if [ -z "${S3_BUCKET:-}" ]; then
  default_ws="${WORKSPACE_DIR:-default}"
  case "$default_ws" in
    /?*) ws_path="$default_ws" ;;
    *)   ws_path="/root/$default_ws" ;;
  esac
  mkdir -p "$ws_path"
fi

# Preserve Docker CMD args (e.g. --port 3080).
n=$#
i=1
while [ "$i" -le "$n" ]; do
  eval "CMD_$i=\$$i"
  i=$((i + 1))
done

set -- dsh --profile web --no-open

# Domain access: browser Host must be trusted (comma-separated host or host:port).
if [ -n "${TRUSTED_HOST:-}" ]; then
  OLDIFS=$IFS
  IFS=','
  for host in $TRUSTED_HOST; do
    host=$(printf '%s' "$host" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [ -n "$host" ]; then
      set -- "$@" --trusted-host "$host"
    fi
  done
  IFS=$OLDIFS
fi

i=1
while [ "$i" -le "$n" ]; do
  eval "set -- \"\$@\" \"\$CMD_$i\""
  i=$((i + 1))
done

# Use plain exec when no S3 sync; otherwise run in foreground so the EXIT trap
# fires and the sync daemon does its final upload pass.
if [ -n "${S3_BUCKET:-}" ]; then
  "$@"
  exit $?
fi

exec "$@"
