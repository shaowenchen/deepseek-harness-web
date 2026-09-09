#!/bin/sh
set -eu

# Must be exported by the launching process — dsh rejects DSH_AUTH_TOKEN in .env files.
TOKEN_VALUE="${DSH_AUTH_TOKEN:-${TOKEN:-dsh-web-default-token}}"
export DSH_AUTH_TOKEN="$TOKEN_VALUE"

mkdir -p "$DSH_HOME" "$DSH_WORKSPACE"
cp /opt/dsh-web/cordis.patch.yml "$DSH_HOME/cordis.patch.yml"

# Remove any previously written bootstrap vars from $DSH_HOME/.env (legacy).
if [ -f "$DSH_HOME/.env" ]; then
  grep -v '^DSH_AUTH_TOKEN=' "$DSH_HOME/.env" > "$DSH_HOME/.env.tmp" || true
  mv "$DSH_HOME/.env.tmp" "$DSH_HOME/.env"
  if [ ! -s "$DSH_HOME/.env" ]; then
    rm -f "$DSH_HOME/.env"
  else
    chmod 600 "$DSH_HOME/.env"
  fi
fi

python3 /opt/dsh-web/sync-auth-token.py

# Host bind mounts start empty and hide the image /dsh. Seed the web profile
# (including dsh-auth-gate) from the image copy when missing.
if [ ! -d "$DSH_HOME/profiles/web/node_modules/dsh-auth-gate" ]; then
  mkdir -p "$DSH_HOME/profiles"
  cp -a /opt/dsh-web/home-seed/profiles/. "$DSH_HOME/profiles/"
fi

echo "dsh-web: login with TOKEN (${#TOKEN_VALUE} chars)" >&2
exec dsh --profile web --no-open "$@"
