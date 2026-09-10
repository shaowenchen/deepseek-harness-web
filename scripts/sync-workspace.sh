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
# $workspace/.dsh-sync-ready when done) so dsh only starts against a fully
# pulled, fully purged /root. No fixed timeout: if the daemon exits (e.g. S3
# credentials rejected, endpoint unreachable) we stop waiting immediately, and
# a slow but healthy boot pull simply takes as long as it takes. A heartbeat
# line every 30s keeps the wait visible in logs.
i=0
while [ ! -f "$workspace/.dsh-sync-ready" ]; do
  if ! kill -0 "$SYNC_PID" 2>/dev/null; then
    echo "sync-workspace: s3-sync daemon exited during boot pull (continuing without it)" >&2
    break
  fi
  i=$((i + 1))
  if [ $((i % 30)) -eq 0 ]; then
    echo "sync-workspace: still waiting for s3-sync boot pull (${i}s)..."
  fi
  sleep 1
done

stop_sync() {
  # Graceful stop: SIGTERM makes the daemon do a final upload pass.
  kill -TERM "$SYNC_PID" 2>/dev/null || true
  wait "$SYNC_PID" 2>/dev/null || true
}

trap stop_sync EXIT INT TERM
