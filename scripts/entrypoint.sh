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

exec dsh --profile web --no-open "$@"
