# The vapor-fly component's targets, for the server in this directory. The root
# Makefile includes this file; the fragment comes from armcknight/templatr at
# TEMPLATES_TAG.
#
# `make server <command>` runs server-<command>, such as `make server serve`.
#
# `make server deploy` deploys to Fly.io. Only the owner runs it.

VAPOR_FLY_DIR = server
VAPOR_FLY_PRODUCT = {{inputs.product}}
VAPOR_FLY_APP = {{inputs.fly_app}}
VAPOR_FLY_HEALTH_PATH = {{inputs.health_check_path}}
VAPOR_FLY_PORT = {{inputs.internal_port}}
VAPOR_FLY_BRANCH = {{inputs.default_branch}}
# Targets each build runs first.
VAPOR_FLY_BUILD_PREREQUISITES =
# Targets `make server deploy` also runs first.
VAPOR_FLY_DEPLOY_PREREQUISITES =

NAMESPACES += server
TEMPLATES_FRAGMENTS += $(TEMPLATES_MAKE)/vapor-fly.mk

include $(TEMPLATES_MAKE)/vapor-fly.mk

.PHONY: server-build server-serve server-serve-docker server-serve-docker-down server-deploy server-status

## server-build: build the server
server-build: vapor-fly-build

## server-serve: build and run the server on this Mac
server-serve: vapor-fly-serve

## server-serve-docker: run the server's image with docker compose, as Fly runs it
server-serve-docker: vapor-fly-serve-docker

## server-serve-docker-down: stop docker compose
server-serve-docker-down: vapor-fly-serve-docker-down

## server-deploy: deploy a clean, current checkout of the default branch to Fly
server-deploy: vapor-fly-deploy

## server-status: show the Fly app's machines and its health check's answer
server-status: vapor-fly-status
