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

# Restart dsh in a loop so plugin installs (which exit dsh) do not tear down
# the container. PID 1 stays alive; SIGTERM/SIGINT forwards to the running dsh,
# then the loop exits cleanly (S3 final sync runs on EXIT).
stopping=0
dsh_pid=0
stop_now() {
  stopping=1
  # Forward the stop signal to the running dsh so it can shut down cleanly.
  [ "$dsh_pid" -ne 0 ] && kill -TERM "$dsh_pid" 2>/dev/null || true
}

if [ -n "${S3_BUCKET:-}" ]; then
  trap stop_now TERM INT
  while [ "$stopping" -eq 0 ]; do
    "$@" &
    dsh_pid=$!
    wait "$dsh_pid"
    code=$?
    dsh_pid=0
    [ "$stopping" -eq 1 ] && break
    echo "dsh exited (code $code); restarting in 2s..."
    sleep 2
  done
  exit $code
fi

# No S3: still keep PID 1 alive across dsh restarts.
trap stop_now TERM INT
while [ "$stopping" -eq 0 ]; do
  "$@" &
  dsh_pid=$!
  wait "$dsh_pid"
  code=$?
  dsh_pid=0
  [ "$stopping" -eq 1 ] && break
  echo "dsh exited (code $code); restarting in 2s..."
  sleep 2
done
exit $code
