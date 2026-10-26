#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Verify that this host can run the image: Docker + Compose, NVIDIA driver,
# NVIDIA Container Toolkit, and GPU visibility from inside a container.
# Run on the GPU server before the first `docker compose up`.
# ---------------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
set +e

status=0
ok()   { printf '  \033[1;32m[ok]\033[0m   %s\n' "$*"; }
bad()  { printf '  \033[1;31m[FAIL]\033[0m %s\n' "$*"; status=1; }
info() { printf '         %s\n' "$*"; }

echo "Docker"
if command -v docker >/dev/null 2>&1; then
  ok "$(docker --version)"
else
  bad "docker not found. Install: https://docs.docker.com/engine/install/ubuntu/"
fi
if docker compose version >/dev/null 2>&1; then
  ok "$(docker compose version)"
else
  bad "docker compose plugin not found (apt-get install docker-compose-plugin)"
fi
if docker info >/dev/null 2>&1; then
  ok "docker daemon reachable as $(id -un)"
else
  bad "cannot talk to the docker daemon (is $(id -un) in the docker group? sudo usermod -aG docker \$USER, then re-login)"
fi

echo "NVIDIA driver"
if command -v nvidia-smi >/dev/null 2>&1; then
  ok "$(nvidia-smi --query-gpu=name,driver_version,memory.total --format=csv,noheader | paste -sd ';' -)"
else
  bad "nvidia-smi not found; install the NVIDIA driver first"
fi

echo "NVIDIA Container Toolkit"
if docker info 2>/dev/null | grep -qi 'Runtimes:.*nvidia'; then
  ok "nvidia runtime registered with Docker"
else
  bad "nvidia runtime not registered. See README: Server prerequisites"
fi

echo "GPU visible inside a container"
img="ubuntu:24.04"
if [[ -n "${MODEL_PROFILE:-}" && -n "${IMAGE_NAME:-}" ]]; then
  candidate="${IMAGE_NAME}:${IMAGE_TAG:-${MODEL_PROFILE}-${VLLM_VERSION}}"
  docker image inspect "$candidate" >/dev/null 2>&1 && img="$candidate"
fi
if out="$(docker run --rm --gpus all "$img" nvidia-smi -L 2>&1)"; then
  ok "docker run --gpus all works (tested with $img)"
  while IFS= read -r line; do info "$line"; done <<<"$out"
else
  bad "docker run --gpus all failed (tested with $img):"
  while IFS= read -r line; do info "$line"; done <<<"$out"
fi

echo
if [[ $status -eq 0 ]]; then
  printf '\033[1;32mHost looks ready.\033[0m\n'
else
  printf '\033[1;31mFix the items marked FAIL, then re-run.\033[0m\n'
fi
exit $status
