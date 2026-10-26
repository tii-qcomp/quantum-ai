# Task runner. Needs GNU make 4+ (Linux, macOS, WSL). On Windows run the
# scripts in scripts/ directly from Git Bash; every target is a one-liner.
.RECIPEPREFIX := >
SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

-include .env
export

.PHONY: help build build-slim build-weights push save load pull pull-services up down restart logs status shell smoke check-server download

help: ## Show this help
> @grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-14s %s\n", $$1, $$2}'

build: ## Build the image selected by .env (BUILD_TARGET decides whether weights are baked)
> bash ./scripts/build.sh

build-slim: ## Build without weights (downloaded into the hf-cache volume on first start)
> BUILD_TARGET=server bash ./scripts/build.sh

build-weights: ## Build with the model weights baked into the image
> BUILD_TARGET=server-with-weights bash ./scripts/build.sh

push: ## Push the image to the registry named in IMAGE_NAME
> bash ./scripts/push.sh

save: ## Export the image to dist/ for transfer with scp/rsync
> bash ./scripts/save-image.sh

load: ## Import an exported image: make load FILE=dist/<file>.tar.zst
> bash ./scripts/load-image.sh "$(FILE)"

pull: ## Pull the CI-built vllm image and the upstream service images
> docker compose pull

pull-services: ## Pre-pull only the upstream service images (when the vllm image is built locally)
> docker compose pull --ignore-pull-failures

up: ## Start the stack in the background (vllm + the profiles in COMPOSE_PROFILES)
> docker compose up -d

down: ## Stop and remove the container
> docker compose down

restart: ## Restart the container (picks up overrides.env changes)
> docker compose up -d --force-recreate

logs: ## Follow the server logs
> docker compose logs -f --tail=200

status: ## Container and health status
> docker compose ps

shell: ## Interactive shell inside the running container
> docker compose exec vllm bash

smoke: ## curl /health, /v1/models, /v1/chat/completions, /v1/completions
> bash ./scripts/smoke-test.sh

check-server: ## Verify Docker, Compose, NVIDIA driver and Container Toolkit on this host
> bash ./scripts/check-server.sh

download: ## Pre-download weights into the hf-cache volume (BUILD_TARGET=server images)
> docker compose run --rm --no-deps vllm download
