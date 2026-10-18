# The apple-app component's Makefile targets. A project's ios/component.mk
# includes this file, downloaded at its pinned tag, and maps `make ios
# <command>` to them; the root Makefile includes ios/component.mk. The targets
# are namespaced so that the project's own `ios-test`, `ios-stage` and
# `ios-deploy-beta` can depend on them, or do more. They run fastlane,
# prepare-release and vrsn in APPLE_APP_DIR, so the changelog that
# prepare-release reads and the shared beta lane's "What to Test" text are both
# APPLE_APP_DIR/CHANGELOG.md.
#
# Set these before the include, as make reads a rule's prerequisites when it
# reads the rule:
#
#   APPLE_APP_DIR                   the directory with the Xcode project, the Gemfile and fastlane/
#   APPLE_APP_XCCONFIG              the xcconfig with MARKETING_VERSION and CURRENT_PROJECT_VERSION, relative to APPLE_APP_DIR
#   APPLE_APP_BUILD_PREREQUISITES   targets each build runs first, such as one that runs XcodeGen
#   APPLE_APP_DEPLOY_PREREQUISITES  targets apple-app-deploy-beta also runs first, such as a schema check
#
# prepare-release and vrsn come from the armcknight/tools cask.

APPLE_APP_DIR ?= .
APPLE_APP_PLATFORM ?= ios
APPLE_APP_XCCONFIG ?=
APPLE_APP_BUILD_PREREQUISITES ?=
APPLE_APP_DEPLOY_PREREQUISITES ?=
FASTLANE ?= bundle exec fastlane

.PHONY: apple-app-test apple-app-stage apple-app-deploy-beta apple-app-patch apple-app-minor apple-app-major apple-app-xcconfig

## apple-app-test: run the tests through the shared fastlane lane
apple-app-test: $(APPLE_APP_BUILD_PREREQUISITES)
	cd $(APPLE_APP_DIR) && $(FASTLANE) $(APPLE_APP_PLATFORM) test

## apple-app-stage: build an ad-hoc staging IPA through the shared fastlane lane (iOS only)
apple-app-stage: $(APPLE_APP_BUILD_PREREQUISITES)
	cd $(APPLE_APP_DIR) && $(FASTLANE) ios stage

# prepare-release moves CHANGELOG.md's Unreleased entries under the release
# candidate's version, raises CURRENT_PROJECT_VERSION in the xcconfig, commits,
# tags, pushes and makes a GitHub prerelease. The beta lane then uploads that
# commit to TestFlight, with the new entry as "What to Test". The log is named
# with the build number.
## apple-app-deploy-beta: cut a release candidate and upload it to TestFlight; only the owner runs it
apple-app-deploy-beta: apple-app-xcconfig $(APPLE_APP_BUILD_PREREQUISITES) $(APPLE_APP_DEPLOY_PREREQUISITES)
	@cd $(APPLE_APP_DIR) || exit 1; set -o pipefail; { \
	  prepare-release rc --file $(APPLE_APP_XCCONFIG) --key MARKETING_VERSION --build-number-key CURRENT_PROJECT_VERSION --push --github-release --prerelease && \
	  $(FASTLANE) $(APPLE_APP_PLATFORM) beta; \
	} 2>&1 | tee deploy-beta.log; \
	status=$$?; \
	BUILD=$$(grep -Eo 'CURRENT_PROJECT_VERSION[[:space:]]*=[[:space:]]*[0-9]+' $(APPLE_APP_XCCONFIG) | grep -Eo '[0-9]+$$'); \
	mv -f deploy-beta.log "deploy-beta-$$BUILD.log"; \
	exit $$status

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
