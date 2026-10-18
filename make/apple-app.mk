# The apple-app component's Makefile targets. A project's apple/component.mk
# includes this file, downloaded at its pinned tag, and maps `make apple
# <command>` and `make apple <platform> <command>` to them; the root Makefile
# includes apple/component.mk. The targets are namespaced so that the project's
# own `apple-test`, `apple-ios-test` and the others can depend on them, or do
# more. They run fastlane, prepare-release and vrsn in APPLE_APP_DIR, so the
# changelog that prepare-release reads and the shared beta lane's "What to Test"
# text are both APPLE_APP_DIR/CHANGELOG.md.
#
# The one Xcode project in APPLE_APP_DIR can build the app for more than one
# platform. For each platform P in APPLE_APP_PLATFORMS, as fastlane names it
# (ios, tvos or mac), this file has apple-app-P-test and apple-app-P-deploy-beta,
# and apple-app-ios-stage for ios. apple-app-test and apple-app-deploy-beta do
# the same for every platform. The version targets are for all platforms, as
# they share the xcconfig.
#
# Set these before the include, as make reads a rule's prerequisites when it
# reads the rule:
#
#   APPLE_APP_DIR                   the directory with the Xcode project, the Gemfile and fastlane/
#   APPLE_APP_PLATFORMS             the platforms the app builds for, separated by spaces, such as `ios mac`
#   APPLE_APP_XCCONFIG              the xcconfig with MARKETING_VERSION and CURRENT_PROJECT_VERSION, relative to APPLE_APP_DIR
#   APPLE_APP_BUILD_PREREQUISITES   targets each build runs first, such as one that runs XcodeGen
#   APPLE_APP_DEPLOY_PREREQUISITES  targets a deploy-beta target also runs first, such as a schema check
#
# prepare-release and vrsn come from the armcknight/tools cask.

APPLE_APP_DIR ?= .
APPLE_APP_PLATFORMS ?= ios
APPLE_APP_XCCONFIG ?=
APPLE_APP_BUILD_PREREQUISITES ?=
APPLE_APP_DEPLOY_PREREQUISITES ?=
FASTLANE ?= bundle exec fastlane

# The platforms that a deploy-beta target uploads. Each apple-app-P-deploy-beta
# sets it to P.
APPLE_APP_DEPLOY_PLATFORMS = $(APPLE_APP_PLATFORMS)

.PHONY: apple-app-test apple-app-deploy-beta apple-app-patch apple-app-minor apple-app-major apple-app-xcconfig

## apple-app-test: run the tests for every platform through the shared fastlane lanes
apple-app-test: $(foreach p,$(APPLE_APP_PLATFORMS),apple-app-$(p)-test)

# prepare-release moves CHANGELOG.md's Unreleased entries under the release
# candidate's version, raises CURRENT_PROJECT_VERSION in the xcconfig, commits,
# tags, pushes and makes a GitHub prerelease. The beta lane of each platform in
# APPLE_APP_DEPLOY_PLATFORMS then uploads that commit to TestFlight, with the
# new entry as "What to Test". The log is named with the build number.
## apple-app-deploy-beta: cut a release candidate and upload it to TestFlight for every platform; only the owner runs it
apple-app-deploy-beta: apple-app-xcconfig $(APPLE_APP_BUILD_PREREQUISITES) $(APPLE_APP_DEPLOY_PREREQUISITES)
	@cd $(APPLE_APP_DIR) || exit 1; set -o pipefail; { \
	  prepare-release rc --file $(APPLE_APP_XCCONFIG) --key MARKETING_VERSION --build-number-key CURRENT_PROJECT_VERSION --push --github-release --prerelease && \
	  for platform in $(APPLE_APP_DEPLOY_PLATFORMS); do $(FASTLANE) $$platform beta || exit 1; done; \
	} 2>&1 | tee deploy-beta.log; \
	status=$$?; \
	BUILD=$$(grep -Eo 'CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*[0-9]+' $(APPLE_APP_XCCONFIG) | grep -Eo '[0-9]+$$'); \
	mv -f deploy-beta.log "deploy-beta-$$BUILD.log"; \
	exit $$status

# The targets for one platform, $(1).
define APPLE_APP_PLATFORM_TARGETS
.PHONY: apple-app-$(1)-test apple-app-$(1)-deploy-beta

apple-app-$(1)-test: $$(APPLE_APP_BUILD_PREREQUISITES)
	cd $$(APPLE_APP_DIR) && $$(FASTLANE) $(1) test

apple-app-$(1)-deploy-beta: APPLE_APP_DEPLOY_PLATFORMS = $(1)
apple-app-$(1)-deploy-beta: apple-app-deploy-beta
endef

$(foreach p,$(APPLE_APP_PLATFORMS),$(eval $(call APPLE_APP_PLATFORM_TARGETS,$(p))))

## apple-app-ios-stage: build an ad-hoc staging IPA through the shared fastlane lane (iOS only)
ifneq ($(filter ios,$(APPLE_APP_PLATFORMS)),)
.PHONY: apple-app-ios-stage
apple-app-ios-stage: $(APPLE_APP_BUILD_PREREQUISITES)
	cd $(APPLE_APP_DIR) && $(FASTLANE) ios stage
endif

## apple-app-patch: raise MARKETING_VERSION's patch number and commit
apple-app-patch: apple-app-xcconfig
	@cd $(APPLE_APP_DIR) && vrsn patch -f $(APPLE_APP_XCCONFIG) -k MARKETING_VERSION --commit

## apple-app-minor: raise MARKETING_VERSION's minor number and commit
apple-app-minor: apple-app-xcconfig
	@cd $(APPLE_APP_DIR) && vrsn minor -f $(APPLE_APP_XCCONFIG) -k MARKETING_VERSION --commit

## apple-app-major: raise MARKETING_VERSION's major number and commit
apple-app-major: apple-app-xcconfig
	@cd $(APPLE_APP_DIR) && vrsn major -f $(APPLE_APP_XCCONFIG) -k MARKETING_VERSION --commit

apple-app-xcconfig:
	@test -n "$(APPLE_APP_XCCONFIG)" || { echo "Set APPLE_APP_XCCONFIG to the xcconfig with MARKETING_VERSION." >&2; exit 1; }
