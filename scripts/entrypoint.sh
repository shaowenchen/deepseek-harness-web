#!/bin/sh
set -eu

# Default must be long enough / stable for dsh-auth-gate credentials resolve.
TOKEN_VALUE="${DSH_AUTH_TOKEN:-${TOKEN:-dsh-web-default-token}}"
export DSH_AUTH_TOKEN="$TOKEN_VALUE"

mkdir -p "$DSH_HOME" "$DSH_WORKSPACE"
cp /opt/dsh-web/cordis.patch.yml "$DSH_HOME/cordis.patch.yml"

# Keep TOKEN in $DSH_HOME/.env (credentials user-env layer).
if [ -f "$DSH_HOME/.env" ]; then
  grep -v '^DSH_AUTH_TOKEN=' "$DSH_HOME/.env" > "$DSH_HOME/.env.tmp" || true
  mv "$DSH_HOME/.env.tmp" "$DSH_HOME/.env"
fi
printf 'DSH_AUTH_TOKEN=%s\n' "$TOKEN_VALUE" >> "$DSH_HOME/.env"
chmod 600 "$DSH_HOME/.env"

python3 /opt/dsh-web/sync-auth-token.py

# Host bind mounts start empty and hide the image /dsh. Seed the web profile
# (including dsh-auth-gate) from the image copy when missing.
if [ ! -d "$DSH_HOME/profiles/web/node_modules/dsh-auth-gate" ]; then
  mkdir -p "$DSH_HOME/profiles"
  cp -a /opt/dsh-web/home-seed/profiles/. "$DSH_HOME/profiles/"
fi

echo "dsh-web: login with TOKEN (${#TOKEN_VALUE} chars)" >&2
exec dsh --profile web --no-open "$@"
