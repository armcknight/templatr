# Changelog

All notable changes to the `templatr` command are documented in this file. The
components have their own releases; see [Releases](README.md#releases).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.1.0] 2026-11-06

### Added

- `templatr` is a Homebrew cask in armcknight/homebrew-tools:
  `brew install --cask armcknight/tools/templatr`. Each release tag builds the
  binary and bumps the cask through armcknight/workflows'
  `swiftpm-cask-release.yml`. The cask's `templatr` keeps a clone of this
  repository in `~/Library/Application Support/templatr/templates`, made on
  first use, with its tags fetched on each run, and checked out at the newest
  alias, so the components it reads are a release's; `--templates` and `--tag`
  choose another checkout or release. A build from a checkout, with
  `swift run` or `make install`, uses that checkout as before.
- `make uninstall` removes the dev build from `~/.local/bin`, so that the
  cask's `templatr` runs again.

## [2.0.0] 2026-11-06

### Changed

- `bin/store-secrets` is now the subcommand `templatr store-secrets`, with the
  same flags, so it runs from the installed command in any directory, and no
  longer from a checkout of this repository. `--check` runs `templatr check`
  directly, not `swift run`. The apple-app and vapor-fly manifests' human
  texts name the subcommand with its flags.

### Removed

- `bin/store-secrets`.

## [1.1.0] 2026-11-06

### Added

- A manifest's secret or step can have `when`, such as
  `{ input = "migration_style", equals = "cli" }`: the component needs it only
  when the input has that value. With another value, `bootstrap` and `check`
  do not read, set, run or report it, and the README does not list it. The
  validator rejects a `when` whose input the component does not declare.
- `templatr bootstrap` and `check` take `--private` and `--no-private`: they
  set the github-repo component's `private` input, which `bootstrap` records
  in `.templatr.toml` and `check` uses for that run only. Without either, a
  repository is public, or keeps the recorded value.

### Fixed

- A component's step and certificate commands get the values of its `local`
  secrets that are in the Keychain, in their environment. Before, `templatr
  check` only looked for the Keychain items, so apple-app's `app-record` and
  `tester-group` checks ran without the App Store Connect API key, stopped
  with "Missing ASC_KEY_ID.", and were reported as steps for a person. A
  variable that the environment already has, such as one from `.envrc`, keeps
  its value. The values go only to the commands' environment, never to their
  arguments or a report.

## [1.0.0] 2026-11-06

### Added

- `templatr bootstrap` sets a project up from its components, and
  `templatr check` reports what it still needs.
- The Keychain items that `bootstrap` and `bin/store-secrets` write and read are
  named `templatr.<name>`, such as `templatr.asc.key-id`, and no longer
  `superlinear.<name>`.
- `templatr --version` prints the version.
- A manifest's `shared` pieces can be of the kind `template`, such as the
  static-site component's CloudFormation template.
- `{{inputs.<name>.compact}}` is an input's value without white space, for a
  name people see, such as `Bae Today`, where a file or an identifier needs
  `BaeToday`.
- `make install` builds with the git commit in the version: `templatr --version`
  prints `0.1.0+<commit>`, and `.dirty` when the working tree had changes. A
  release build prints the version alone.
- `make patch`, `minor` and `major` bump the version, and `make deploy` and
  `make deploy-beta` tag a release and make its GitHub release.
- A `detect` or `infer` rule with `root = true` reads from the repository root
  instead of the component's directory, so that a component can be detected
  and its inputs found from another part of the project.
- `bin/store-secrets` stores the App Store Connect API keys and the Fly deploy
  tokens in the Keychain, under the item names that the manifests give.
- A `build-setting` infer rule with `separator` reads a list setting, such as
  `SUPPORTED_PLATFORMS`: it maps each word, drops a value that is already in
  the list, and joins the values with `separator`.
- `templatr check` reports signing certificates, provisioning profiles and
  other files that expire within 30 days, from a manifest's optional
  `certificates`, whose `list` command prints each one with its expiry. The
  report's new `certificateExpiries` has them. The `apple-app` component lists
  the certificates and profiles in the fastlane match repository.
- An infer rule with `from = "command"` takes an input's value from what a
  shell command prints, for a value that is not in a file, such as one a
  service's API gives. It runs in the component's directory, or at the root
  with `root = true`, with the `templates` and `templates.tag` placeholders
  filled in.
- A manifest's optional `links` are links to the project's own pages for the
  component, such as its Linear workspace, with placeholders in their URLs.
  `bootstrap` writes them under "Further reading" in the README's section, and
  leaves out a link whose input has no value.
- The `supabase` component is detected from the root also, before its
  `supabase/` exists: from a `server/Package.swift` with
  `fluent-postgres-driver`, or a `.envrc.example` with a Supabase host. It
  infers `project_ref` from `.envrc.example`, `fly_app` from `server/fly.toml`,
  `product` from `server/Package.swift`, `ca_cert_path` from the certificate
  that `server/Dockerfile` copies, and `ca_cert_env` from `server/fly.toml`'s
  `[env]`.

### Changed

- `templatr check` and `bootstrap` read only the templates' major-version
  aliases, such as `v1`, and pin new components to the newest one; `--tag`
  still takes a full tag, such as `v1.0.1`. A component is behind when a newer
  alias exists, so `v1` is behind `v2` but not `v1.0.1`.
