# The apple-app component's targets, for the app in this directory. The root
# Makefile includes this file; the fragment comes from armcknight/templatr at
# TEMPLATES_TAG.
#
# The one Xcode project here builds the app for each platform in
# APPLE_APP_PLATFORMS. `make apple <platform> <command>` runs
# apple-<platform>-<command> for that platform, such as `make apple ios test` or
# `make apple mac deploy-beta`. `make apple <command>` runs apple-<command>, such
# as `make apple test`, which tests every platform.
#
# `make apple deploy-beta` and `make apple <platform> deploy-beta` upload a build
# to TestFlight. Only the owner runs them, and `make apple patch`, `minor` and
# `major`.

APPLE_APP_DIR = apple
# The platforms, as fastlane names them: ios, tvos and mac.
APPLE_APP_PLATFORMS = {{inputs.platforms}}
# Relative to apple/.
APPLE_APP_XCCONFIG = {{inputs.xcconfig}}
# Targets each build runs first.
APPLE_APP_BUILD_PREREQUISITES = apple-generate
# Targets a deploy-beta target also runs first, such as a schema check.
APPLE_APP_DEPLOY_PREREQUISITES =

NAMESPACES += apple
TEMPLATES_FRAGMENTS += $(TEMPLATES_MAKE)/apple-app.mk

include $(TEMPLATES_MAKE)/apple-app.mk

.PHONY: apple-test apple-deploy-beta apple-patch apple-minor apple-major apple-generate

## apple-generate: run Arkana and XcodeGen, when the app uses them
apple-generate:
	cd apple && if [ -f .arkana.yml ]; then bundle exec arkana; fi
	cd apple && if [ -f project.yml ]; then xcodegen; fi

## apple-test: run the tests for every platform
apple-test: apple-app-test

## apple-deploy-beta: cut a release candidate and upload it to TestFlight for every platform
apple-deploy-beta: apple-app-deploy-beta

## apple-<platform>-test: run the tests for one platform, such as `make apple ios test`
## apple-<platform>-deploy-beta: cut a release candidate and upload it to TestFlight for one platform
$(foreach p,$(APPLE_APP_PLATFORMS),$(eval .PHONY: apple-$(p)-test apple-$(p)-deploy-beta)$(eval apple-$(p)-test: apple-app-$(p)-test)$(eval apple-$(p)-deploy-beta: apple-app-$(p)-deploy-beta))

## apple-ios-stage: build an ad-hoc staging IPA, for ios only
ifneq ($(filter ios,$(APPLE_APP_PLATFORMS)),)
.PHONY: apple-ios-stage
apple-ios-stage: apple-app-ios-stage
endif

## apple-patch: raise the patch version and commit
apple-patch: apple-app-patch

## apple-minor: raise the minor version and commit
apple-minor: apple-app-minor

## apple-major: raise the major version and commit
apple-major: apple-app-major
