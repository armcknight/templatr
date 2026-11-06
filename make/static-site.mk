# The static-site component's Makefile targets. A project's site/component.mk,
# from the static-site scaffold, includes this file, which the root Makefile
# downloads at its pinned tag, and maps `make site <command>` to these targets.
# The targets are namespaced so that the project's own targets can depend on
# them, or do more, such as checking data before a build. They run from the
# repository's root.
#
# Set these before the include, as make reads a rule's prerequisites when it
# reads the rule:
#
#   TEMPLATES_TAG                    the templatr tag that the scripts are downloaded at
#   TEMPLATES_MAKE                   where the fragments and the scripts are downloaded to
#   STATIC_SITE_DIR                  the directory with the site's sources, its component.mk and its DEPLOYED stamp
#   STATIC_SITE_NAME                 the namespace: the commit that records a deploy is "deploy(<name>): <commit>"
#   STATIC_SITE_DOMAIN               the domain the site is served at
#   STATIC_SITE_WITH_WWW             true when www.<domain> is served too, and redirects to the domain
#   STATIC_SITE_BUILD                the command, run in STATIC_SITE_DIR, that builds the site; empty for files uploaded as they are
#   STATIC_SITE_OUTPUT               the built site, relative to STATIC_SITE_DIR
#   STATIC_SITE_IMMUTABLE            directories under the output whose file names change with their contents, such as assets for Vite
#   STATIC_SITE_INVALIDATE           the paths each deploy clears from CloudFront, /* by default
#   STATIC_SITE_PORT                 the port static-site-serve serves the built site on
#   STATIC_SITE_PROFILE              the AWS profile the commands run with
#   STATIC_SITE_PRICE_CLASS          the distribution's price class
#   STATIC_SITE_REDIRECT_FROM        domains that redirect to the site, each with its www, separated by spaces
#   STATIC_SITE_BUILD_PREREQUISITES  targets each build runs first
#   STATIC_SITE_DEPLOY_PREREQUISITES targets static-site-deploy also runs first, such as a link check
#   STATIC_SITE_LOG_DIR              where the targets write their logs
#
# aws comes from awscli, and the site's generator from the site's Brewfile.

