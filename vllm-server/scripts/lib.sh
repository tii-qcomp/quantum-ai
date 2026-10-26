# shellcheck shell=bash
# ---------------------------------------------------------------------------
# Shared helpers for scripts/*.sh. Source it, do not run it.
# Loads .env (shell environment takes precedence) and derives IMAGE_REF.
# ---------------------------------------------------------------------------
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*" >&2; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Export KEY=VALUE pairs from a file for variables that are unset or empty.
load_env_file() {
  local file=$1 line key value
  [[ -f "$file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    [[ -z "$line" || "$line" == \#* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue
    case "$value" in
      \"*\") value="${value#\"}"; value="${value%\"}" ;;
      \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    if [[ -z "${!key:-}" ]]; then
      export "$key=$value"
    fi
  done < "$file"
}

load_env_file .env

# Fill in defaults that do not need .env
VLLM_IMAGE="${VLLM_IMAGE:-vllm/vllm-openai}"
VLLM_VERSION="${VLLM_VERSION:-v0.32.0}"
BUILD_TARGET="${BUILD_TARGET:-server-with-weights}"
BUILD_PLATFORM="${BUILD_PLATFORM:-linux/amd64}"
HOST_PORT="${HOST_PORT:-8000}"
export VLLM_IMAGE VLLM_VERSION BUILD_TARGET BUILD_PLATFORM HOST_PORT

# Call this from scripts that need a fully specified image (build, push, save).
require_image_config() {
  [[ -f .env ]] || die "no .env in $ROOT_DIR (cp .env.example .env)"
  [[ -n "${MODEL_PROFILE:-}" ]] || die "MODEL_PROFILE is not set in .env"
  [[ -n "${IMAGE_NAME:-}" ]] || die "IMAGE_NAME is not set in .env"
  PROFILE_FILE="models/${MODEL_PROFILE}.env"
  [[ -f "$PROFILE_FILE" ]] || die "profile not found: $PROFILE_FILE (available: $(ls models/*.env | xargs -n1 basename | grep -v '^_' | sed 's/\.env$//' | paste -sd ' ' -))"
  IMAGE_TAG="${IMAGE_TAG:-${MODEL_PROFILE}-${VLLM_VERSION}}"
  IMAGE_REF="${IMAGE_NAME}:${IMAGE_TAG}"
  export MODEL_PROFILE IMAGE_NAME IMAGE_TAG IMAGE_REF PROFILE_FILE
}
