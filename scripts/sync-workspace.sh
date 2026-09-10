#!/bin/sh
# Persist /root (the root user's HOME and dsh's working area) to S3 with the
# Node sync daemon.
# Uses @aws-sdk/client-s3 with the same client params that storage-console uses
# against KS3 (virtual-host style, requestChecksumCalculation WHEN_REQUIRED),
# which is verified to work where rclone's generic S3 driver fails.
# No FUSE needed — runs on Railway and other container platforms.
# Required: S3_BUCKET, S3_ENDPOINT, S3_ACCESS_KEY, S3_SECRET_KEY
# Optional: S3_PATH, S3_REGION
set -eu

workspace=/root

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
  echo "sync-workspace: S3_BUCKET is set; missing:$missing" >&2
  exit 1
fi

mkdir -p "$workspace"

if ! command -v node >/dev/null 2>&1; then
  echo "sync-workspace: node not installed, skipping S3 persistence" >&2
  return 0 2>/dev/null || exit 0
fi

echo "sync-workspace: starting s3-sync daemon"
node /opt/dsh-web/s3-sync.mjs &
SYNC_PID=$!

# Wait for the daemon's boot pull + version purge to finish (it writes
# $workspace/.dsh-sync-ready when done) so the entrypoint does not start dsh
# against a half-pulled or half-purged /root. The boot pull downloads every
# remote object, so on a large bucket it can take minutes — allow up to 5m,
# then proceed regardless so a genuinely absent/stuck bucket never blocks
# startup forever. If the daemon itself exits (e.g. S3 credentials rejected),
# stop waiting immediately.
i=0
while [ ! -f "$workspace/.dsh-sync-ready" ]; do
  if ! kill -0 "$SYNC_PID" 2>/dev/null; then
    echo "sync-workspace: s3-sync daemon exited during boot pull (continuing)" >&2
    break
  fi
  i=$((i + 1))
  if [ "$i" -ge 300 ]; then
    echo "sync-workspace: timed out after 300s waiting for s3-sync ready (continuing; boot pull may still be running)" >&2
    break
  fi
  sleep 1
done

stop_sync() {
  # Graceful stop: SIGTERM makes the daemon do a final upload pass.
  kill -TERM "$SYNC_PID" 2>/dev/null || true
  wait "$SYNC_PID" 2>/dev/null || true
}

trap stop_sync EXIT INT TERM
