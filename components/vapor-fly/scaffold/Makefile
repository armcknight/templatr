# The vapor-fly component's targets come from armcknight/templatr at
# TEMPLATES_TAG. The fragment is downloaded on first use; `make templates-update`
# downloads it again, as after changing the tag.
#
# Commands are namespaced: `make server deploy` runs the server-deploy target.
# The direct form, `make server-deploy`, works too.
#
# `make server deploy` deploys to Fly.io. Only the owner runs it.

TEMPLATES_TAG = {{templates.tag}}
VAPOR_FLY_PRODUCT = {{inputs.product}}
VAPOR_FLY_APP = {{inputs.fly_app}}
VAPOR_FLY_HEALTH_PATH = {{inputs.health_check_path}}
VAPOR_FLY_PORT = {{inputs.internal_port}}
VAPOR_FLY_BRANCH = {{inputs.default_branch}}
# Targets each build runs first.
VAPOR_FLY_BUILD_PREREQUISITES =
# Targets `make server deploy` also runs first.
VAPOR_FLY_DEPLOY_PREREQUISITES =

TEMPLATES_MAKE = .superlinear/make

# `make <namespace> <command>` runs `<namespace>-<command>`, and the words after
# the namespace do nothing by themselves. A namespace with no command lists the
# targets.
NAMESPACES := server
ifneq ($(filter $(firstword $(MAKECMDGOALS)),$(NAMESPACES)),)
NS  := $(firstword $(MAKECMDGOALS))
CMD := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
.PHONY: $(NS)
$(NS):
	@$(MAKE) --no-print-directory $(if $(strip $(CMD)),$(NS)-$(CMD),help)
%:
	@:
endif

.DEFAULT_GOAL = help
.PHONY: help templates-update server-build server-serve server-serve-docker server-serve-docker-down server-deploy server-status

include $(TEMPLATES_MAKE)/vapor-fly.mk

$(TEMPLATES_MAKE)/%.mk:
	mkdir -p $(@D)
	curl -fsSL https://raw.githubusercontent.com/armcknight/templatr/$(TEMPLATES_TAG)/make/$*.mk -o $@

## help: list these targets
help:
	@awk '/^## /{ t = substr($$0, 4); c = index(t, ":"); printf "  make %-28s %s\n", substr(t, 1, c - 1), substr(t, c + 2) }' $(firstword $(MAKEFILE_LIST))

## templates-update: download the Makefile fragments again at TEMPLATES_TAG
templates-update:
	rm -rf $(TEMPLATES_MAKE)
	$(MAKE) $(TEMPLATES_MAKE)/vapor-fly.mk

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
