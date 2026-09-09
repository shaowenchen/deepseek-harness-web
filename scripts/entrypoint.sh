#!/bin/sh
set -eu

export DSH_AUTH_TOKEN="${DSH_AUTH_TOKEN:-${TOKEN:-dsh}}"

mkdir -p "$DSH_HOME" "$DSH_WORKSPACE"
cp /opt/dsh-web/cordis.patch.yml "$DSH_HOME/cordis.patch.yml"

# Host bind mounts start empty and hide the image /dsh. Seed the web profile
# (including dsh-auth-gate) from the image copy when missing.
if [ ! -d "$DSH_HOME/profiles/web/node_modules/dsh-auth-gate" ]; then
  mkdir -p "$DSH_HOME/profiles"
  cp -a /opt/dsh-web/home-seed/profiles/. "$DSH_HOME/profiles/"
fi

exec dsh --profile web --no-open "$@"
