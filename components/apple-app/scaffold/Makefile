# The apple-app component's targets come from armcknight/templates at
# TEMPLATES_TAG. The fragment is downloaded on first use; `make templates-update`
# downloads it again, as after changing the tag.
#
# `make deploy-beta` uploads a build to TestFlight. Only the owner runs it, and
# `make patch`, `minor` and `major`.

TEMPLATES_TAG = {{templates.tag}}
APPLE_APP_PLATFORM = {{inputs.platform}}
APPLE_APP_XCCONFIG = {{inputs.xcconfig}}
# Targets each build runs first.
APPLE_APP_BUILD_PREREQUISITES = generate
# Targets `make deploy-beta` also runs first, such as a schema check.
APPLE_APP_DEPLOY_PREREQUISITES =

TEMPLATES_MAKE = .superlinear/make

.DEFAULT_GOAL = test
.PHONY: test stage deploy-beta patch minor major generate templates-update

include $(TEMPLATES_MAKE)/apple-app.mk

$(TEMPLATES_MAKE)/%.mk:
	mkdir -p $(@D)
	curl -fsSL https://raw.githubusercontent.com/armcknight/templates/$(TEMPLATES_TAG)/make/$*.mk -o $@

## templates-update: download the Makefile fragments again at TEMPLATES_TAG
templates-update:
	rm -rf $(TEMPLATES_MAKE)
	$(MAKE) $(TEMPLATES_MAKE)/apple-app.mk

## generate: run Arkana and XcodeGen, when the project uses them
generate:
	if [ -f .arkana.yml ]; then bundle exec arkana; fi
	if [ -f project.yml ]; then xcodegen; fi

## test: run the tests
test: apple-app-test

## stage: build an ad-hoc staging IPA
stage: apple-app-stage

## deploy-beta: cut a release candidate and upload it to TestFlight
deploy-beta: apple-app-deploy-beta

## patch: raise the patch version and commit
patch: apple-app-patch

## minor: raise the minor version and commit
minor: apple-app-minor

## major: raise the major version and commit
major: apple-app-major
