# The vapor-fly component's Makefile targets. A project's server/component.mk
# includes this file, downloaded at its pinned tag, and maps `make server
# <command>` to them; the root Makefile includes server/component.mk. The
# targets are namespaced so that the project's own targets can depend on them,
# or do more. They run from the repository's root.
#
# Set these before the include, as make reads a rule's prerequisites when it
# reads the rule:
#
#   VAPOR_FLY_DIR                  the directory with the server's Swift package, Dockerfile and fly.toml
#   VAPOR_FLY_PRODUCT              the executable product that runs the server
#   VAPOR_FLY_APP                  the Fly app
#   VAPOR_FLY_HEALTH_PATH          the path that answers 200 when the server is ready
#   VAPOR_FLY_PORT                 the port the server listens on
#   VAPOR_FLY_BRANCH               the branch that deploys come from
#   VAPOR_FLY_SERVE_ARGS           the arguments `vapor-fly-serve` runs the product with
#   VAPOR_FLY_BUILD_PREREQUISITES  targets each build runs first
#   VAPOR_FLY_DEPLOY_PREREQUISITES targets vapor-fly-deploy also runs first, such as a migration check
#
# check-release-ready comes from the armcknight/tools cask, and fly from flyctl.

VAPOR_FLY_DIR ?= .
VAPOR_FLY_PRODUCT ?=
VAPOR_FLY_APP ?=
VAPOR_FLY_HEALTH_PATH ?= /healthz
VAPOR_FLY_PORT ?= 8080
VAPOR_FLY_BRANCH ?= main
VAPOR_FLY_SERVE_ARGS ?= serve --hostname 127.0.0.1 --port $(VAPOR_FLY_PORT)
VAPOR_FLY_BUILD_PREREQUISITES ?=
VAPOR_FLY_DEPLOY_PREREQUISITES ?=
VAPOR_FLY_URL ?= https://$(VAPOR_FLY_APP).fly.dev

# The recipes use pipefail, which /bin/sh may not have.
SHELL := /bin/bash

.PHONY: vapor-fly-build vapor-fly-serve vapor-fly-serve-docker vapor-fly-serve-docker-down vapor-fly-deploy vapor-fly-status vapor-fly-product vapor-fly-app

## vapor-fly-build: build the server with swift build
vapor-fly-build: vapor-fly-product $(VAPOR_FLY_BUILD_PREREQUISITES)
	@set -o pipefail; swift build --package-path $(VAPOR_FLY_DIR) --product $(VAPOR_FLY_PRODUCT) 2>&1 | tee $(VAPOR_FLY_DIR)/vapor-fly-build.log

## vapor-fly-serve: build and run the server on this Mac
vapor-fly-serve: vapor-fly-build
	@set -o pipefail; swift run --package-path $(VAPOR_FLY_DIR) --skip-build $(VAPOR_FLY_PRODUCT) $(VAPOR_FLY_SERVE_ARGS) 2>&1 | tee $(VAPOR_FLY_DIR)/vapor-fly-serve.log

## vapor-fly-serve-docker: build the image that Fly runs and run it with docker compose, for Linux parity
vapor-fly-serve-docker:
	@docker info >/dev/null 2>&1 || { echo "Docker is not running. Open Docker Desktop, or run colima start, and try again." >&2; exit 1; }
	@set -o pipefail; docker compose --file $(VAPOR_FLY_DIR)/docker-compose.yml up --build 2>&1 | tee $(VAPOR_FLY_DIR)/vapor-fly-serve-docker.log

## vapor-fly-serve-docker-down: stop the docker compose services
vapor-fly-serve-docker-down:
	docker compose --file $(VAPOR_FLY_DIR)/docker-compose.yml down

# fly deploy sends the local working tree to Fly's builder, so a deploy from a
# dirty checkout, another branch or a branch behind origin puts code on the
# server that is not on VAPOR_FLY_BRANCH. check-release-ready stops it first.
# The image gets the commit as GIT_SHA, and the deploy waits until the health
# check answers. fly deploy reads fly.toml in VAPOR_FLY_DIR, and builds the
# Dockerfile there with that directory as the context. The log is named with
# the commit.
## vapor-fly-deploy: deploy a clean, current checkout of VAPOR_FLY_BRANCH to Fly; only the owner runs it
vapor-fly-deploy: vapor-fly-app $(VAPOR_FLY_DEPLOY_PREREQUISITES)
	@check-release-ready --branch $(VAPOR_FLY_BRANCH)
	@set -o pipefail; \
	SHA=$$(git rev-parse --short HEAD); \
	{ \
	  fly deploy $(VAPOR_FLY_DIR) --app $(VAPOR_FLY_APP) --build-arg GIT_SHA=$$SHA && \
	  echo "Waiting for $(VAPOR_FLY_URL)$(VAPOR_FLY_HEALTH_PATH) to answer..." && \
	  for i in $$(seq 1 40); do \
	    if curl -fsS --max-time 10 "$(VAPOR_FLY_URL)$(VAPOR_FLY_HEALTH_PATH)" 2>/dev/null | grep -q "$$SHA"; then \
	      echo "Deployed $$SHA, and the health check answers."; exit 0; \
	    fi; \
	    sleep 3; \
	  done; \
	  echo "The deploy finished, but $(VAPOR_FLY_HEALTH_PATH) did not answer with $$SHA. See fly logs --app $(VAPOR_FLY_APP)." >&2; exit 1; \
	} 2>&1 | tee "$(VAPOR_FLY_DIR)/vapor-fly-deploy-$$SHA.log"

## vapor-fly-status: show the Fly app's machines and its health check's answer
vapor-fly-status: vapor-fly-app
	fly status --app $(VAPOR_FLY_APP)
	@curl -fsS --max-time 10 "$(VAPOR_FLY_URL)$(VAPOR_FLY_HEALTH_PATH)"; echo

vapor-fly-product:
	@test -n "$(VAPOR_FLY_PRODUCT)" || { echo "Set VAPOR_FLY_PRODUCT to the executable product that runs the server." >&2; exit 1; }

vapor-fly-app:
	@test -n "$(VAPOR_FLY_APP)" || { echo "Set VAPOR_FLY_APP to the Fly app." >&2; exit 1; }
