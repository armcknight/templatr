# Releases of the templatr command. The components have their own releases,
# the `v*` tags in the README's Releases section, which these targets do not
# make.
#
# `make patch`, `minor` or `major` bumps the version in VERSION_FILE with vrsn
# and commits it. Then `make deploy` runs prepare-release, which moves the
# CHANGELOG's [Unreleased] section into a dated section for the version,
# commits, tags the commit with the version, such as `0.1.0`, pushes, and makes
# a GitHub release with that section as its notes. `make deploy-beta` does the
# same for a release candidate, such as `0.1.0-RC1`, marked as a prerelease.
# prepare-release numbers it from the RC sections at the top of the CHANGELOG,
# so running it again makes RC2 without a new bump.
#
# vrsn and prepare-release come from the armcknight/tools cask.

VERSION_FILE = Sources/TemplatrCLI/Version.swift
VRSN_KEY     = version

.DEFAULT_GOAL = help
.PHONY: help build test validate patch minor major deploy deploy-beta

# Targets document themselves with a `## name: description` line above them,
# which is the only thing this prints. Only the first colon separates the two,
# so a description may contain further colons.
## help: list these targets
help:
	@awk '/^## /{ t = substr($$0, 4); c = index(t, ":"); printf "  make %-12s %s\n", substr(t, 1, c - 1), substr(t, c + 2) }' $(MAKEFILE_LIST)

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
