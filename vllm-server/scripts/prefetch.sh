#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Pull the images and download the weights of several profiles ahead of time,
# so switching models later (scripts/switch-model.sh) only restarts vLLM.
# Run on the GPU server. Weights land in the shared hf-cache volume; images
# share the vLLM base layers, so each extra profile costs only its weights.
#
#   scripts/prefetch.sh                         every profile in models/
#   scripts/prefetch.sh falcon-h1r-7b falcon-11b-vlm
#   scripts/prefetch.sh --images-only all       pull images, skip weights
#   DRY_RUN=1 scripts/prefetch.sh ...           print what would run
# ---------------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

images_only=0
profiles=()
for a in "$@"; do
  case "$a" in
    --images-only) images_only=1 ;;
    all) profiles=() ; all=1 ;;
    -h|--help) sed -n '2,13p' "$0"; exit 0 ;;
    *) profiles+=("$a") ;;
  esac
done
if [[ ${#profiles[@]} -eq 0 || -n "${all:-}" ]]; then
  profiles=()
  for f in models/*.env; do
    n="$(basename "$f" .env)"; [[ "$n" == _* ]] || profiles+=("$n")
  done
fi
for p in "${profiles[@]}"; do
  [[ -f "models/$p.env" && "$p" != _* ]] || die "unknown profile '$p'"
done

run() { if [[ -n "${DRY_RUN:-}" ]]; then printf '  + %s\n' "$*"; else "$@"; fi; }

failed=()
for p in "${profiles[@]}"; do
  ref="${IMAGE_NAME}:${p}-${VLLM_VERSION}"
  log "[$p] pulling $ref"
  # IMAGE_TAG is cleared so compose derives the tag from the profile.
  if ! run env MODEL_PROFILE="$p" IMAGE_TAG= docker compose pull --quiet vllm; then
    failed+=("$p (pull)"); continue
  fi
  [[ $images_only -eq 1 ]] && continue
  if [[ -z "${DRY_RUN:-}" ]] && [[ "$(docker image inspect "$ref" --format '{{index .Config.Labels "llm.weights.baked"}}' 2>/dev/null)" == "true" ]]; then
    log "[$p] weights are baked into the image; nothing to download"
    continue
  fi
  model="$(sed -n "s/^MODEL=//p" "models/$p.env")"
  log "[$p] downloading weights of $model into the hf-cache volume"
  if ! run env MODEL_PROFILE="$p" IMAGE_TAG= docker compose run --rm --no-deps vllm download; then
    failed+=("$p (download)")
  fi
done

echo
if [[ -z "${DRY_RUN:-}" ]]; then
  docker system df --format 'table {{.Type}}\t{{.Size}}\t{{.Reclaimable}}' 2>/dev/null | sed -n '1,3p'
  vol="$(docker volume ls -q --filter name=hf-cache | head -n1)"
  [[ -n "$vol" ]] && docker run --rm -v "$vol:/c:ro" ubuntu:24.04 du -sh /c 2>/dev/null | sed "s#/c#hf-cache volume ($vol)#"
fi
if [[ ${#failed[@]} -gt 0 ]]; then
  die "failed: ${failed[*]}"
fi
log "done: ${profiles[*]}"
log "switch with: scripts/switch-model.sh <profile>"
