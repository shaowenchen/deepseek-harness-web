#!/bin/sh
# Persist $DSH_WORKSPACE to S3 (or S3-compatible) storage.
# Strategy: try a real s3fs mount first (fast, live filesystem). If FUSE is not
# available (Railway, macOS Docker Desktop, etc.), fall back to a Node sync daemon
# using @aws-sdk/client-s3 (boot pull + interval push/pull), which needs no /dev/fuse.
# Required: S3_BUCKET, S3_ENDPOINT, S3_ACCESS_KEY, S3_SECRET_KEY
# Optional: S3_PATH, S3_PATH_STYLE (default 1), S3_REGION, SYNC_INTERVAL (default 30)
set -eu

workspace="${DSH_WORKSPACE:-/workspace}"

if [ -z "${S3_BUCKET:-}" ]; then
  return 0 2>/dev/null || exit 0
fi

missing=
for var in S3_ENDPOINT S3_ACCESS_KEY S3_SECRET_KEY; do
  eval "val=\${$var:-}"
  if [ -z "$val" ]; then
    missing="$missing $var"
  fi
done
if [ -n "$missing" ]; then
  echo "workspace: S3_BUCKET is set; missing:$missing" >&2
  exit 1
fi

prefix="${S3_PATH:-}"
prefix="${prefix#/}"
prefix="${prefix%/}"

path_style="${S3_PATH_STYLE:-1}"

# ---------------------------------------------------------------------------
# Mode 1: s3fs mount (live filesystem). Skips gracefully when FUSE is absent.
# ---------------------------------------------------------------------------
MOUNTED=0
try_s3fs() {
  command -v s3fs >/dev/null 2>&1 || { echo "workspace: s3fs not installed, falling back to sync"; return 1; }
  [ -e /dev/fuse ] || { echo "workspace: /dev/fuse missing (no FUSE here), falling back to sync"; return 1; }

  mkdir -p "$workspace" /run/s3fs
  passwd_file=/run/s3fs/passwd
  umask 077
  printf '%s:%s\n' "$S3_ACCESS_KEY" "$S3_SECRET_KEY" > "$passwd_file"
  chmod 600 "$passwd_file"

  target="$S3_BUCKET"
  if [ -n "$prefix" ]; then
    target="${S3_BUCKET}:/${prefix}"
  fi

  opts="passwd_file=${passwd_file},allow_other,umask=0022,mp_umask=0022,listobjectsv2,complement_stat"
  opts="${opts},url=${S3_ENDPOINT}"

  case "$path_style" in
    1|true|TRUE|yes|YES|on|ON) opts="${opts},use_path_request_style" ;;
  esac

  if [ -n "${S3_REGION:-}" ]; then
    opts="${opts},endpoint=${S3_REGION}"
  fi

  echo "workspace: s3fs ${target} -> ${workspace}"
  # shellcheck disable=SC2086
  if s3fs "$target" "$workspace" -o "$opts"; then
    MOUNTED=1
    return 0
  fi
  echo "workspace: s3fs mount failed, falling back to sync" >&2
  rm -f "$passwd_file"
  return 1
}

unmount_workspace() {
  if [ "$MOUNTED" -eq 1 ] && mountpoint -q "$workspace" 2>/dev/null; then
    fusermount -u "$workspace" 2>/dev/null || umount "$workspace" 2>/dev/null || true
  fi
  rm -f /run/s3fs/passwd
}

# ---------------------------------------------------------------------------
# Mode 2: Node SDK sync daemon (no FUSE needed). Boot pull + interval push/pull.
# Uses @aws-sdk/client-s3 with the same client params that are verified to work
# against KS3 (storage-console's createS3Client), which rclone's generic driver
# fails to connect to.
# ---------------------------------------------------------------------------
start_node_sync() {
  if ! command -v node >/dev/null 2>&1; then
    echo "workspace: node not installed, giving up on S3 persistence" >&2
    return 1
  fi

  echo "workspace: starting s3-sync daemon (AWS SDK)"
  node /opt/dsh-web/s3-sync.mjs &
  SYNC_PID=$!

  stop_sync() {
    # Graceful stop: SIGTERM makes the daemon do a final upload pass.
    kill -TERM "$SYNC_PID" 2>/dev/null || true
    wait "$SYNC_PID" 2>/dev/null || true
  }
  trap stop_sync EXIT INT TERM
}

# ---------------------------------------------------------------------------
# Decide: try mount, else sync. Entrypoint runs dsh in foreground either way,
# so the final-sync/unmount EXIT trap always fires on container shutdown.
# ---------------------------------------------------------------------------
if try_s3fs; then
  trap unmount_workspace EXIT INT TERM
else
  start_node_sync
fi
