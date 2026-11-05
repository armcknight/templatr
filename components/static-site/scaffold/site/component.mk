# The static-site component's targets, for the site in this directory. The root
# Makefile includes this file; the fragment comes from armcknight/templatr at
# TEMPLATES_TAG.
#
# `make site <command>` runs site-<command>, such as `make site build`.
#
# `make site deploy` publishes the site, and `make site stack` changes its
# hosting. Only the owner runs them.

STATIC_SITE_DIR = site
STATIC_SITE_NAME = site
STATIC_SITE_DOMAIN = {{inputs.domain}}
# true when www.<domain> is served too, and redirects to the domain.
STATIC_SITE_WITH_WWW = {{inputs.with_www}}
# The command, run in site/, that builds the site; empty for files uploaded as
# they are.
STATIC_SITE_BUILD = {{inputs.build}}
# The built site, relative to site/.
STATIC_SITE_OUTPUT = {{inputs.output}}
# Directories under the output whose file names change with their contents,
# such as assets for Vite, separated by spaces. They are cached for a year;
# everything else is checked on each request.
STATIC_SITE_IMMUTABLE =
STATIC_SITE_PORT = {{inputs.port}}
STATIC_SITE_PROFILE = {{inputs.aws_profile}}
STATIC_SITE_PRICE_CLASS = {{inputs.price_class}}
# Targets each build runs first, such as a check of the site's data.
STATIC_SITE_BUILD_PREREQUISITES =
# Targets `make site deploy` also runs first.
STATIC_SITE_DEPLOY_PREREQUISITES =

NAMESPACES += site
TEMPLATES_FRAGMENTS += $(TEMPLATES_MAKE)/static-site.mk

include $(TEMPLATES_MAKE)/static-site.mk

.PHONY: site-build site-serve site-endserve site-deploy site-bust-cache site-invalidations site-stack site-status

## site-build: build the site into site/{{inputs.output}}
site-build: static-site-build

## site-serve: serve the built site at http://localhost:{{inputs.port}} and open it
site-serve: static-site-serve

## site-endserve: stop the served site
site-endserve: static-site-endserve

## site-deploy: upload the built site, clear CloudFront, then stamp and commit what is live
site-deploy: static-site-deploy

## site-bust-cache: clear PATHS="/ /index.html" from CloudFront
site-bust-cache: static-site-bust-cache

## site-invalidations: list the recent CloudFront invalidations
site-invalidations: static-site-invalidations

## site-stack: make or update the bucket, certificate, distribution and DNS records
site-stack: static-site-stack

## site-status: show the hosting and the commit that is live
site-status: static-site-status
