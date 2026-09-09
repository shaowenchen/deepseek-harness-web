#!/bin/sh
set -eu

mkdir -p "$DSH_HOME" "$DSH_WORKSPACE"
cp /opt/dsh-web/cordis.patch.yml "$DSH_HOME/cordis.patch.yml"

# Drop leftover auth-gate from older images if present.
rm -rf "$DSH_HOME/profiles/web/node_modules/dsh-auth-gate"
if [ -f "$DSH_HOME/.env" ]; then
  grep -v '^DSH_AUTH_TOKEN=' "$DSH_HOME/.env" > "$DSH_HOME/.env.tmp" || true
  mv "$DSH_HOME/.env.tmp" "$DSH_HOME/.env"
  [ -s "$DSH_HOME/.env" ] || rm -f "$DSH_HOME/.env"
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

exec "$@"
