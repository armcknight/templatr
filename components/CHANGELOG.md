# Changelog

All notable changes to the templates are documented in this file: the
components, the `make/*.mk` fragments and the shared Fastfile, which projects
fetch at a `v*` tag. Their releases are tagged `v1.0.0`, `v1.1.0` and so on,
and projects pin the major alias, such as `v1`; see
[Releases](../README.md#releases). The `templatr` command's changes are in
[CHANGELOG.md](../CHANGELOG.md).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The `apple-app` component's `ASC_ADMIN_KEY_ID`, `ASC_ADMIN_ISSUER_ID` and
  `ASC_ADMIN_KEY_P8_BASE64` local secrets: the App Store Connect API key with
  the Admin role, which match needs to make or renew certificates and
  profiles. `templatr check` reports them as missing until they are in the
  Keychain.

## [v1.0.0] 2026-10-18

### Added

- The `base` component: the project's root Makefile, which includes each
  component's targets and downloads the `make/*.mk` fragments at
  `TEMPLATES_TAG`, and the root README.md that links to each component's README.
- The `apple-app` component: an app for iOS (with an optional embedded watch
  app), tvOS, macOS or more than one of them, from one Xcode project in
  `apple/`, with an XcodeGen spec for a new app, the shared `test`, `beta` and
  `stage` lanes in `fastlane/Fastfile`, the `make/apple-app.mk` targets, tests
  on each pull request, staging builds on demand, and the expiry dates of its
  signing certificates and profiles.
- The `github-repo` component: a repository on GitHub whose pull requests are
  squashed when they merge, with their branches deleted, and whose default
  branch cannot be deleted or force-pushed except by the owner.
- The `linear-workspace` component: a Linear workspace that superlinear works
  from, with its states, Triage, labels, proposals view and initiatives.
- The `vapor-fly` component: a Swift server in `server/`, built with Vapor and
  run on Fly.io, built and tested on Linux on each pull request, and deployed
  by hand or on a merge, with the `make/vapor-fly.mk` targets.
- The `supabase` component: a Postgres database on Supabase for a Vapor server
  on Fly.io, with local and test databases, Supabase's root CA in the server's
  image, a local and remote parity check, migrations, and the
  `make/supabase.mk` targets.