TEMPLATES_TAG ?=
TEMPLATES_MAKE ?= .templatr/make
STATIC_SITE_DIR ?= site
STATIC_SITE_NAME ?= site
STATIC_SITE_DOMAIN ?=
STATIC_SITE_WITH_WWW ?= false
STATIC_SITE_BUILD ?=
STATIC_SITE_OUTPUT ?= public
STATIC_SITE_IMMUTABLE ?=
STATIC_SITE_INVALIDATE ?= /*
STATIC_SITE_PORT ?= 4000
STATIC_SITE_PROFILE ?= default
STATIC_SITE_PRICE_CLASS ?= PriceClass_100
STATIC_SITE_REDIRECT_FROM ?=
STATIC_SITE_BUILD_PREREQUISITES ?=
STATIC_SITE_DEPLOY_PREREQUISITES ?=
STATIC_SITE_LOG_DIR ?= $(STATIC_SITE_DIR)/logs
STATIC_SITE_STAMP ?= $(STATIC_SITE_DIR)/DEPLOYED
# The CloudFormation stack, named for the domain, in us-east-1.
STATIC_SITE_STACK ?= site-$(subst .,-,$(STATIC_SITE_DOMAIN))
STATIC_SITE_OUTPUT_PATH = $(STATIC_SITE_DIR)/$(STATIC_SITE_OUTPUT)

# The scripts that the targets run, and the stacks' templates with their
# functions, downloaded from templatr at TEMPLATES_TAG on first use, like the
# fragments.
STATIC_SITE_BIN = $(TEMPLATES_MAKE)/static-site
STATIC_SITE_SCRIPTS = $(STATIC_SITE_BIN)/deploy-site $(STATIC_SITE_BIN)/deploy-stack $(STATIC_SITE_BIN)/deploy-redirect-stacks $(STATIC_SITE_BIN)/site-zone $(STATIC_SITE_BIN)/site-template $(STATIC_SITE_BIN)/serve-site.py
STATIC_SITE_TEMPLATE = $(STATIC_SITE_BIN)/site.yml
STATIC_SITE_FUNCTION = $(STATIC_SITE_BIN)/viewer-request.js
STATIC_SITE_REDIRECT_TEMPLATE = $(STATIC_SITE_BIN)/redirect.yml
STATIC_SITE_REDIRECT_FUNCTION = $(STATIC_SITE_BIN)/redirect.js
STATIC_SITE_STACK_SCRIPTS = $(STATIC_SITE_BIN)/deploy-stack $(STATIC_SITE_BIN)/site-zone $(STATIC_SITE_BIN)/site-template

$(STATIC_SITE_BIN)/%:
	@test -n "$(TEMPLATES_TAG)" || { echo "Set TEMPLATES_TAG to the templatr tag that the project is pinned to." >&2; exit 1; }
	mkdir -p $(@D)
	curl -fsSL https://raw.githubusercontent.com/armcknight/templatr/$(TEMPLATES_TAG)/components/static-site/bin/$* -o $@
	chmod +x $@

$(STATIC_SITE_TEMPLATE) $(STATIC_SITE_FUNCTION) $(STATIC_SITE_REDIRECT_TEMPLATE) $(STATIC_SITE_REDIRECT_FUNCTION):
	@test -n "$(TEMPLATES_TAG)" || { echo "Set TEMPLATES_TAG to the templatr tag that the project is pinned to." >&2; exit 1; }
	mkdir -p $(@D)
	curl -fsSL https://raw.githubusercontent.com/armcknight/templatr/$(TEMPLATES_TAG)/components/static-site/cloudformation/$(@F) -o $@

# The recipes use pipefail, which /bin/sh may not have.
SHELL := /bin/bash

STATIC_SITE_AWS = aws --profile $(STATIC_SITE_PROFILE) --no-cli-pager
# An output of the stack, read when a recipe runs: $(call static_site_output,DistributionId).
static_site_output = $$($(STATIC_SITE_AWS) cloudformation describe-stacks --stack-name $(STATIC_SITE_STACK) --region us-east-1 --query "Stacks[0].Outputs[?OutputKey=='$(1)'].OutputValue | [0]" --output text)

.PHONY: static-site-build static-site-serve static-site-endserve static-site-deploy static-site-bust-cache static-site-invalidations static-site-stack static-site-redirects static-site-status static-site-domain

## static-site-build: build the site into its output directory; nothing to do when STATIC_SITE_BUILD is empty
static-site-build: $(STATIC_SITE_BUILD_PREREQUISITES)
	@mkdir -p $(STATIC_SITE_LOG_DIR); set -o pipefail; \
	if [ -z "$(STATIC_SITE_BUILD)" ]; then echo "Nothing to build: the files in $(STATIC_SITE_OUTPUT_PATH) are uploaded as they are."; exit 0; fi; \
	cd $(STATIC_SITE_DIR) && $(STATIC_SITE_BUILD) 2>&1 | tee $(CURDIR)/$(STATIC_SITE_LOG_DIR)/static-site-build.log

# It serves the build, not the sources: there is no watch and no reload, so
# each change needs another build. A page that does not exist gets 404.html
# with a 404 status, as the distribution answers it; open /nope to see it.
## static-site-serve: serve the built site at http://localhost:STATIC_SITE_PORT and open it
static-site-serve: $(STATIC_SITE_BIN)/serve-site.py
	@test -d $(STATIC_SITE_OUTPUT_PATH) || { echo "$(STATIC_SITE_OUTPUT_PATH) does not exist. Build the site first." >&2; exit 1; }
	@if lsof -ti :$(STATIC_SITE_PORT) -sTCP:LISTEN >/dev/null 2>&1; then echo "Something already serves port $(STATIC_SITE_PORT). Run make $(STATIC_SITE_NAME) endserve first." >&2; exit 1; fi
	@mkdir -p $(STATIC_SITE_LOG_DIR); cd $(STATIC_SITE_OUTPUT_PATH) && nohup python3 $(CURDIR)/$(STATIC_SITE_BIN)/serve-site.py $(STATIC_SITE_PORT) > $(CURDIR)/$(STATIC_SITE_LOG_DIR)/static-site-serve.log 2>&1 &
	@echo "Serving $(STATIC_SITE_DOMAIN) at http://localhost:$(STATIC_SITE_PORT)"; command -v open >/dev/null && open http://localhost:$(STATIC_SITE_PORT) || true

## static-site-endserve: stop the served site, by its port
static-site-endserve:
	@pids=$$(lsof -ti :$(STATIC_SITE_PORT) -sTCP:LISTEN 2>/dev/null); \
	if [ -n "$$pids" ]; then echo "$$pids" | xargs kill && echo "Stopped the server on port $(STATIC_SITE_PORT)."; else echo "Nothing was serving port $(STATIC_SITE_PORT)."; fi

# deploy-site refuses a working tree with uncommitted changes, uploads what
# `build` last made, clears STATIC_SITE_INVALIDATE from CloudFront, then stamps
# and commits what is live; see the script. It does not build first. The log,
# in STATIC_SITE_LOG_DIR, is named with the commit.
## static-site-deploy: upload the built site, clear CloudFront, then stamp and commit what is live; only the owner runs it
static-site-deploy: static-site-domain $(STATIC_SITE_BIN)/deploy-site $(STATIC_SITE_DEPLOY_PREREQUISITES)
	@mkdir -p $(STATIC_SITE_LOG_DIR); set -o pipefail; \
	SHA=$$(git rev-parse --short HEAD); \
	STATIC_SITE_NAME="$(STATIC_SITE_NAME)" STATIC_SITE_DOMAIN="$(STATIC_SITE_DOMAIN)" \
	STATIC_SITE_OUTPUT="$(STATIC_SITE_OUTPUT_PATH)" STATIC_SITE_STAMP="$(STATIC_SITE_STAMP)" \
	STATIC_SITE_PROFILE="$(STATIC_SITE_PROFILE)" STATIC_SITE_IMMUTABLE="$(STATIC_SITE_IMMUTABLE)" \
	STATIC_SITE_INVALIDATE="$(STATIC_SITE_INVALIDATE)" \
	$(STATIC_SITE_BIN)/deploy-site 2>&1 | tee "$(STATIC_SITE_LOG_DIR)/static-site-deploy-$$SHA.log"

# PATHS is a space-separated list, each entry starting with /: that is what
# create-invalidation wants, one argument for each path. A comma joins
# nothing: "/a,/b" is one path that matches no file. A directory's address and
# its index.html are cached under separate keys, so clearing a page usually
# means both: PATHS="/blog/ /blog/index.html". /* is everything, and counts as
# one path. set -f keeps the shell from expanding it against the local files.
## static-site-bust-cache: clear PATHS="/ /index.html" from CloudFront
static-site-bust-cache: static-site-domain
	@test -n "$(PATHS)" || { echo 'usage: make $(STATIC_SITE_NAME) bust-cache PATHS="/ /index.html"' >&2; exit 1; }
	@set -f; $(STATIC_SITE_AWS) cloudfront create-invalidation --distribution-id $(call static_site_output,DistributionId) --paths $(PATHS) --query Invalidation.Id --output text

## static-site-invalidations: list the recent CloudFront invalidations and whether each has finished
static-site-invalidations: static-site-domain
	@$(STATIC_SITE_AWS) cloudfront list-invalidations --distribution-id $(call static_site_output,DistributionId) --query 'InvalidationList.Items[].[CreateTime,Status,Id]' --output table

## static-site-stack: make or update the bucket, certificate, distribution and DNS records from the component's template; only the owner runs it
static-site-stack: static-site-domain $(STATIC_SITE_STACK_SCRIPTS) $(STATIC_SITE_TEMPLATE) $(STATIC_SITE_FUNCTION)
	$(STATIC_SITE_BIN)/deploy-stack site $(STATIC_SITE_DOMAIN) $(STATIC_SITE_PROFILE) $(STATIC_SITE_TEMPLATE) WithWww=$(STATIC_SITE_WITH_WWW) PriceClass=$(STATIC_SITE_PRICE_CLASS)

## static-site-redirects: make or update the stack of each domain in STATIC_SITE_REDIRECT_FROM that redirects to the site; only the owner runs it
static-site-redirects: static-site-domain $(STATIC_SITE_STACK_SCRIPTS) $(STATIC_SITE_BIN)/deploy-redirect-stacks $(STATIC_SITE_REDIRECT_TEMPLATE) $(STATIC_SITE_REDIRECT_FUNCTION)
	@test -n "$(STATIC_SITE_REDIRECT_FROM)" || { echo "No domain redirects to $(STATIC_SITE_DOMAIN): set STATIC_SITE_REDIRECT_FROM."; exit 0; }
	$(STATIC_SITE_BIN)/deploy-redirect-stacks $(STATIC_SITE_DOMAIN) $(STATIC_SITE_PROFILE) $(STATIC_SITE_REDIRECT_TEMPLATE) $(STATIC_SITE_REDIRECT_FROM)

## static-site-status: show the stack's bucket, distribution and certificate, and the commit that is live
static-site-status: static-site-domain
	@$(STATIC_SITE_AWS) cloudformation describe-stacks --stack-name $(STATIC_SITE_STACK) --region us-east-1 --query 'Stacks[0].Outputs[].[OutputKey,OutputValue]' --output table
	@echo "Live at https://$(STATIC_SITE_DOMAIN)/DEPLOYED:"; curl -fsS --max-time 10 https://$(STATIC_SITE_DOMAIN)/DEPLOYED || echo "(no stamp yet)"

static-site-domain:
	@test -n "$(STATIC_SITE_DOMAIN)" || { echo "Set STATIC_SITE_DOMAIN to the domain the site is served at." >&2; exit 1; }
