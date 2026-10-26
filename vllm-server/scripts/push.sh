#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Push the built image to the registry named in IMAGE_NAME.
# Log in first, e.g.:  docker login ghcr.io -u <user>
# On the server:       docker compose pull && docker compose up -d
# ---------------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_image_config

[[ "$IMAGE_NAME" == */* && "$IMAGE_NAME" != local/* ]] \
  || die "IMAGE_NAME '$IMAGE_NAME' is not a registry path; set e.g. ghcr.io/<user>/vllm-models in .env"

docker image inspect "$IMAGE_REF" >/dev/null 2>&1 \
  || die "image $IMAGE_REF not found locally; run scripts/build.sh first"

log "pushing $IMAGE_REF"
docker push "$IMAGE_REF"
