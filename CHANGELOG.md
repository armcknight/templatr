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
