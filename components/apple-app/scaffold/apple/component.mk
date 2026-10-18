# The apple-app component's targets, for the app in this directory. The root
# Makefile includes this file; the fragment comes from armcknight/templatr at
# TEMPLATES_TAG.
#
# `make apple <command>` runs apple-<command>, such as `make apple test`.
#
# `make apple deploy-beta` uploads a build to TestFlight. Only the owner runs it,
# and `make apple patch`, `minor` and `major`.

APPLE_APP_DIR = apple
APPLE_APP_PLATFORM = {{inputs.platform}}
# Relative to apple/.
APPLE_APP_XCCONFIG = {{inputs.xcconfig}}
# Targets each build runs first.
APPLE_APP_BUILD_PREREQUISITES = apple-generate
# Targets `make apple deploy-beta` also runs first, such as a schema check.
APPLE_APP_DEPLOY_PREREQUISITES =

NAMESPACES += apple
TEMPLATES_FRAGMENTS += $(TEMPLATES_MAKE)/apple-app.mk

include $(TEMPLATES_MAKE)/apple-app.mk

.PHONY: apple-test apple-stage apple-deploy-beta apple-patch apple-minor apple-major apple-generate

## apple-generate: run Arkana and XcodeGen, when the app uses them
apple-generate:
	cd apple && if [ -f .arkana.yml ]; then bundle exec arkana; fi
	cd apple && if [ -f project.yml ]; then xcodegen; fi

## apple-test: run the tests
apple-test: apple-app-test

## apple-stage: build an ad-hoc staging IPA
apple-stage: apple-app-stage

## apple-deploy-beta: cut a release candidate and upload it to TestFlight
apple-deploy-beta: apple-app-deploy-beta

## apple-patch: raise the patch version and commit
apple-patch: apple-app-patch

## apple-minor: raise the minor version and commit
apple-minor: apple-app-minor

## apple-major: raise the major version and commit
apple-major: apple-app-major
