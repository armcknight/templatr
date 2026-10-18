# Two families of release targets, one for each kind of release in the
# README's Releases section.
#
# The templatr command: `patch`, `minor`, `major`, `deploy`, `deploy-beta`.
# `make patch`, `minor` or `major` bumps the version in VERSION_FILE with vrsn
# and commits it. Then `make deploy` runs prepare-release, which moves the
# CHANGELOG's [Unreleased] section into a dated section for the version,
# commits, tags the commit with the version, such as `0.1.0`, pushes, and makes
# a GitHub release with that section as its notes. `make deploy-beta` does the
# same for a release candidate, such as `0.1.0-RC1`, marked as a prerelease.
# prepare-release numbers it from the RC sections at the top of the CHANGELOG,
# so running it again makes RC2 without a new bump.
#
# The templates, which are the components, the make/*.mk fragments and the
# shared Fastfile that projects fetch at a tag: `templates-patch`,
# `templates-minor`, `templates-major`, `templates-deploy`,
# `templates-deploy-beta`. They do the same with components/VERSION and
# components/CHANGELOG.md, and tag with a `v` prefix, such as `v1.1.0` or
# `v1.1.0-RC1`. They only tag and push: .github/workflows/release.yml then makes
# the GitHub release and moves the major alias, such as `v1`, that projects are
# pinned to. A release candidate is for trying a lane or a fragment on one
# project before every project pinned to the alias gets it. Only a change that
# a project must act on is `templates-major`.
#
# vrsn and prepare-release come from the armcknight/tools cask.

VERSION_FILE = Sources/TemplatrCLI/Version.swift
VRSN_KEY     = version

TEMPLATES_VERSION_FILE = components/VERSION
TEMPLATES_CHANGELOG    = components/CHANGELOG.md

.DEFAULT_GOAL = help
.PHONY: help build test validate patch minor major deploy deploy-beta \
	templates-patch templates-minor templates-major templates-deploy templates-deploy-beta

# Targets document themselves with a `## name: description` line above them,
# which is the only thing this prints. Only the first colon separates the two,
# so a description may contain further colons.
## help: list these targets
help:
	@awk '/^## /{ t = substr($$0, 4); c = index(t, ":"); printf "  make %-22s %s\n", substr(t, 1, c - 1), substr(t, c + 2) }' $(MAKEFILE_LIST)

## build: build the release binaries
build:
	swift build -c release

## test: run the unit tests, and the apple-app component's match-certificates package's
test:
	swift test
	swift test --package-path components/apple-app/match-certificates

## validate: check the component manifests
validate:
	swift run validate-components

## patch: bump the patch version (x.y.Z) and commit (also: minor, major)
patch:
	vrsn patch -f $(VERSION_FILE) -k $(VRSN_KEY) --commit

minor:
	vrsn minor -f $(VERSION_FILE) -k $(VRSN_KEY) --commit

major:
	vrsn major -f $(VERSION_FILE) -k $(VRSN_KEY) --commit

## deploy: migrate the changelog, tag, push, and make the GitHub release
deploy:
	prepare-release --file $(VERSION_FILE) --key $(VRSN_KEY) --push --github-release

## deploy-beta: same, but for a release candidate, as a prerelease
deploy-beta:
	prepare-release rc --file $(VERSION_FILE) --key $(VRSN_KEY) --push --github-release --prerelease

## templates-patch: bump the templates' patch version in components/VERSION and commit (also: templates-minor, templates-major)
templates-patch:
	vrsn patch -f $(TEMPLATES_VERSION_FILE) --commit

templates-minor:
	vrsn minor -f $(TEMPLATES_VERSION_FILE) --commit

templates-major:
	vrsn major -f $(TEMPLATES_VERSION_FILE) --commit

## templates-deploy: migrate components/CHANGELOG.md, tag v<version> and push; release.yml makes the release and moves v<major>
templates-deploy:
	prepare-release --file $(TEMPLATES_VERSION_FILE) --changelog $(TEMPLATES_CHANGELOG) --tag-prefix v --push

## templates-deploy-beta: same, but for a release candidate, as a prerelease, without moving v<major>
templates-deploy-beta:
	prepare-release rc --file $(TEMPLATES_VERSION_FILE) --changelog $(TEMPLATES_CHANGELOG) --tag-prefix v --push
