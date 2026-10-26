#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# End-to-end check of a running server with curl only.
#
#   scripts/smoke-test.sh                        http://localhost:$HOST_PORT
#   scripts/smoke-test.sh http://gpu-box:8000    any base URL
#
# Honours VLLM_API_KEY from the environment or .env.
# ---------------------------------------------------------------------------
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BASE_URL="${1:-${BASE_URL:-http://localhost:${HOST_PORT}}}"
BASE_URL="${BASE_URL%/}"
auth=()
[[ -n "${VLLM_API_KEY:-}" ]] && auth=(-H "Authorization: Bearer $VLLM_API_KEY")

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }

step "GET $BASE_URL/health"
curl -fsS "${auth[@]}" "$BASE_URL/health" && echo "ok"

step "GET $BASE_URL/v1/models"
models_json="$(curl -fsS "${auth[@]}" "$BASE_URL/v1/models")"
echo "$models_json"
model="$(printf '%s' "$models_json" | grep -o '"id": *"[^"]*"' | head -n1 | sed 's/.*"\([^"]*\)"$/\1/')"
[[ -n "$model" ]] || die "could not read a model id from /v1/models"

step "POST $BASE_URL/v1/chat/completions  (model=$model)"
curl -fsS "${auth[@]}" "$BASE_URL/v1/chat/completions" \
  -H 'Content-Type: application/json' \
  -d '{
        "model": "'"$model"'",
        "messages": [{"role": "user", "content": "In one sentence, what is a qubit?"}],
        "max_tokens": 64,
        "temperature": 0.2
      }'
echo

step "POST $BASE_URL/v1/completions  (model=$model)"
curl -fsS "${auth[@]}" "$BASE_URL/v1/completions" \
  -H 'Content-Type: application/json' \
  -d '{
        "model": "'"$model"'",
        "prompt": "The capital of France is",
        "max_tokens": 8,
        "temperature": 0
      }'
echo

printf '\n\033[1;32mAll smoke tests passed.\033[0m\n'
