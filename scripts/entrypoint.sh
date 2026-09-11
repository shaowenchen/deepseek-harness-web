#!/bin/sh
set -eu

# Owner-only umask so dsh-created secrets (.credentials.yaml etc.) are 0600,
# which dsh-credentials-local enforces on load.
umask 077

mkdir -p "$DSH_HOME" /root
cp /opt/dsh-web/cordis.patch.yml "$DSH_HOME/cordis.patch.yml"

# Harden any existing sensitive files (dsh refuses 0644 credentials).
chmod 600 "$DSH_HOME/.credentials.yaml" "$DSH_HOME/.env" 2>/dev/null || true

# Version-aware purge of the persisted plugin directory (non-S3 mode only).
# $DSH_HOME/profiles is kept on disk (bind mount) across dsh upgrades; plugins
# a previous dsh version installed there can then leak into the new one and
# crash it (e.g. the 0.1.5-alpha.2 documentpreview loader failing with "Can't
# find variable: Iterator"). When the recorded version differs from the image's
# DSH_VERSION, wipe the profile's node_modules so dsh rebuilds its plugin set
# from the current image. Same-version boots keep the directory untouched.
# When S3 is configured, the sync daemon owns /root and applies the same purge
# AFTER its boot pull (s3-sync.mjs), so skip it here to avoid pulling stale
# state back down only to purge it again.
if [ -z "${S3_BUCKET:-}" ] && [ -n "${DSH_VERSION:-}" ]; then
  prev=$(cat "$DSH_HOME/.dsh-web-version" 2>/dev/null || true)
  if [ "$prev" != "$DSH_VERSION" ]; then
    if [ -n "$prev" ]; then
      echo "entrypoint: dsh version changed ($prev -> $DSH_VERSION); purging persisted web plugins"
    fi
    rm -rf "$DSH_HOME/profiles/web/node_modules"
    printf '%s\n' "$DSH_VERSION" > "$DSH_HOME/.dsh-web-version"
  fi
fi

# Official DeepSeek route: only when not using a custom BASE_URL.
if [ -z "${BASE_URL:-}" ] && [ -n "${API_KEY:-}" ] && [ -z "${DEEPSEEK_API_KEY:-}" ]; then
  export DEEPSEEK_API_KEY="$API_KEY"
fi

# Optional: persist /root (workspace) to S3 via Node SDK sync (sets EXIT trap;
# do not exec before dsh). Boot-pulled files must win over nothing: this starts
# the sync daemon and its boot pull, then the managed provider config is written
# below so a stale bucket copy of settings.yaml cannot clobber env-driven models.
# shellcheck source=/dev/null
. /opt/dsh-web/sync-workspace.sh

# Custom OpenAI-compatible provider (BASE_URL + MODEL), or clear managed block.
# Runs after the S3 boot pull so the env-generated settings.yaml is never
# overwritten by an older copy of the file stored in the bucket.
/opt/dsh-web/sync-provider.sh

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

# Preserve Docker CMD args (e.g. --port 3080). Stash each original argv entry
# on its own line so they can be re-appended without eval — arg values (spaces,
# quotes, metacharacters) are never re-parsed.
cmd_args_tmp=$(mktemp)
printf '%s\n' "$@" > "$cmd_args_tmp"

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

# Append the original CMD args, one line at a time, values untouched.
while IFS= read -r arg; do
  set -- "$@" "$arg"
done < "$cmd_args_tmp"
rm -f "$cmd_args_tmp"

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
    if wait "$dsh_pid"; then
      code=0
    else
      code=$?
    fi
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
  if wait "$dsh_pid"; then
    code=0
  else
    code=$?
  fi
  dsh_pid=0
  [ "$stopping" -eq 1 ] && break
  echo "dsh exited (code $code); restarting in 2s..."
  sleep 2
done
exit $code
