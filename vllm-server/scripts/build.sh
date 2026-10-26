#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Build the image for the profile selected in .env.
#
#   scripts/build.sh                      target from BUILD_TARGET in .env
#   BUILD_TARGET=server scripts/build.sh  build without baked weights
#   scripts/build.sh --no-cache           extra args go straight to docker build
#
# Set HF_TOKEN in the environment to download gated models during the build.
# ---------------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require_image_config

case "$BUILD_TARGET" in
  server|server-with-weights) ;;
  *) die "BUILD_TARGET must be 'server' or 'server-with-weights' (got '$BUILD_TARGET')" ;;
esac

args=(
  --file Dockerfile
  --target "$BUILD_TARGET"
  --platform "$BUILD_PLATFORM"
  --build-arg "VLLM_IMAGE=$VLLM_IMAGE"
  --build-arg "VLLM_VERSION=$VLLM_VERSION"
  --build-arg "MODEL_PROFILE=$MODEL_PROFILE"
  --label "llm.build.target=$BUILD_TARGET"
  --tag "$IMAGE_REF"
)
if [[ -n "${HF_TOKEN:-}" ]]; then
  args+=( --secret "id=hf_token,env=HF_TOKEN" )
  log "HF_TOKEN is set; passing it to the build as a secret"
fi

log "building $IMAGE_REF"
log "  base:    $VLLM_IMAGE:$VLLM_VERSION ($BUILD_PLATFORM)"
log "  profile: $PROFILE_FILE"
log "  target:  $BUILD_TARGET"
DOCKER_BUILDKIT=1 docker build "${args[@]}" "$@" .

log "built $IMAGE_REF"
docker image ls "$IMAGE_REF" --format '    {{.Repository}}:{{.Tag}}  {{.Size}}  (id {{.ID}})'
cat <<EOF >&2

Next:
  docker compose up -d            run it here
  scripts/save-image.sh           export for scp to the server
  scripts/push.sh                 or push to the registry in IMAGE_NAME
EOF
