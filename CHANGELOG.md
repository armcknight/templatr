# Changelog

All notable changes to the `templatr` command are documented in this file. The
components have their own releases; see [Releases](README.md#releases).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `templatr bootstrap` sets a project up from its components, and
  `templatr check` reports what it still needs.
- `templatr --version` prints the version.
- `make patch`, `minor` and `major` bump the version, and `make deploy` and
  `make deploy-beta` tag a release and make its GitHub release.
- A `detect` or `infer` rule with `root = true` reads from the repository root
  instead of the component's directory, so that a component can be detected
  and its inputs found from another part of the project.
- A `build-setting` infer rule with `separator` reads a list setting, such as
  `SUPPORTED_PLATFORMS`: it maps each word, drops a value that is already in
  the list, and joins the values with `separator`.
- `templatr check` reports signing certificates, provisioning profiles and
  other files that expire within 30 days, from a manifest's optional
  `certificates`, whose `list` command prints each one with its expiry. The
  report's new `certificateExpiries` has them. The `apple-app` component lists
  the certificates and profiles in the fastlane match repository.
- The `supabase` component is detected from the root also, before its
  `supabase/` exists: from a `server/Package.swift` with
  `fluent-postgres-driver`, or a `.envrc.example` with a Supabase host. It
  infers `project_ref` from `.envrc.example`, `fly_app` from `server/fly.toml`,
  `product` from `server/Package.swift`, `ca_cert_path` from the certificate
  that `server/Dockerfile` copies, and `ca_cert_env` from `server/fly.toml`'s
  `[env]`.
