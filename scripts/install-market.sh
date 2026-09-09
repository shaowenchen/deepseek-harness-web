#!/bin/sh
# Install the dshmarket plugin bundle into the web profile (idempotent).
# Runs `dsh plugin --profile web add <pkg>` only when the package is not yet a
# profile dependency, so restarts don't re-run pnpm. The profile lives under
# $DSH_HOME (/root/.dsh), persisted via the ./home mount.
# Env: MARKET_PACKAGE (default dshmarket); INSTALL_MARKET (set to 0 to disable).
set -eu

[ "${INSTALL_MARKET:-1}" = "0" ] && { echo "install-market: disabled"; return 0 2>/dev/null || exit 0; }

pkg="${MARKET_PACKAGE:-dshmarket}"
profile_manifest="${DSH_HOME:?DSH_HOME required}/profiles/web/package.json"

if [ -f "$profile_manifest" ] && grep -q "\"$pkg\"" "$profile_manifest"; then
  echo "install-market: $pkg already installed"
  return 0 2>/dev/null || exit 0
fi

if ! command -v dsh >/dev/null 2>&1; then
  echo "install-market: dsh not found, skipping" >&2
  return 0 2>/dev/null || exit 0
fi

echo "install-market: installing $pkg into web profile"
dsh plugin --profile web add "$pkg" 2>&1 | sed 's/^/install-market: /'
