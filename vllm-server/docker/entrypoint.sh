#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Container entrypoint for the vLLM OpenAI-compatible server.
#
#   entrypoint.sh [serve] [extra vllm args]   start the server (default)
#   entrypoint.sh --some-vllm-flag ...        same; flags are appended to `vllm serve`
#   entrypoint.sh download                    fetch the weights into $HF_HOME, then exit
#   entrypoint.sh <command> [args]            run anything else (bash, nvidia-smi, ...)
#
# Configuration is environment-driven. The profile baked into the image
# ($LLM_PROFILE_FILE, copied from models/<profile>.env at build time) supplies
# defaults; any variable that is already set and non-empty in the container
# environment wins. models/_template.env documents every supported variable.
# ---------------------------------------------------------------------------
set -euo pipefail

PROFILE_FILE="${LLM_PROFILE_FILE:-/opt/llm/profile.env}"
TEMPLATES_DIR="${LLM_TEMPLATES_DIR:-/opt/llm/templates}"

log() { printf '[entrypoint] %s\n' "$*" >&2; }

# Export KEY=VALUE pairs from a profile file for variables that are unset/empty.
# Format: one KEY=VALUE per line, '#' comments on their own line, optional quotes.
load_profile() {
  local file=$1 line key value
  if [[ ! -f "$file" ]]; then
    log "no profile at $file; using environment only"
    return 0
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"            # trim leading whitespace
    [[ -z "$line" || "$line" == \#* ]] && continue      # blank or comment
    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"                # trim trailing whitespace
    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      log "profile: ignoring malformed line: $line"
      continue
    fi
    case "$value" in                                    # strip one pair of quotes
      \"*\") value="${value#\"}"; value="${value%\"}" ;;
      \'*\') value="${value#\'}"; value="${value%\'}" ;;
    esac
    if [[ -z "${!key:-}" ]]; then
      export "$key=$value"
    fi
  done < "$file"
}

load_profile "$PROFILE_FILE"

# Hugging Face token from a Docker secret (build: --secret id=hf_token,env=HF_TOKEN).
if [[ -z "${HF_TOKEN:-}" && -r /run/secrets/hf_token ]]; then
  HF_TOKEN="$(tr -d '\r\n' < /run/secrets/hf_token)"
  export HF_TOKEN
fi

require_model() {
  : "${MODEL:?MODEL is not set: the image carries no profile and none was given in the environment}"
}

download_weights() {
  require_model
  log "downloading ${MODEL} (revision: ${MODEL_REVISION:-main}) into ${HF_HOME:-$HOME/.cache/huggingface}"
  python3 - <<'PY'
import os
from huggingface_hub import HfApi, snapshot_download

model     = os.environ["MODEL"]
revision  = os.environ.get("MODEL_REVISION") or None
tokenizer = os.environ.get("TOKENIZER") or None

# Skip files vLLM never reads. Prefer safetensors over legacy .bin when both exist.
ignore = ["*.md", "*.h5", "*.msgpack", "*.onnx", "*.tflite", "*.ot", "*.gguf",
          "coreml/*", "*.mlpackage/*", "onnx/*", "openvino/*"]
files = HfApi().list_repo_files(model, revision=revision)
if any(f.endswith(".safetensors") for f in files):
    ignore += ["*.bin", "*.pt", "*.pth"]

path = snapshot_download(model, revision=revision, ignore_patterns=ignore)
print(f"[entrypoint] weights ready: {path}")
if tokenizer and tokenizer != model:
    print(f"[entrypoint] tokenizer ready: {snapshot_download(tokenizer)}")
PY
}

serve() {
  require_model
  local args=( "$MODEL" --host 0.0.0.0 --port "${PORT:-8000}" )
  [[ -n "${MODEL_REVISION:-}" ]]         && args+=( --revision "$MODEL_REVISION" )
  [[ -n "${TOKENIZER:-}" ]]              && args+=( --tokenizer "$TOKENIZER" )
  [[ -n "${SERVED_MODEL_NAME:-}" ]]      && args+=( --served-model-name "$SERVED_MODEL_NAME" )
  [[ -n "${DTYPE:-}" ]]                  && args+=( --dtype "$DTYPE" )
  [[ -n "${MAX_MODEL_LEN:-}" ]]          && args+=( --max-model-len "$MAX_MODEL_LEN" )
  [[ -n "${MAX_NUM_SEQS:-}" ]]           && args+=( --max-num-seqs "$MAX_NUM_SEQS" )
  [[ -n "${GPU_MEMORY_UTILIZATION:-}" ]] && args+=( --gpu-memory-utilization "$GPU_MEMORY_UTILIZATION" )
  [[ -n "${TENSOR_PARALLEL_SIZE:-}" ]]   && args+=( --tensor-parallel-size "$TENSOR_PARALLEL_SIZE" )
  [[ "${TRUST_REMOTE_CODE:-0}" == "1" ]] && args+=( --trust-remote-code )

  if [[ -n "${CHAT_TEMPLATE:-}" ]]; then
    # A bare file name refers to a template shipped in the image (templates/).
    local tpl="$CHAT_TEMPLATE"
    [[ "$tpl" != /* && -f "$TEMPLATES_DIR/$tpl" ]] && tpl="$TEMPLATES_DIR/$tpl"
    args+=( --chat-template "$tpl" )
  fi

  if [[ -n "${VLLM_EXTRA_ARGS:-}" ]]; then
    # shellcheck disable=SC2206  # word splitting is the point here
    args+=( ${VLLM_EXTRA_ARGS} )
  fi
  args+=( "$@" )

  log "profile=${PROFILE_FILE} HF_HOME=${HF_HOME:-default} HF_HUB_OFFLINE=${HF_HUB_OFFLINE:-0}"
  [[ -n "${VLLM_API_KEY:-}" ]] && log "API key authentication enabled (VLLM_API_KEY)"
  log "exec: vllm serve ${args[*]}"
  exec vllm serve "${args[@]}"
}

case "${1:-serve}" in
  serve)    shift || true; serve "$@" ;;
  -*)       serve "$@" ;;
  download) download_weights ;;
  *)        exec "$@" ;;
esac
