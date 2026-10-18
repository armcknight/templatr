# templatr

Components: reusable parts of a project, such as an Apple app, a Swift command-line tool, a Vapor server on Fly, or a Supabase database. Each one says how to recognize a project that uses it, what it needs to know about the project, which secrets it needs and where they come from, what to check and set up, and which shared workflows, lanes and Makefile fragments it uses.

Shared lanes and Makefile fragments are here. Reusable GitHub workflows are in [armcknight/workflows](https://github.com/armcknight/workflows), and the components' scaffolds call them.

[superlinear](https://github.com/armcknight/superlinear)'s `bootstrap` command reads the components and sets projects up with them. People can also follow a manifest by hand.

This repository holds no secrets: only their names and where to get them.

## Components

| Component | What it sets up |
| --- | --- |
| [apple-app](components/apple-app) | An iOS (with an optional embedded watch app), tvOS or macOS app, tested on each pull request, with staging builds on demand, and uploaded to TestFlight by hand with `make deploy-beta`. |
| [vapor-fly](components/vapor-fly) | A Swift server built with Vapor and run on Fly.io, built and tested on Linux on each pull request, and deployed by the owner, by hand with `make server deploy` or on a merge. |
| [supabase](components/supabase) | A Postgres database on Supabase for a Vapor server on Fly.io, with local and test databases, Supabase's root CA in the server's image, a local and remote parity check, and migrations with the Supabase CLI before each deploy or with Fluent when the server starts. |

## Layout

```
components/<name>/component.toml   the manifest
components/<name>/scaffold/        files copied one time into a project
components/<name>/CLAUDE.md        conventions for agents, included by projects
components/<name>/bin/             scripts the manifest's steps run
.github/workflows/ci.yml           this repository's own CI
fastlane/                          shared lanes, imported with import_from_git
make/                              Makefile fragments
schema/component.schema.json       the manifest's JSON Schema, for editors
Package.swift                      the ComponentManifest library and the validator
Sources/ComponentManifest/         the manifest's types and the checks
Sources/validate-components/       the validator command
Tests/ComponentManifestTests/      the validator's tests
```

## Releases

Releases are tags: `v1`, `v1.1`, `v2`. Projects refer to a tag — in `import_from_git(branch: "v1")` and `TEMPLATES_TAG = v1` — never to `main`. The workflows from armcknight/workflows are called at its major tag, such as `@4`, never `@main`. A change that a project must act on, such as a renamed input, a new required secret or a lane that behaves differently, takes a new major version.

## Shared pieces

| Piece | Kind | Used by | What it does |
| --- | --- | --- | --- |
| [fastlane/Fastfile](fastlane/Fastfile) | fastlane | apple-app | The `test` and `beta` lanes for `ios`, `tvos` and `mac`, and the `stage` lane for `ios`. |
| [armcknight/workflows: ios-ci.yml](https://github.com/armcknight/workflows/blob/4/.github/workflows/ios-ci.yml) | workflow | apple-app | Runs the `test` lane on each pull request, and on a `/build-staging` comment the `stage` lane, with an install link. |
| [armcknight/workflows: ota-refresh.yml](https://github.com/armcknight/workflows/blob/4/.github/workflows/ota-refresh.yml) | workflow | apple-app | Signs a staging build's install link again on a `/refresh-staging` comment, and asks for a new build when the old one is gone. |
| [armcknight/workflows: ota-cleanup.yml](https://github.com/armcknight/workflows/blob/4/.github/workflows/ota-cleanup.yml) | workflow | apple-app | Deletes a pull request's staging builds when it closes. |
| [make/apple-app.mk](make/apple-app.mk) | make | apple-app | The `apple-app-test`, `apple-app-stage`, `apple-app-deploy-beta`, `apple-app-patch`, `apple-app-minor` and `apple-app-major` targets. |
| [components/apple-app/scaffold/Brewfile](components/apple-app/scaffold/Brewfile) | brewfile | apple-app | The tools the lanes use. |
| [components/apple-app/bin/check-app-store-connect](components/apple-app/bin/check-app-store-connect) | script | apple-app | Checks the app record and its tester group in App Store Connect. |
| [components/apple-app/bin/check-shared-lanes](components/apple-app/bin/check-shared-lanes) | script | apple-app | Checks that `fastlane/Fastfile` uses the shared lanes. |
| [armcknight/workflows: vapor-ci.yml](https://github.com/armcknight/workflows/blob/4/.github/workflows/vapor-ci.yml) | workflow | vapor-fly | Builds and tests the package on Linux in the swift image on each pull request, and builds the Docker image. |
| [armcknight/workflows: fly-deploy.yml](https://github.com/armcknight/workflows/blob/4/.github/workflows/fly-deploy.yml) | workflow | vapor-fly | Deploys the default branch's tip to Fly with its `GIT_SHA`, by hand or on a merge, then waits for the health check to answer. |
| [make/vapor-fly.mk](make/vapor-fly.mk) | make | vapor-fly | The `vapor-fly-build`, `vapor-fly-serve`, `vapor-fly-serve-docker`, `vapor-fly-deploy` and `vapor-fly-status` targets, which the scaffold's Makefile runs as `make server <command>`. |
| [components/vapor-fly/scaffold/Brewfile](components/vapor-fly/scaffold/Brewfile) | brewfile | vapor-fly | The tools the Makefile targets use. |
| [components/vapor-fly/bin/check-fly-config](components/vapor-fly/bin/check-fly-config) | script | vapor-fly | Checks that `fly.toml` names the app, forces HTTPS, scales to zero and has the health check. |
| [components/vapor-fly/bin/check-fly-secrets](components/vapor-fly/bin/check-fly-secrets) | script | vapor-fly, supabase | Checks that the Fly app has each runtime secret, by name. |
| [make/supabase.mk](make/supabase.mk) | make | supabase | The `supabase-db-init`, `supabase-db-reset`, `supabase-db-migrate`, `supabase-db-test-start`, `supabase-db-test-stop`, `supabase-db-status`, `supabase-status-diff` and `supabase-refresh-ca` targets, which the scaffold's `make/local-db.mk` runs as `make local-db <command>` and `make server <command>`. |
| [components/supabase/bin/check-supabase-project](components/supabase/bin/check-supabase-project) | script | supabase | Checks that the Supabase CLI can see the project. |
| [components/supabase/bin/supabase-ca](components/supabase/bin/supabase-ca) | script | supabase | Downloads the database's root CA certificate and verifies the database's TLS certificate against it. |
| [components/supabase/bin/db-snapshot](components/supabase/bin/db-snapshot) | script | supabase | Writes a database's tables, columns, row counts and applied migrations as JSON. |
| [components/supabase/bin/db-snapshot-diff](components/supabase/bin/db-snapshot-diff) | script | supabase | Compares two snapshots, and exits 1 when the databases differ. |

## The manifest

`component.toml` has these parts. The `ComponentManifest` library's types, in [Sources/ComponentManifest/Manifest.swift](Sources/ComponentManifest/Manifest.swift), are the format. [schema/component.schema.json](schema/component.schema.json) says the same for editors, and a test keeps the two the same.

### `name`, `description`

The component's name, which is also its directory's name, and one sentence about what it sets up.

### `detect`

How to know that a repository uses the component, from its files only. Each rule is a `glob`, relative to the repository root (`**` matches any number of directories), with an optional `contains`: a regular expression that the contents of at least one matching file must match. The component is detected when every rule in `all` matches and, if `any` has rules, at least one of them does.

```toml
[detect]
all = [
  { glob = "fly.toml" },
  { glob = "Package.swift", contains = "github\\.com/vapor/vapor" },
]
```

### `inputs`

Values that differ for each project, such as the bundle ID or the team ID. Each has a `name`, a `description`, an `example`, an optional `default`, and `infer`: where to read the value in the repository, tried in order.

| `from` | Reads |
| --- | --- |
| `build-setting` | `key` from `xcodebuild -showBuildSettings` for the project's scheme. |
| `fastlane-config` | The first argument of the call `key` in `file`, such as `team_id("…")` in `fastlane/Appfile`. An array's values are joined with commas. |
| `toml` | The dotted `key` in the TOML `file`, such as `app` in `fly.toml`. |
| `yaml` | The dotted `key` in the YAML `file`, such as `global_secrets` in `.arkana.yml`. A list's values are joined with `separator`, a comma by default. |
| `glob` | The path of the first file that matches `glob` and, with `contains`, whose contents match that regular expression; with `exists = true`, `true` or `false`. |
| `regex` | The first capture group of `pattern` in the first file that matches `glob`. |

Any rule can have `map`, which replaces the value found with the value of its key, such as `{ iphoneos = "ios" }`. An input with no `infer`, or whose value is not found and has no `default`, is asked for one time.

### `secrets`

Secrets, by name. Each has a `description`, a `source` — `keychain:<item>`, `1password:op://<vault>/<item>/<field>`, or `generate:<kind>`, where `<kind>` is `ssh-key`, `password` or `hex32` — and a `scope`: `team` (one value for every project), `app` or `repo`, each set as a GitHub Actions secret; or `local`, a value kept only in the owner's Keychain for commands run on their Mac, such as `make deploy-beta`, and never set as a GitHub secret. A `local` secret's source is a Keychain item. A source can name an input, such as `keychain:superlinear.fly.{{inputs.fly_app}}.deploy-token` for a value that each app has. `human` is a step a person must do to get the value, with `twoFactor = true` when it needs a two-factor prompt. `rotateEvery`, such as `90d` or `1y`, is how often to make a new value.

### `steps`

Ordered. Each has an `id`, a `description`, a `check` — a shell command, run at the repository root, that exits 0 when the step is done — and a `fix`: a shell command, or `{ human = { text = "…" } }`, which becomes a Needs human issue. `scope = "app"` marks a step done one time for each app.

### `shared`

The reusable pieces that the component uses: `kind` (`workflow`, `fastlane`, `make`, `brewfile` or `script`), `path`, `version` and a `description`. A piece in another repository has `repo`, such as `armcknight/workflows`, and its `version` is the tag projects call it at, such as `4`; the validator does not look for its path here. For a piece in this repository, `version` is the tag that has it in its current form, such as `v1`. This README links to each piece: one in another repository at `https://github.com/<repo>/blob/<version>/<path>`.

### `docs`

Sections of the superlinear guide that explain the component, each with a `title` and an `anchor` listed in its [Anchors](https://github.com/armcknight/superlinear/blob/main/docs/anchors.md) page, as `<page>.md#<id>`, such as `builds.md#testflight`.

### Placeholders

Scaffold files, step commands, secrets' sources and human texts can contain:

* `{{inputs.<name>}}`: an input's value. In `check` and `fix` commands, the value is quoted for the shell.
* `{{templates}}`: the path of a checkout of this repository at the project's tag, for the scripts in `components/<name>/bin/`.
* `{{templates.tag}}`: the project's tag, such as `v1`.

GitHub Actions expressions, `${{ … }}`, are not placeholders.

## The scaffold's README section

Each component's `scaffold/README.md` has a section between these markers:

```
<!-- superlinear:begin how-this-is-built -->
<!-- superlinear:end -->
```

`superlinear bootstrap` writes it from the manifests of the components the project uses, and changes nothing outside the markers. It has a "How this project is built" heading and:

* the components the project uses, each linked to `components/<name>` here at the pinned tag;
* each shared workflow, lane, Makefile fragment and Brewfile the project uses, linked here at the pinned tag, or in its own repository at its `version`;
* the secrets by name, never their values, with where each comes from, and the human steps;
* links to the superlinear guide's [life of an issue](https://github.com/armcknight/superlinear/blob/main/docs/lifecycle.md#overview), [planning](https://github.com/armcknight/superlinear/blob/main/docs/planning.md#proposals), [bootstrap](https://github.com/armcknight/superlinear/blob/main/docs/bootstrap.md#components) and [builds](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#ci) sections, and to the components' own `docs` anchors;
* a link to the project's Linear team and, when it has one, its spec document.

## Adding a component

1. Make `components/<name>/` with `component.toml`, `CLAUDE.md` and `scaffold/README.md` with the markers.
2. Put shared lanes, Makefile fragments and scripts at the top level, and reusable workflows in armcknight/workflows. Add them to the manifest's `shared` and to the table above.
3. Add any new guide section to superlinear's `docs/`, with its anchor listed in `docs/anchors.md`, first.
4. Run the checks below, then tag a release.

## The package

[Package.swift](Package.swift) has two products:

* `ComponentManifest`, a library: `Manifest` and its `Codable` types for `component.toml`, and `Validator`, the checks below. Decoding is strict: an unknown key, an empty text, a value that does not match its pattern, or an empty list is an error with its path in the file, such as `secrets/0/source`. The library does not run `detect` rules or `infer` rules; superlinear does that on these types. The tests have a reference that runs them, `Tests/ComponentManifestTests/Detection.swift`, to test each component's rules against fixtures taken from the projects it comes from; set `MTG_REPOSITORY` to a checkout of mtg to also test `vapor-fly` and `supabase` against it.
* `validate-components`, a command: `validate-components [--root DIR] [--anchors PATH_OR_URL|none]`. The root is the current directory by default. The anchors come from superlinear's `docs/anchors.md` on `main` by default; a path or a URL replaces that, and `none` skips the check. It prints each problem to stderr and exits 1 when there are any.

The package builds on macOS and Linux. [TOMLKit](https://github.com/LebJe/TOMLKit) parses the TOML.

superlinear uses the library at a release tag. The tags are not three-part versions, so a `Package.swift` pins one as a revision:

```swift
.package(url: "https://github.com/armcknight/templatr", revision: "v1")
```

### What the validator checks

For each `components/<name>/component.toml`:

* the manifest decodes;
* `name` is the directory's name;
* input names, secret names and step IDs are unique;
* a `local` secret's source is a Keychain item;
* `CLAUDE.md` and `scaffold/README.md` exist, and the README has the generated section's markers, one time each and in order;
* each `{{placeholder}}` in the scaffold, the steps, the secrets' sources and the human texts names a declared input, `templates` or `templates.tag`;
* each regular expression compiles, and each `regex` infer rule has a capture group;
* each shared path in this repository exists; a path in another `repo` is not checked;
* each docs anchor is listed in superlinear's `docs/anchors.md`.

And `README.md` links to each component and each shared piece: a path in this repository, or `https://github.com/<repo>/blob/<version>/<path>`.

## Checks

CI runs these on each pull request and push, in the `swift` Docker image on Linux:

```sh
swift build
swift test                                    # the validator's tests, and the components' detect and infer rules against fixtures
swift run validate-components                 # the manifests, and the guide's docs/anchors.md
```

and checks every link in the Markdown files with [lychee](https://github.com/lycheeverse/lychee).
