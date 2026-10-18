# The apple-app component's targets, for the app in this directory. The root
# Makefile includes this file; the fragment comes from armcknight/templatr at
# TEMPLATES_TAG.
#
# `make {{directory}} <command>` runs {{directory}}-<command>, such as `make {{directory}} test`.
#
# `make {{directory}} deploy-beta` uploads a build to TestFlight. Only the owner runs it,
# and `make {{directory}} patch`, `minor` and `major`.

APPLE_APP_DIR = {{directory}}
APPLE_APP_PLATFORM = {{inputs.platform}}
# Relative to {{directory}}/.
APPLE_APP_XCCONFIG = {{inputs.xcconfig}}
# Targets each build runs first.
APPLE_APP_BUILD_PREREQUISITES = {{directory}}-generate
# Targets `make {{directory}} deploy-beta` also runs first, such as a schema check.
APPLE_APP_DEPLOY_PREREQUISITES =

NAMESPACES += {{directory}}
TEMPLATES_FRAGMENTS += $(TEMPLATES_MAKE)/apple-app.mk

include $(TEMPLATES_MAKE)/apple-app.mk

.PHONY: {{directory}}-test {{directory}}-stage {{directory}}-deploy-beta {{directory}}-patch {{directory}}-minor {{directory}}-major {{directory}}-generate

## {{directory}}-generate: run Arkana and XcodeGen, when the app uses them
{{directory}}-generate:
	cd {{directory}} && if [ -f .arkana.yml ]; then bundle exec arkana; fi
	cd {{directory}} && if [ -f project.yml ]; then xcodegen; fi

## {{directory}}-test: run the tests
{{directory}}-test: apple-app-test

## {{directory}}-stage: build an ad-hoc staging IPA
{{directory}}-stage: apple-app-stage

## {{directory}}-deploy-beta: cut a release candidate and upload it to TestFlight
{{directory}}-deploy-beta: apple-app-deploy-beta

## {{directory}}-patch: raise the patch version and commit
{{directory}}-patch: apple-app-patch

## {{directory}}-minor: raise the minor version and commit
{{directory}}-minor: apple-app-minor

## {{directory}}-major: raise the major version and commit
{{directory}}-major: apple-app-major
