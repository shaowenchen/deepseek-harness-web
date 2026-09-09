#!/bin/sh
# Mount S3 (or S3-compatible) storage onto $DSH_WORKSPACE with s3fs when S3_BUCKET is set.
# Required: S3_BUCKET, S3_ENDPOINT, S3_ACCESS_KEY, S3_SECRET_KEY
# Optional: S3_PATH (bucket subpath), S3_PATH_STYLE (default 1), S3_REGION
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
  echo "mount-workspace: S3_BUCKET is set; missing:$missing" >&2
  exit 1
fi

if ! command -v s3fs >/dev/null 2>&1; then
  echo "mount-workspace: s3fs is not installed" >&2
  exit 1
fi

if [ ! -e /dev/fuse ]; then
  echo "mount-workspace: /dev/fuse missing; add devices: [/dev/fuse] and cap_add: [SYS_ADMIN]" >&2
  exit 1
fi

mkdir -p "$workspace" /run/s3fs
passwd_file=/run/s3fs/passwd
umask 077
printf '%s:%s\n' "$S3_ACCESS_KEY" "$S3_SECRET_KEY" > "$passwd_file"
chmod 600 "$passwd_file"

prefix="${S3_PATH:-}"
prefix="${prefix#/}"
prefix="${prefix%/}"
target="$S3_BUCKET"
if [ -n "$prefix" ]; then
  target="${S3_BUCKET}:/${prefix}"
fi

# Cover any existing bind mount under the workspace path.
if mountpoint -q "$workspace" 2>/dev/null; then
  # Already an s3fs mount from a previous attempt in this namespace — remount cleanly.
  case "$(findmnt -n -o FSTYPE "$workspace" 2>/dev/null || true)" in
    fuse.s3fs|fuse)
      fusermount -u "$workspace" 2>/dev/null || umount "$workspace" 2>/dev/null || true
      ;;
  esac
fi

opts="passwd_file=${passwd_file},allow_other,umask=0022,mp_umask=0022,listobjectsv2,complement_stat"
opts="${opts},url=${S3_ENDPOINT}"

path_style="${S3_PATH_STYLE:-1}"
case "$path_style" in
  1|true|TRUE|yes|YES|on|ON)
    opts="${opts},use_path_request_style"
    ;;
esac

if [ -n "${S3_REGION:-}" ]; then
  opts="${opts},endpoint=${S3_REGION}"
fi

echo "mount-workspace: s3fs ${target} -> ${workspace}"
# shellcheck disable=SC2086
s3fs "$target" "$workspace" -o "$opts"

# Ensure credentials file is not world-readable; keep it for the mount lifetime.
chmod 600 "$passwd_file"

unmount_workspace() {
  if mountpoint -q "$workspace" 2>/dev/null; then
    fusermount -u "$workspace" 2>/dev/null || umount "$workspace" 2>/dev/null || true
  fi
  rm -f "$passwd_file"
}

trap unmount_workspace EXIT INT TERM
