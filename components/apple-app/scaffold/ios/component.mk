# The apple-app component's targets, for the app in this directory. The root
# Makefile includes this file; the fragment comes from armcknight/templatr at
# TEMPLATES_TAG.
#
# `make ios <command>` runs ios-<command>, such as `make ios test`.
#
# `make ios deploy-beta` uploads a build to TestFlight. Only the owner runs it,
# and `make ios patch`, `minor` and `major`.

APPLE_APP_DIR = ios
APPLE_APP_PLATFORM = {{inputs.platform}}
# Relative to ios/.
APPLE_APP_XCCONFIG = {{inputs.xcconfig}}
# Targets each build runs first.
APPLE_APP_BUILD_PREREQUISITES = ios-generate
# Targets `make ios deploy-beta` also runs first, such as a schema check.
APPLE_APP_DEPLOY_PREREQUISITES =

NAMESPACES += ios
TEMPLATES_FRAGMENTS += $(TEMPLATES_MAKE)/apple-app.mk

include $(TEMPLATES_MAKE)/apple-app.mk

.PHONY: ios-test ios-stage ios-deploy-beta ios-patch ios-minor ios-major ios-generate

## ios-generate: run Arkana and XcodeGen, when the app uses them
ios-generate:
	cd ios && if [ -f .arkana.yml ]; then bundle exec arkana; fi
	cd ios && if [ -f project.yml ]; then xcodegen; fi

## ios-test: run the tests
ios-test: apple-app-test

## ios-stage: build an ad-hoc staging IPA
ios-stage: apple-app-stage

## ios-deploy-beta: cut a release candidate and upload it to TestFlight
ios-deploy-beta: apple-app-deploy-beta

## ios-patch: raise the patch version and commit
ios-patch: apple-app-patch

## ios-minor: raise the minor version and commit
ios-minor: apple-app-minor

## ios-major: raise the major version and commit
ios-major: apple-app-major
