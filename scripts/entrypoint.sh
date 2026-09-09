#!/bin/sh
set -eu

if [ -z "${TOKEN:-}" ] && [ -z "${DSH_AUTH_TOKEN:-}" ]; then
  echo "TOKEN is required" >&2
  exit 1
fi
export DSH_AUTH_TOKEN="${DSH_AUTH_TOKEN:-$TOKEN}"

# Keep deploy patch in sync (volume may be an older seed).
cp /opt/dsh-web/cordis.patch.yml "$DSH_HOME/cordis.patch.yml"

# Reinstall plugin if this volume never received it.
if [ ! -d "$DSH_HOME/profiles/web/node_modules/dsh-auth-gate" ]; then
  dsh plugin --profile web add dsh-auth-gate
fi

exec dsh --profile web --no-open "$@"
