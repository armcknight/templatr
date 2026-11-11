# swift-cli

This project is a command line tool built with the Swift Package Manager, with the `swift-cli` component from [armcknight/templatr](https://github.com/armcknight/templatr). `.templatr.toml` has the tag it is pinned to.

The Swift package is at the repository's root, with `CHANGELOG.md`. The component's `component.mk`, `README.md` and `Brewfile` are in `cli/`. Run `swift` commands and the `make cli …` commands at the root.

## Building and testing

* `make cli build` builds the release binaries, and `make cli test` runs the tests. CI builds and tests the package on macOS on each pull request, through `swift-package-ci.yml` from [armcknight/workflows](https://github.com/armcknight/workflows).
* `make cli install` builds with the commit in the version, such as `1.2.0+d0a4bc2.dirty`, and installs the build. `make cli uninstall` removes it.

## The version

* The version is on one line of the version file in `cli/component.mk`'s `SWIFT_CLI_VERSION_FILE`, such as `static let version = "1.2.0"`. vrsn finds the line by its name: do not rename it, and do not put another line with that name and ` = ` before it.
* `--version` prints `fullVersion`, the version with the build metadata of `make cli install` appended. `BuildMetadata.generated.swift` is written by `make cli install` and ignored by git: never commit it.
* Add each change that a user can see to the `[Unreleased]` section of `CHANGELOG.md`, under Added, Changed, Fixed or Removed. `make cli deploy` moves that section into the release's.

## Rules

* Never release. Do not run `make cli patch`, `minor`, `major`, `deploy` or `deploy-beta`, `vrsn`, `prepare-release`, or push a version tag. Only the owner releases, and a tag starts the release workflow.
* The CI and release workflows, `.github/workflows/swift-cli-*.yml` or the project's own, call armcknight/workflows at its major tag. Do not point them at `main`.
* The `swift-cli-*` targets come from the templatr repository; `cli/component.mk` includes them from `make/swift-cli.mk`, and the root Makefile includes `cli/component.mk`. Do not copy them into this project. To change them, change the templatr repository and move this project to its new tag.
* Never print, log or commit a secret's value. The secrets are named in the "How this project is built" section of the root `README.md`.

## Further reading

* [CI](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#ci)
* [The release rule](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#release-rule)
* [Secrets](https://github.com/armcknight/superlinear/blob/main/docs/bootstrap.md#secrets)
