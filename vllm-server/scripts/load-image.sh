#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Import a tarball written by scripts/save-image.sh. The image keeps the
# name:tag it was saved with, so .env on this host must use the same
# IMAGE_NAME / IMAGE_TAG (or leave IMAGE_TAG empty with the same profile+version).
#
#   scripts/load-image.sh ~/local_vllm-models_falcon-7b-instruct-v0.32.0.tar.zst
# ---------------------------------------------------------------------------
set -euo pipefail

file="${1:?usage: $0 <image.tar | image.tar.gz | image.tar.zst>}"
[[ -f "$file" ]] || { echo "error: not found: $file" >&2; exit 1; }

case "$file" in
  *.tar.zst)
    command -v zstd >/dev/null 2>&1 || { echo "error: zstd is not installed (apt-get install zstd)" >&2; exit 1; }
    zstd -dc "$file" | docker load ;;
  *.tar.gz)
    gzip -dc "$file" | docker load ;;
  *.tar)
    docker load -i "$file" ;;
  *)
    echo "error: unknown extension: $file" >&2; exit 1 ;;
esac

cat <<'EOF' >&2

Loaded. Check that .env points at the same name:tag, then start it:
  docker image ls
  docker compose up -d && docker compose logs -f
EOF
