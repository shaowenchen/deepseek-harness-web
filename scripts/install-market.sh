#!/bin/sh
# Install plugin bundles into the web profile (idempotent).
# Runs `dsh plugin --profile web add <pkg>` only when a package is not yet a
# profile dependency, so restarts don't re-run pnpm. The profile lives under
# $DSH_HOME (/root/.dsh), persisted via the ./home mount.
# Env: MARKET_PACKAGES (comma-separated, default dshmarket,dsh-file-explorer);
#      INSTALL_MARKET (set to 0 to disable).
set -eu
set -o pipefail 2>/dev/null || true

[ "${INSTALL_MARKET:-1}" = "0" ] && { echo "install-market: disabled"; return 0 2>/dev/null || exit 0; }

pkgs="${MARKET_PACKAGES:-dshmarket,dsh-file-explorer}"
profile_manifest="${DSH_HOME:?DSH_HOME required}/profiles/web/package.json"

if ! command -v dsh >/dev/null 2>&1; then
  echo "install-market: dsh not found, skipping" >&2
  return 0 2>/dev/null || exit 0
fi

OLDIFS=$IFS
IFS=','
for pkg in $pkgs; do
  pkg=$(printf '%s' "$pkg" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [ -z "$pkg" ] && continue
  if [ -f "$profile_manifest" ] && grep -q "\"$pkg\"" "$profile_manifest"; then
    echo "install-market: $pkg already installed"
    continue
  fi
  echo "install-market: installing $pkg into web profile"
  if ! dsh plugin --profile web add "$pkg" 2>&1 | sed 's/^/install-market: /'; then
    echo "install-market: FAILED to install $pkg" >&2
  fi
done
IFS=$OLDIFS
