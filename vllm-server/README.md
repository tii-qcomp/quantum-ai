# vllm-server

Reproducible Docker images for serving LLMs with [vLLM](https://docs.vllm.ai) behind an
OpenAI-compatible API, plus a chat UI with web search and optional monitoring, all from
upstream images. Build the model image once, ship it to the GPU box, `docker compose up`.
Models are small profile files, so a second model is a new profile, not a new project.

Default profile: **Falcon-7B-Instruct in bf16** (its native precision, no quantization) on an
NVIDIA RTX PRO 6000 Blackwell (96 GB), driver 595 / CUDA 13.2.

## What runs

| Service | Image | Profile | Port on the host | Purpose |
|---|---|---|---|---|
| `vllm` | built here from `vllm/vllm-openai` | always | 8000 | OpenAI-compatible API |
| `open-webui` | `ghcr.io/open-webui/open-webui` | `ui` | 3000 | Chat UI, documents, web search |
| `searxng` | `searxng/searxng` | `ui` | 127.0.0.1:8081 | Private metasearch engine behind Open WebUI |
| `prometheus` | `prom/prometheus` | `monitoring` | 127.0.0.1:9090 | Scrapes vLLM `/metrics` |
| `grafana` | `grafana/grafana` | `monitoring` | 3001 | Dashboards |

`COMPOSE_PROFILES` in `.env` picks the optional services (`ui` by default). Only the
`vllm` image is built; everything else is pinned upstream images plus two small config
files (`searxng/settings.yml`, `monitoring/*.yml`).

## Layout

```
vllm-server/
├── Dockerfile              two targets: server (no weights) and server-with-weights
├── docker-compose.yml      vllm + optional ui / monitoring profiles
├── .env.example            deployment settings (profile, versions, ports, secrets)
├── overrides.env.example   optional runtime overrides for vllm, kept next to the compose file
├── Makefile                task runner (Linux/macOS/WSL); wraps scripts/ and compose
├── docker/entrypoint.sh    turns env vars into a `vllm serve` command line
├── models/
│   ├── _template.env       every supported knob, documented
│   ├── falcon-7b-instruct.env
│   ├── falcon-7b.env
│   └── falcon3-7b-instruct.env
├── templates/falcon.jinja  fallback chat template for models without one
├── searxng/settings.yml    enables JSON output for Open WebUI, disables the rate limiter
├── monitoring/             prometheus.yml + Grafana datasource/dashboard provisioning
├── scripts/
│   ├── build.sh            docker build with the right args, target, tag, secrets
│   ├── save-image.sh       docker save -> dist/*.tar.zst (or .tar.gz)
│   ├── load-image.sh       docker load on the server
│   ├── push.sh             docker push to the registry in IMAGE_NAME
│   ├── smoke-test.sh       curl /health, /v1/models, chat and text completions
│   └── check-server.sh     Docker, Compose, driver and Container Toolkit checks
└── tests/smoke_test.py     same checks through the official OpenAI Python SDK
```

## How configuration is layered

| Layer | File | Read by | Purpose |
|---|---|---|---|
| Deployment | `.env` | compose, scripts, Makefile | profile, versions, image name/tag, ports, secrets, profiles |
| Model | `models/<profile>.env` | baked into the image, read by the entrypoint at start | model id, revision, dtype, context length, memory fraction |
| Runtime overrides | `overrides.env` (optional) | compose `env_file` on `vllm` | change any model knob without rebuilding |

Precedence at container start: environment (compose `environment:`, `overrides.env`, `-e`)
beats the baked profile. Empty values count as "not set".

## Quick start

### 0. Prerequisites

Build machine: Docker with BuildKit (Docker Desktop on Windows is fine, it builds `linux/amd64`
images). Run the scripts from Git Bash or WSL on Windows.

GPU server (Ubuntu): NVIDIA driver, Docker Engine, Compose v2.24+, NVIDIA Container Toolkit.
To install the toolkit:

```bash
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker
```

Then, from a checkout of this folder on the server:

```bash
cp .env.example .env              # fill SEARXNG_SECRET and WEBUI_SECRET_KEY: openssl rand -hex 32
bash scripts/check-server.sh      # or: make check-server
```

### 1. Build the model image

```bash
cp .env.example .env              # already done in this checkout
bash scripts/build.sh             # or: make build
```

With the defaults this builds `local/vllm-models:falcon-7b-instruct-v0.32.0` from the
`server-with-weights` target: the vLLM v0.32.0 CUDA 13 image plus the Falcon-7B-Instruct
snapshot (safetensors only, pinned commit) baked in. The result runs fully offline.
Size: the vLLM base is about 20 GB uncompressed, the weights add 14.4 GB.

`BUILD_TARGET=server bash scripts/build.sh` (or `make build-slim`) builds the same image
without weights; they are then downloaded into the `hf-cache` volume on first start.

### 2. Ship it to the server

Either path works; pick one.

**A. Tarball over scp / rsync** (no registry needed)

```bash
bash scripts/save-image.sh                     # writes dist/local_vllm-models_falcon-7b-instruct-v0.32.0.tar.zst
rsync -avP dist/*.tar.zst user@server:~/
# on the server
bash scripts/load-image.sh ~/local_vllm-models_falcon-7b-instruct-v0.32.0.tar.zst
```

zstd is used when available (`apt-get install zstd`, or `winget install zstd` on Windows),
otherwise gzip. `.tar.gz` and plain `.tar` are accepted on both ends.

**B. Registry**

```bash
# .env: IMAGE_NAME=ghcr.io/<user>/vllm-models
docker login ghcr.io -u <user>
bash scripts/push.sh
# on the server
docker compose pull
```

**C. Build on the server instead.** Clone this folder there and run step 1 on the GPU box.
Simplest when the server has internet access.

The other services are pulled from their registries on the server (`make pull-services`
does it ahead of time).

### 3. Run

On the server, in this folder with the same `.env`:

```bash
docker compose up -d              # or: make up
docker compose logs -f vllm       # or: make logs
```

First start of `vllm` takes a few minutes: weight loading, `torch.compile`, CUDA-graph
capture. The container reports `healthy` once `/health` answers. Everything restarts
automatically on reboot (`restart: unless-stopped`).

Open WebUI is up at `http://server:3000` right away; it lists the model as soon as vLLM is
healthy. The first account you create there is the admin.

### 4. Test

```bash
bash scripts/smoke-test.sh                          # from the server
bash scripts/smoke-test.sh http://server:8000       # from anywhere
pip install -r tests/requirements.txt && python tests/smoke_test.py --base-url http://server:8000/v1
curl 'http://127.0.0.1:8081/search?q=vllm&format=json' | head -c 300   # SearXNG, on the server
```

## Using the API

Any OpenAI client works by pointing `base_url` at the server. The model name is
`SERVED_MODEL_NAME` from the profile (`falcon-7b-instruct`).

```python
from openai import OpenAI

client = OpenAI(base_url="http://server:8000/v1", api_key="not-needed")
reply = client.chat.completions.create(
    model="falcon-7b-instruct",
    messages=[{"role": "user", "content": "Explain superposition in two sentences."}],
    max_tokens=128,
)
print(reply.choices[0].message.content)
```

```bash
curl http://server:8000/v1/chat/completions -H 'Content-Type: application/json' -d '{
  "model": "falcon-7b-instruct",
  "messages": [{"role": "user", "content": "Explain superposition in two sentences."}],
  "max_tokens": 128
}'
```

Endpoints: `/v1/models`, `/v1/chat/completions`, `/v1/completions`, `/v1/embeddings`
(for embedding models), `/health`, `/metrics` (Prometheus), `/docs` (Swagger UI).

To require an API key, set `VLLM_API_KEY=<secret>` in `.env` before `docker compose up`.
Clients must then send `Authorization: Bearer <secret>`; Open WebUI picks it up automatically.

## Chat UI and web search (`ui` profile)

Open WebUI talks to vLLM over the compose network and to SearXNG for web search. Toggle
the globe icon in the chat box to search; Open WebUI asks the model for search queries,
fetches the top results through SearXNG, embeds them locally (CPU, a small
sentence-transformers model downloaded on first use) and injects the best chunks into the
prompt. Documents uploaded to a chat go through the same retrieval pipeline.

Two things to know:

- **Settings are seeded once.** The `environment:` block for `open-webui` only applies on
  the first start; afterwards Open WebUI keeps those values in its database and you change
  them under Admin > Settings (Connections, Web Search, Documents). Set
  `ENABLE_PERSISTENT_CONFIG=false` on the service if you prefer the compose file to always win.
- **Falcon-7B has a 2048-token window.** Retrieval sizing in `.env`
  (`WEB_SEARCH_RESULT_COUNT`, `RAG_TOP_K`, `RAG_CHUNK_SIZE`) is deliberately small so the
  injected context fits. Long chats plus search can still exceed the window, and the 2023
  model is weak at generating search queries. For search-augmented chat, build the
  `falcon3-7b-instruct` profile instead (32k context, same family) and raise those values.

SearXNG is private: only published on `127.0.0.1:8081` of the server, rate limiter off
(it needs no Valkey/Redis), JSON output enabled in `searxng/settings.yml` because Open WebUI
requires it.

## Monitoring (`monitoring` profile)

Add `monitoring` to `COMPOSE_PROFILES` and `docker compose up -d`. Prometheus scrapes
`vllm:8000/metrics` every 15 s and keeps 30 days. Grafana is at `http://server:3001`
(admin / `GRAFANA_ADMIN_PASSWORD`) with the datasource already provisioned. Any `*.json`
in `monitoring/grafana/dashboards/` is loaded as a dashboard; vLLM's official one:

```bash
curl -fsSLo monitoring/grafana/dashboards/vllm.json \
  https://raw.githubusercontent.com/vllm-project/vllm/v0.32.0/examples/observability/prometheus_grafana/grafana.json
```

It shows tokens/s, time to first token, queue depth, KV-cache usage and request latency.

## Configuration reference

All model knobs are listed and documented in [models/_template.env](models/_template.env).
The ones that matter most for Falcon-7B on this GPU:

| Variable | Default | Notes |
|---|---|---|
| `DTYPE` | `bfloat16` | Falcon's native dtype. `float32` for true fp32 (28 GB of weights, slower). `auto` reads `config.json`. |
| `MAX_MODEL_LEN` | `2048` | Falcon-7B's context window. Must not be raised. |
| `GPU_MEMORY_UTILIZATION` | `0.90` | Fraction of the 96 GB vLLM claims. Weights take ~14 GB; the rest becomes KV cache. Lower it to share the GPU. |
| `MAX_NUM_SEQS` | `256` | Concurrent sequences per step. |
| `CHAT_TEMPLATE` | empty | Falcon-7B-Instruct ships its own. Base models use `falcon.jinja`. |
| `VLLM_EXTRA_ARGS` | empty | Anything else, e.g. `--enforce-eager`. |

Change them for one deployment in `overrides.env` (then `make restart`), or permanently in
the profile (then rebuild).

## Adding another model

1. `cp models/_template.env models/<name>.env` and fill it in. Pin `MODEL_REVISION` to a
   commit hash from the model's "Files and versions" page for reproducible images.
2. `MODEL_PROFILE=<name>` in `.env`. `IMAGE_TAG` can stay empty; it becomes `<name>-<vLLM version>`.
3. `bash scripts/build.sh`, ship, `docker compose up -d`.

Set `HF_TOKEN` in the shell for gated repos; `build.sh` passes it as a BuildKit secret, so it
never lands in an image layer. Models needing custom code set `TRUST_REMOTE_CODE=1`. Multi-GPU
hosts set `TENSOR_PARALLEL_SIZE`.

Ready-made profiles: `falcon-7b-instruct` (default), `falcon-7b` (base model, completions
only) and `falcon3-7b-instruct` (32k context, recommended with the UI).

## Other add-ons worth considering

All of these are upstream images plus a few lines of compose; none is wired in yet.

- **GPU embeddings.** Open WebUI embeds web pages and documents on the CPU with a small
  model. A second `vllm` service running an embedding model (for example `BAAI/bge-m3`, a
  new profile) and `RAG_EMBEDDING_ENGINE=openai` + `RAG_OPENAI_API_BASE_URL=http://vllm-embed:8000/v1`
  on Open WebUI moves that to the GPU, which has room to spare next to a 7B model.
- **Apache Tika** (`apache/tika:latest-full`) for better PDF/Office parsing in Open WebUI:
  `CONTENT_EXTRACTION_ENGINE=tika`, `TIKA_SERVER_URL=http://tika:9998`.
- **Reverse proxy with TLS** (Caddy or Traefik) if the box is reachable beyond the LAN.
  Open WebUI has accounts; vLLM only has the optional API key; Grafana has its admin login.
- **LiteLLM proxy** only if you need to fan out to several backends or hand out per-user keys.

## Blackwell / CUDA notes

- The RTX PRO 6000 Blackwell is compute capability 12.0 (`sm_120`). vLLM's official images
  since mid-2025 compile for it (`TORCH_CUDA_ARCH_LIST` includes `12.0`), and v0.32.0's default
  tag is a CUDA 13.0 build. The 595 driver (CUDA 13.2) is newer than the toolkit, which is the
  supported direction. No CUDA install is needed on the host, only the driver and the toolkit.
- Falcon-7B is a plain dense bf16 transformer; the community issues reported for `sm_120`
  concern FP8 / NVFP4 kernels and MoE models, not this path.
- If the attention backend misbehaves after a vLLM upgrade, force one in `overrides.env`
  (`VLLM_ATTENTION_BACKEND=FLASHINFER` or `FLASH_ATTN`; see the vLLM docs for the version in use).
- To change the base image: edit `VLLM_VERSION` in `.env` (for example `v0.32.0-cu129` for a
  CUDA 12.9 build) and rebuild. Tags are listed at https://hub.docker.com/r/vllm/vllm-openai/tags.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `could not select device driver "nvidia"` | NVIDIA Container Toolkit missing or Docker not restarted after `nvidia-ctk runtime configure`. Run `scripts/check-server.sh`. |
| `Free memory on device ... is less than desired GPU memory utilization` | Something else holds VRAM (`nvidia-smi`). Lower `GPU_MEMORY_UTILIZATION` in `overrides.env`. |
| `vllm` stays `starting` for a long time | Normal for the first minutes. Watch `docker compose logs -f vllm`. `server` images also download the weights on first start. |
| Very slow start every time | Add `VLLM_EXTRA_ARGS=--enforce-eager` to skip compilation (lower throughput). |
| `chat template` error on `/v1/chat/completions` | The model has no template. Set `CHAT_TEMPLATE=falcon.jinja` or add a template under `templates/`. |
| Image pulled on the server but compose can't find it | `docker image ls`, then make `IMAGE_NAME` / `IMAGE_TAG` in `.env` match. |
| Need to serve a different model with an existing slim image | Set `MODEL`, `MODEL_REVISION`, `SERVED_MODEL_NAME`, `MAX_MODEL_LEN` in `overrides.env`. Not possible with `server-with-weights` images (`HF_HUB_OFFLINE=1`). |
| `error from registry: denied` pulling `ghcr.io/open-webui/...` | A stale `docker login ghcr.io` is stored (`docker-credential-desktop list` / `~/.docker/config.json`). The image is public: `docker logout ghcr.io`, or log in again with a token that has `read:packages`. |
| Open WebUI shows no model | vLLM not healthy yet (`make status`), or `VLLM_API_KEY` set after Open WebUI's first start: update the key under Admin > Settings > Connections. |
| Web search returns `403` from SearXNG | `json` missing from `search.formats` in `searxng/settings.yml`, or the rate limiter was turned on. |
| `maximum context length` errors with web search or documents | Lower `RAG_TOP_K` / `RAG_CHUNK_SIZE`, start a new chat, or switch to the `falcon3-7b-instruct` profile. |
| Changing `open-webui` environment has no effect | Settings are persisted after the first start. Change them in Admin > Settings or set `ENABLE_PERSISTENT_CONFIG=false`. |

Useful commands: `make shell` for a shell in the vllm container, `make status` for health,
`docker compose exec vllm nvidia-smi` to see VRAM use from inside.
