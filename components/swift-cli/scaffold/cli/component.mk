# The swift-cli component's targets, for the command line tool whose Swift
# package is at the repository's root. The root Makefile includes this file;
# the fragment comes from armcknight/templatr at TEMPLATES_TAG.
#
# `make cli <command>` runs cli-<command>, such as `make cli install`.
#
# `make cli deploy` releases the tool. Only the owner runs it.

SWIFT_CLI_NAME = {{inputs.name}}
SWIFT_CLI_BINARIES = {{inputs.binaries}}
SWIFT_CLI_VERSION_FILE = {{inputs.version_file}}
SWIFT_CLI_VRSN_KEY = {{inputs.vrsn_key}}
SWIFT_CLI_DISTRIBUTION = {{inputs.distribution}}
SWIFT_CLI_CASK = {{inputs.cask}}
SWIFT_CLI_DIR = cli

NAMESPACES += cli
TEMPLATES_FRAGMENTS += $(TEMPLATES_MAKE)/swift-cli.mk

include $(TEMPLATES_MAKE)/swift-cli.mk

.PHONY: cli-init cli-build cli-test cli-install cli-uninstall cli-patch cli-minor cli-major cli-deploy cli-deploy-beta

## cli-init: trust the taps and install cli/Brewfile
cli-init: swift-cli-init

## cli-build: build the release binaries
cli-build: swift-cli-build

## cli-test: run the tests
cli-test: swift-cli-test

## cli-install: build with the commit in the version, and install it
cli-install: swift-cli-install

## cli-uninstall: remove that build, and restore the cask's
cli-uninstall: swift-cli-uninstall

## cli-patch: bump the patch version and commit (also: cli-minor, cli-major)
cli-patch: swift-cli-patch

cli-minor: swift-cli-minor

cli-major: swift-cli-major

## cli-deploy: migrate the changelog, tag the version and push, which releases it
cli-deploy: swift-cli-deploy

## cli-deploy-beta: same, for a release candidate
cli-deploy-beta: swift-cli-deploy-beta
