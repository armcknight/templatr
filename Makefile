# Two families of release targets, one for each kind of release in the
# README's Releases section.
#
# The templatr command: `make cli patch`, `minor`, `major`, `deploy` and
# `deploy-beta`, from the swift-cli component's fragment, which
# cli/component.mk includes. This repository is bootstrapped with its own
# component. `make cli patch`, `minor` or `major` bumps the version in
# Sources/TemplatrCLI/Version.swift with vrsn and commits it. Then `make cli
# deploy` runs prepare-release, which moves the CHANGELOG's [Unreleased]
# section into a dated section for the version, commits, tags the commit with
# the version, such as `0.1.0`, pushes, and makes a GitHub release with that
# section as its notes. `make cli deploy-beta` does the same for a release
# candidate, such as `0.1.0-RC1`, marked as a prerelease. prepare-release
# numbers it from the RC sections at the top of the CHANGELOG, so running it
# again makes RC2 without a new bump. `make cli build`, `test`, `install` and
# `uninstall` come from the same fragment.
#
# The templates, which are the components, the make/*.mk fragments and the
# shared Fastfile that projects fetch at a tag: `templates-patch`,
# `templates-minor`, `templates-major`, `templates-deploy`,
# `templates-deploy-beta`, below. They do the same with components/VERSION and
# components/CHANGELOG.md, and tag with a `v` prefix, such as `v1.1.0` or
# `v1.1.0-RC1`. They only tag and push: .github/workflows/release.yml then makes
# the GitHub release and moves the major alias, such as `v1`, that projects are
# pinned to. A release candidate is for trying a lane or a fragment on one
# project before every project pinned to the alias gets it. Only a change that
# a project must act on is `templates-major`.
#
# vrsn and prepare-release come from the armcknight/tools cask: `make init`
# installs it with the rest of the Brewfile.
#
# No target here may share its name with a `make cli <command>`: the namespace
# rule below runs cli-<command>, and then make runs a root target of the same
# name as well.

# <!-- templatr:begin base -->
# # The project's Makefile. Each component's targets are in its directory's
# component.mk, such as server/component.mk or apple/component.mk, which this
# file includes. Their Makefile fragments come from armcknight/templatr at
# TEMPLATES_TAG: each is downloaded on first use, and `make templates-update`
# downloads them again, as after changing the tag.
#
# Commands are namespaced: `make server deploy` runs the server-deploy target,
# and `make apple ios test` runs apple-ios-test. The direct form, `make
# server-deploy`, works too. `make help` lists them.

TEMPLATES_TAG = v3
TEMPLATES_MAKE = .templatr/make

# Each component.mk adds its namespace, such as server, and the fragments it
# includes.
NAMESPACES :=
TEMPLATES_FRAGMENTS :=

.DEFAULT_GOAL = help
.PHONY: help templates-update

include $(sort $(wildcard */component.mk))

# `make <namespace> <command>` runs `<namespace>-<command>`, and the words after
# the namespace do nothing by themselves. A command can be more than one word,
# joined with dashes: `make apple ios test` runs `apple-ios-test`. A namespace
# with no command lists the targets.
ifneq ($(filter $(firstword $(MAKECMDGOALS)),$(NAMESPACES)),)
NS  := $(firstword $(MAKECMDGOALS))
EMPTY :=
SPACE := $(EMPTY) $(EMPTY)
CMD := $(subst $(SPACE),-,$(strip $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))))
.PHONY: $(NS)
$(NS):
	@$(MAKE) --no-print-directory $(if $(strip $(CMD)),$(NS)-$(CMD),help)
%:
	@:
endif

$(TEMPLATES_MAKE)/%.mk:
	mkdir -p $(@D)
	curl -fsSL https://raw.githubusercontent.com/armcknight/templatr/$(TEMPLATES_TAG)/make/$*.mk -o $@

## help: list these targets
help:
	@awk '/^## /{ t = substr($$0, 4); c = index(t, ":"); printf "  make %-28s %s\n", substr(t, 1, c - 1), substr(t, c + 2) }' $(filter-out $(TEMPLATES_MAKE)/%,$(MAKEFILE_LIST))

## templates-update: download the Makefile fragments again at TEMPLATES_TAG
templates-update:
	rm -rf $(TEMPLATES_MAKE)
	$(if $(strip $(TEMPLATES_FRAGMENTS)),$(MAKE) $(TEMPLATES_FRAGMENTS))
# <!-- templatr:end -->

TEMPLATES_VERSION_FILE = components/VERSION
TEMPLATES_CHANGELOG    = components/CHANGELOG.md

.PHONY: init match-certificates-test validate links \
	templates-patch templates-minor templates-major templates-deploy templates-deploy-beta

# Both taps are third-party, and Homebrew refuses to load formulae or casks from
# an untrusted tap. `brew bundle` aborts on the first one it meets and installs
# nothing at all, including the entries after it, so trust precedes the bundle.
# All three commands are idempotent: `work start` runs this in every new
# worktree, so it has to stay that way.
## init: trust the taps and install everything in the Brewfile
init:
	@command -v brew >/dev/null 2>&1 || { echo "Homebrew is required: https://brew.sh"; exit 1; }
	brew trust --tap armcknight/tools
	brew trust --tap dorkitude/linctl
	brew bundle --file=Brewfile

# `make cli test` runs the command's tests. This second package is the
# apple-app component's, which CI tests in its own job.
## match-certificates-test: run the apple-app component's match-certificates package's tests
match-certificates-test:
	swift test --package-path components/apple-app/match-certificates

## validate: check the component manifests
validate:
	swift run validate-components

# The same check as CI's links job.
# The token raises GitHub's rate limit for the many github.com links.
## links: check the links in every Markdown file, as CI does
links:
	GITHUB_TOKEN="$$(gh auth token 2>/dev/null)" lychee --no-progress --include-fragments './**/*.md'

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
