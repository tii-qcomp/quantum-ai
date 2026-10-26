# syntax=docker/dockerfile:1
# ---------------------------------------------------------------------------
# vLLM OpenAI-compatible server, parameterised by a model profile.
#
# Targets (pick with --target, or BUILD_TARGET in .env):
#   server               vLLM + entrypoint + baked profile. Weights are pulled
#                        into HF_HOME (/models/hf) on first start, so mount a
#                        volume there (docker-compose.yml does).
#   server-with-weights  Same, plus the model snapshot downloaded into the image
#                        at /models/baked. Fully self-contained: no Hugging Face
#                        access needed at runtime (HF_HUB_OFFLINE=1).
#
# Build args:
#   VLLM_IMAGE     base image repository       (default vllm/vllm-openai)
#   VLLM_VERSION   base image tag              (default v0.32.0 = CUDA 13.0 build)
#   MODEL_PROFILE  name of models/<name>.env   (required)
#
# Secrets (optional, only for gated Hugging Face repos):
#   --secret id=hf_token,env=HF_TOKEN
# ---------------------------------------------------------------------------
ARG VLLM_IMAGE=vllm/vllm-openai
ARG VLLM_VERSION=v0.32.0

# ===========================================================================
# server: no weights inside the image
# ===========================================================================
FROM ${VLLM_IMAGE}:${VLLM_VERSION} AS server

ARG MODEL_PROFILE
RUN test -n "${MODEL_PROFILE}" \
 || { echo >&2 "ERROR: --build-arg MODEL_PROFILE=<name> is required (one of models/*.env)"; exit 1; }

ENV HF_HOME=/models/hf \
    LLM_PROFILE_FILE=/opt/llm/profile.env \
    LLM_TEMPLATES_DIR=/opt/llm/templates \
    PORT=8000

COPY docker/entrypoint.sh          /opt/llm/entrypoint.sh
COPY templates/                    /opt/llm/templates/
COPY models/${MODEL_PROFILE}.env   /opt/llm/profile.env

# Normalise line endings (repo may have been checked out on Windows), set modes.
RUN sed -i 's/\r$//' /opt/llm/entrypoint.sh /opt/llm/profile.env /opt/llm/templates/* \
 && chmod +x /opt/llm/entrypoint.sh \
 && mkdir -p /models/hf

ARG VLLM_VERSION
LABEL org.opencontainers.image.title="vllm-${MODEL_PROFILE}" \
      org.opencontainers.image.description="vLLM OpenAI-compatible server, profile ${MODEL_PROFILE}" \
      llm.profile="${MODEL_PROFILE}" \
      llm.vllm.version="${VLLM_VERSION}" \
      llm.weights.baked="false"

EXPOSE 8000

# Model load + torch.compile + CUDA-graph capture takes minutes; a first start of
# the `server` target also downloads the weights. Hence the long start period.
HEALTHCHECK --interval=30s --timeout=10s --start-period=20m --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${PORT}/health" || exit 1

ENTRYPOINT ["/opt/llm/entrypoint.sh"]
CMD ["serve"]

# ===========================================================================
# server-with-weights: weights baked in, runs fully offline
# ===========================================================================
FROM server AS server-with-weights

# Separate from /models/hf so a runtime volume mounted there never hides the
# baked snapshot.
ENV HF_HOME=/models/baked

RUN --mount=type=secret,id=hf_token \
    /opt/llm/entrypoint.sh download

ENV HF_HUB_OFFLINE=1
LABEL llm.weights.baked="true"
