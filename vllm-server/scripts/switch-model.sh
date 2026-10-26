#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Switch the running vLLM model to another profile: updates MODEL_PROFILE in
# .env, pulls the image if missing, recreates only the vllm container and
# waits until it is healthy. Open WebUI picks up the new model automatically.
#
#   scripts/switch-model.sh                    list profiles and show the current one
#   scripts/switch-model.sh falcon-h1r-7b
#   scripts/switch-model.sh falcon-h1r-7b --no-wait
# ---------------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

target="${1:-}"
wait_healthy=1
[[ "${2:-}" == "--no-wait" ]] && wait_healthy=0

current="$(sed -n 's/^MODEL_PROFILE=//p' .env 2>/dev/null)"
if [[ -z "$target" ]]; then
  echo "current profile: ${current:-<none>}"
  echo "available:"
  for f in models/*.env; do
    n="$(basename "$f" .env)"; [[ "$n" == _* ]] && continue
    printf '  %-32s %s\n' "$n" "$(sed -n 's/^MODEL=//p' "$f")"
  done
  exit 0
fi
[[ -f "models/$target.env" && "$target" != _* ]] || die "unknown profile '$target' (run without arguments to list)"
[[ -f .env ]] || die "no .env (cp .env.example .env)"

if [[ -n "$(sed -n 's/^IMAGE_TAG=//p' .env)" ]]; then
  log "note: IMAGE_TAG is set in .env and pins the image regardless of profile; clearing it"
  sed -i 's/^IMAGE_TAG=.*/IMAGE_TAG=/' .env
fi
sed -i "s/^MODEL_PROFILE=.*/MODEL_PROFILE=$target/" .env
log "MODEL_PROFILE: ${current:-<none>} -> $target"

ref="${IMAGE_NAME}:${target}-${VLLM_VERSION}"
if ! docker image inspect "$ref" >/dev/null 2>&1; then
  log "pulling $ref"
  MODEL_PROFILE="$target" docker compose pull vllm
fi

# The container name contains the profile, so compose replaces the old one.
MODEL_PROFILE="$target" docker compose up -d --remove-orphans vllm
[[ $wait_healthy -eq 1 ]] || exit 0

name="vllm-$target"
log "waiting for $name to become healthy (first start of a profile also downloads its weights)"
for _ in $(seq 1 240); do
  state="$(docker inspect -f '{{.State.Health.Status}}' "$name" 2>/dev/null || echo missing)"
  case "$state" in
    healthy)   log "$name is healthy"; exit 0 ;;
    unhealthy) die "$name is unhealthy; see: docker compose logs vllm" ;;
    missing)   die "$name is not running; see: docker compose logs vllm" ;;
  esac
  sleep 5
done
die "timed out after 20 min; see: docker compose logs vllm"
