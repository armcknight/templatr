# {{inputs.name}}

The command line tool's Swift package is at the repository's root, with its `CHANGELOG.md`. This directory has the swift-cli component's `component.mk` and `Brewfile`.

Run these from the repository's root:

* `make cli init` installs the tools that these commands use, from `cli/Brewfile`.
* `make cli build` builds it, and `make cli test` runs its tests.
* `make cli install` builds it with the commit in its version, such as `0.1.0+d0a4bc2`, with `.dirty` when the working tree has changes, and copies it where `which {{inputs.name}}` finds it. `make cli uninstall` removes that build.
* `make cli patch`, `make cli minor` and `make cli major` bump the version in `{{inputs.version_file}}` and commit it.
* `make cli deploy` moves the changelog's Unreleased section into a section for the version, tags the version and pushes, and the release workflow releases it. `make cli deploy-beta` does the same for a release candidate. Only the owner releases.
