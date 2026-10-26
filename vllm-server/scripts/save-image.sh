#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Export the built image to a compressed tarball under dist/ for transfer by
# scp/rsync/USB. Pair with scripts/load-image.sh on the target host.
#
#   scripts/save-image.sh                 dist/<image>_<tag>.tar.zst (or .tar.gz)
#   scripts/save-image.sh out.tar.gz      explicit output; compression by extension
# ---------------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_image_config

docker image inspect "$IMAGE_REF" >/dev/null 2>&1 \
  || die "image $IMAGE_REF not found locally; run scripts/build.sh first"

mkdir -p dist
base="dist/$(printf '%s' "$IMAGE_REF" | tr '/:' '__')"
out="${1:-}"
if [[ -z "$out" ]]; then
  if command -v zstd >/dev/null 2>&1; then out="$base.tar.zst"; else out="$base.tar.gz"; fi
fi

case "$out" in
  *.tar.zst)
    command -v zstd >/dev/null 2>&1 || die "zstd is not installed; use a .tar.gz output name"
    compress=(zstd -T0 -3 -q) ;;
  *.tar.gz)
    if command -v pigz >/dev/null 2>&1; then compress=(pigz -6); else compress=(gzip -6); fi ;;
  *.tar)
    compress=(cat) ;;
  *)
    die "output must end in .tar, .tar.gz or .tar.zst" ;;
esac

log "saving $IMAGE_REF -> $out"
log "(images with baked weights are 20+ GB; this takes a while)"
docker save "$IMAGE_REF" | "${compress[@]}" > "$out"
log "wrote $out ($(du -h "$out" | cut -f1))"

cat <<EOF >&2

Next, copy it to the server and load it there:
  rsync -avP $out user@server:~/
  scripts/load-image.sh ~/$(basename "$out")
EOF
