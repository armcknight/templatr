# templatr

Components: reusable parts of a project, such as an Apple app, a Swift command-line tool, a Vapor server on Fly, or a Supabase database. Each one says how to recognize a project that uses it, what it needs to know about the project, which secrets it needs and where they come from, what to check and set up, and which shared workflows, lanes and Makefile fragments it uses.

Shared lanes and Makefile fragments are here. Reusable GitHub workflows are in [armcknight/workflows](https://github.com/armcknight/workflows), and the components' scaffolds call them.

The `templatr` command, and the `Templatr` library under it, read the components and set projects up with them: see [Setting up a project](#setting-up-a-project). [superlinear](https://github.com/armcknight/superlinear)'s `bootstrap` command uses the library. People can also follow a manifest by hand.

This repository holds no secrets: only their names and where to get them.

## Components

| Component | What it sets up |
| --- | --- |
| [apple-app](components/apple-app) | An app for iOS (with an optional embedded watch app), tvOS, macOS or more than one of them, from one Xcode project in `apple/`, tested on each pull request, with staging builds on demand, and uploaded to TestFlight by hand with `make apple <platform> deploy-beta`. |
| [base](components/base) | The root files that every project has with its other components: the Makefile that includes each component's targets, and the README.md that links to each component's README. |
| [github-repo](components/github-repo) | A repository on GitHub whose pull requests are squashed when they merge, with their branches deleted, and whose default branch cannot be deleted or force-pushed except by the owner. |
| [linear-workspace](components/linear-workspace) | A Linear workspace that superlinear works from: each team has an In Review state after In Progress, a Todo state, Triage, and superlinear's labels; the owner has a "superlinear proposals" view in their favorites; and no onboarding issue is open. See [The linear-workspace component](#the-linear-workspace-component). |
| [vapor-fly](components/vapor-fly) | A Swift server in `server/`, built with Vapor and run on Fly.io, built and tested on Linux on each pull request, and deployed by the owner, by hand with `make server deploy` or on a merge. |
| [supabase](components/supabase) | A Postgres database on Supabase for a Vapor server on Fly.io, with its files in `supabase/`, local and test databases, Supabase's root CA in the server's image, a local and remote parity check, and migrations with the Supabase CLI before each deploy or with Fluent when the server starts. |

## Layout

```
components/<name>/component.toml   the manifest
components/<name>/scaffold/        files copied one time into a project, at the paths they have there
components/<name>/CLAUDE.md        conventions for agents, included by projects
components/<name>/bin/             scripts the manifest's steps run
components/apple-app/match-certificates/  the Swift package that bin/list-match-certificates builds and runs
components/apple-app/xcodegen/     the templates of the files that bin/new-xcodegen-spec writes
.github/workflows/ci.yml           this repository's own CI
fastlane/                          shared lanes, imported with import_from_git
make/                              Makefile fragments
schema/component.schema.json       the manifest's JSON Schema, for editors
schema/check-report.schema.json    the format of `templatr check --json`
Package.swift                      the libraries and the commands
Makefile                           the templatr command's builds and releases
CHANGELOG.md                       the templatr command's changes
Sources/ComponentManifest/         the manifest's types and the checks
Sources/validate-components/       the validator command
Sources/Templatr/                  the library that sets projects up
Sources/TemplatrCLI/               the templatr command
Tests/ComponentManifestTests/      the validator's tests
Tests/TemplatrTests/               the Templatr library's tests
```

## Releases

The templates — the components, the `make/*.mk` fragments and the shared Fastfile — have releases with three-part tags: `v1.0.0`, `v1.1.0`, `v2.0.0`. Their version is in [components/VERSION](components/VERSION) and their changes are in [components/CHANGELOG.md](components/CHANGELOG.md). Each release also moves the alias of its major version, `v1` or `v2`, to it, and projects pin the alias — in `import_from_git(branch: "v1")`, `TEMPLATES_TAG = v1` and `.templatr.toml` — never a full tag or `main`. The workflows from armcknight/workflows are called the same way, at their major alias, such as `@4`, never `@main`.

A compatible change, such as a fixed lane or a new optional input, is a minor or patch release, and reaches every project pinned to its alias on that project's next `make templates-update` or fastlane run. A change that a project must act on, such as a renamed input, a new required secret or a lane that behaves differently, is a new major version; moving a project from `v1` to `v2` is a change in that project, and `templatr check` reports each component that is pinned to an older major than the newest alias.

* `make templates-patch`, `make templates-minor` or `make templates-major` bumps `components/VERSION` and commits it.
* `make templates-deploy` moves the `[Unreleased]` section of `components/CHANGELOG.md` into a section for the version, commits, tags the commit with the version and a `v`, such as `v1.1.0`, and pushes. [release.yml](.github/workflows/release.yml) then calls armcknight/workflows' [github-release.yml](https://github.com/armcknight/workflows/blob/main/.github/workflows/github-release.yml), which makes the GitHub release from that section, moves the alias `v1` to the tag when the tag is on `main` and is the newest of its major, and asks mcknight.io to refresh its projects page when the `SITE_DISPATCH_TOKEN` secret is set.
* `make templates-deploy-beta` does the same for a release candidate, such as `v1.1.0-RC1`, which is a prerelease and does not move the alias. Pin one project to it, with `TEMPLATES_TAG` and `import_from_git`, to try a lane or a fragment before every project gets it.

The `templatr` command has releases of its own, with three-part tags without the `v`, such as `0.1.0`, and its changes are in [CHANGELOG.md](CHANGELOG.md). `make patch`, `make minor` or `make major` bumps the version in `Sources/TemplatrCLI/Version.swift` and commits it. `make deploy` moves the changelog's `[Unreleased]` section into a section for the version, tags the commit, pushes, and makes a GitHub release; `make deploy-beta` does the same for a release candidate, such as `0.1.0-RC1`. A component is never pinned to one of these tags, as `templatr` reads only the `v*` tags.

`make help` lists both families of targets. vrsn and prepare-release come from the armcknight/tools cask.

## Shared pieces

| Piece | Kind | Used by | What it does |
| --- | --- | --- | --- |
| [fastlane/Fastfile](fastlane/Fastfile) | fastlane | apple-app | The `test` and `beta` lanes for `ios`, `tvos` and `mac`, and the `stage` lane for `ios`. |
| [armcknight/workflows: ios-ci.yml](https://github.com/armcknight/workflows/blob/4/.github/workflows/ios-ci.yml) | workflow | apple-app | Runs the `test` lane on each pull request, and on a `/build-staging` comment the `stage` lane, with an install link. |
| [armcknight/workflows: ota-refresh.yml](https://github.com/armcknight/workflows/blob/4/.github/workflows/ota-refresh.yml) | workflow | apple-app | Signs a staging build's install link again on a `/refresh-staging` comment, and asks for a new build when the old one is gone. |
| [armcknight/workflows: ota-cleanup.yml](https://github.com/armcknight/workflows/blob/4/.github/workflows/ota-cleanup.yml) | workflow | apple-app | Deletes a pull request's staging builds when it closes. |
| [make/apple-app.mk](make/apple-app.mk) | make | apple-app | The `apple-app-test` and `apple-app-deploy-beta` targets for every platform, `apple-app-<platform>-test` and `apple-app-<platform>-deploy-beta` for each, `apple-app-ios-stage`, and `apple-app-patch`, `apple-app-minor` and `apple-app-major`, which `apple/component.mk` runs as `make apple <command>` and `make apple <platform> <command>`. |
| [components/apple-app/scaffold/apple/Brewfile](components/apple-app/scaffold/apple/Brewfile) | brewfile | apple-app | The tools the lanes use. |
| [components/apple-app/bin/check-app-store-connect](components/apple-app/bin/check-app-store-connect) | script | apple-app | Checks the app record and its tester group in App Store Connect. |
| [components/apple-app/bin/list-match-certificates](components/apple-app/bin/list-match-certificates) | script | apple-app | Lists the certificates and profiles in the fastlane match repository, with their expiry dates. It builds and runs the `list-match-certificates` command of the Swift package in [components/apple-app/match-certificates](components/apple-app/match-certificates), so its first run takes longer. |
| [components/apple-app/bin/new-xcodegen-spec](components/apple-app/bin/new-xcodegen-spec) | script | apple-app | Writes a new app's XcodeGen spec, `apple/project.yml`, for its `xcode-project` step: an app target and a test target that build for each platform in the `platforms` input (`ios` is iOS, `tvos` tvOS and `mac` macOS in XcodeGen's `supportedDestinations`), with the xcconfig, a SwiftUI app and a test that it needs. It fills in the templates in [components/apple-app/xcodegen](components/apple-app/xcodegen). An app that has an Xcode project, a workspace, a spec or a Tuist manifest already passes the step's check, and nothing is written. |
| [components/apple-app/bin/check-shared-lanes](components/apple-app/bin/check-shared-lanes) | script | apple-app | Checks that `fastlane/Fastfile` uses the shared lanes. |
| [armcknight/workflows: vapor-ci.yml](https://github.com/armcknight/workflows/blob/4/.github/workflows/vapor-ci.yml) | workflow | vapor-fly | Builds and tests the package on Linux in the swift image on each pull request, and builds the Docker image. |
| [armcknight/workflows: fly-deploy.yml](https://github.com/armcknight/workflows/blob/4/.github/workflows/fly-deploy.yml) | workflow | vapor-fly | Deploys the default branch's tip to Fly with its `GIT_SHA`, by hand or on a merge, then waits for the health check to answer. |
| [make/vapor-fly.mk](make/vapor-fly.mk) | make | vapor-fly | The `vapor-fly-build`, `vapor-fly-serve`, `vapor-fly-serve-docker`, `vapor-fly-deploy` and `vapor-fly-status` targets, which `server/component.mk` runs as `make server <command>`. |
| [components/vapor-fly/scaffold/server/Brewfile](components/vapor-fly/scaffold/server/Brewfile) | brewfile | vapor-fly | The tools the Makefile targets use. |
| [components/vapor-fly/bin/check-fly-config](components/vapor-fly/bin/check-fly-config) | script | vapor-fly | Checks that `fly.toml` names the app, forces HTTPS, scales to zero and has the health check. |
| [components/vapor-fly/bin/check-fly-secrets](components/vapor-fly/bin/check-fly-secrets) | script | vapor-fly, supabase | Checks that the Fly app has each runtime secret, by name. |
| [make/supabase.mk](make/supabase.mk) | make | supabase | The `supabase-db-init`, `supabase-db-reset`, `supabase-db-migrate`, `supabase-db-test-start`, `supabase-db-test-stop`, `supabase-db-status`, `supabase-status-diff` and `supabase-refresh-ca` targets, which `supabase/component.mk` runs as `make local-db <command>`, `make server status-diff` and `make server refresh-ca`. |
| [components/supabase/bin/check-supabase-project](components/supabase/bin/check-supabase-project) | script | supabase | Checks that the Supabase CLI can see the project. |
| [components/supabase/bin/supabase-ca](components/supabase/bin/supabase-ca) | script | supabase | Downloads the database's root CA certificate and verifies the database's TLS certificate against it. |
| [components/supabase/bin/db-snapshot](components/supabase/bin/db-snapshot) | script | supabase | Writes a database's tables, columns, row counts and applied migrations as JSON. |
| [components/supabase/bin/db-snapshot-diff](components/supabase/bin/db-snapshot-diff) | script | supabase | Compares two snapshots, and exits 1 when the databases differ. |
| [components/github-repo/bin/check-merge-options](components/github-repo/bin/check-merge-options) | script | github-repo | Checks that pull requests merge only by squashing, titled with the pull request's title, that GitHub offers to update their branches, and that it deletes them after a merge. |
| [components/github-repo/bin/check-rulesets-available](components/github-repo/bin/check-rulesets-available) | script | github-repo | Checks that GitHub offers rulesets for the repository, which it does not for a private repository on the free plan. |
| [components/github-repo/bin/check-default-branch-protection](components/github-repo/bin/check-default-branch-protection) | script | github-repo | Checks that a ruleset that the owner can bypass stops the default branch from being deleted or force-pushed, when GitHub offers rulesets for the repository. |
| [components/github-repo/bin/protect-default-branch](components/github-repo/bin/protect-default-branch) | script | github-repo | Makes or updates the `Default branch` ruleset, which stops the default branch from being deleted or force-pushed, with a bypass for the repository's admins. |
| [components/linear-workspace/bin/linear-workspace](components/linear-workspace/bin/linear-workspace) | script | linear-workspace | Checks, and sets up, the Linear workspace's teams' states, Triage and labels, the proposals view, the onboarding issues and the initiatives, with Linear's API. |

## The linear-workspace component

Its steps check, and `bootstrap` sets up, the Linear workspace that superlinear works from. They run like any other component's steps, and their results are in the same report.

It is detected by an `.envrc` (or `.envrc.example`) that sets `LINEAR_API_KEY` or `LINCTL_API_KEY`. A project without one can add `linear-workspace` to `.templatr.toml` by hand. Its input `linear_teams` has the keys of the teams to check, separated by spaces, such as `STA`; empty, the default, means every team in the workspace. superlinear gives the teams of its `teamIds`. Set `linear_initiatives` to `true` when the project's spec should be under an initiative.

| Step | Check | Fix |
| --- | --- | --- |
| `linear-key` | `LINEAR_API_KEY`, else `LINCTL_API_KEY`, is set, Linear accepts it, and its user is an admin of the workspace or of each team, which the fixes need. | Human: make a personal API key in Linear's settings, as the workspace's owner, and export it in the project's `.envrc`. |
| `envrc-ignored` | An `.envrc` that holds a key is ignored by git. | Adds `.envrc` to `.gitignore`. |
| `in-review-state` | Each team has an "In Review" state of type `started`, after "In Progress": superlinear sets it after it opens a pull request. | Makes the state, or moves it, after the team's last `started` state and before its first `completed` one. |
| `todo-state` | Each team has a state of type `unstarted`, which superlinear's `ready` mode starts from. | Human. |
| `triage` | Triage is on in each team: superlinear puts its proposals there. | Turns it on. |
| `labels` | Each team has the labels `Needs human`, `superlinear`, `superlinear: proposed`, `superlinear: spec` and `superlinear: hands off`, as team or workspace labels. | Makes the missing ones as team labels. |
| `proposals-view` | A custom view named "superlinear proposals" shows the open issues labeled `superlinear: proposed`, and is in the key's user's favorites. superlinear's comments are written with the owner's own key, so they do not reach the owner's inbox; this view is where pending proposals are found. | Makes the view, or corrects its filter, and adds it to the favorites. |
| `onboarding-issues` | None of the issues Linear makes in a new workspace ("Get familiar with Linear", "Set up your teams", "Connect your tools", "Import your data") is open: in `ready` mode, superlinear would start agents on them. | Cancels the open issues with exactly those titles. |
| `initiatives` | Only when `linear_initiatives` is `true`: the workspace has an initiative. The API cannot tell whether initiatives are on, but there are initiatives only when they are. | Human: turn initiatives on in the workspace's settings. The API cannot. |

The steps read the key from their environment: `LINEAR_API_KEY`, else `LINCTL_API_KEY`. A project's `.envrc` already exports `LINCTL_API_KEY` for `linctl`, and direnv loads it in the shell; a script runs `direnv exec <repository> swift run templatr check <repository>`. superlinear's daemon has no `.envrc`, so it gives each workspace's key from its own config to the steps, with `Services.system(environment:)`.

The script calls Linear's GraphQL API with `curl`, and reads its JSON with JavaScript for Automation, which every Mac has; the steps that use it run only on macOS. It never prints the key, and gives it to `curl` in a header file that only the user can read, never on a command line. Each fix is safe to run again.

## The manifest

`component.toml` has these parts. The `ComponentManifest` library's types, in [Sources/ComponentManifest/Manifest.swift](Sources/ComponentManifest/Manifest.swift), are the format. [schema/component.schema.json](schema/component.schema.json) says the same for editors, and a test keeps the two the same.

### `name`, `description`

The component's name, which is also its directory's name, and one sentence about what it sets up.

### `directory`, `blurb`, `base`

`directory` is the project's subdirectory that the component's files are in, such as `server` for vapor-fly and `apple` for apple-app. It names the part's role, not its framework or how it is deployed, so that it stays right when those change, and so that a second app can have its own, such as `android`. A component has its own directory also when a project has no other component. Its `detect` and `infer` rules read files in it, but for those with `root = true`, and its steps run in it.

`blurb` is a summary of the component's part of the project, with placeholders. `templatr bootstrap` writes it in the root README.md, with a link to the README.md in `directory`.

A component with `base = true` comes with every other component, so it has no `detect` and no `directory`: [base](components/base) has the root Makefile and README.md. There is at most one.

### Project layout

Each component's scaffold has the files at the paths they have in the project: under its `directory`, such as `scaffold/server/fly.toml`, with its own `README.md`, `.gitignore` and `Brewfile` there, and its workflows in `scaffold/.github/workflows/`, each named with the component's name first, such as `vapor-fly-ci.yml`, because GitHub reads workflows only there. The tools run in the directory, or are told where it is: `fly deploy server`, `docker compose --file server/docker-compose.yml`, `cd apple && bundle exec fastlane`, and the shared workflows' `working-directory` input. No two components have a file at the same path.

The root Makefile, from the base component, has `TEMPLATES_TAG`, the rule that downloads the Makefile fragments, `help` and `templates-update`, and includes every `*/component.mk`. Each component's `component.mk` sets its values, adds its namespace to `NAMESPACES` and its fragment to `TEMPLATES_FRAGMENTS`, includes the fragment, and maps `make <namespace> <command>` to the fragment's targets, such as `make server deploy` to `vapor-fly-deploy`.

### `detect`

How to know that a repository uses the component, from its files only. Each rule is a `glob`, relative to the component's `directory`, or to the repository root when it has none (`**` matches any number of directories), with an optional `contains`: a regular expression that the contents of at least one matching file must match. The component is detected when every rule in `all` matches and, if `any` has rules, at least one of them does.

```toml
[detect]
all = [
  { glob = "fly.toml" },
  { glob = "Package.swift", contains = "github\\.com/vapor/vapor" },
]
```

A rule with `root = true` reads from the repository root instead, so that a component can be detected from another part of the project before its own directory exists, such as a database from the server's `Package.swift`. `root` is only for a component with a `directory`; the validator rejects it otherwise.

```toml
[detect]
any = [
  { glob = "component.mk" },
  { glob = "server/Package.swift", contains = "fluent-postgres-driver", root = true },
]
```

### `inputs`

Values that differ for each project, such as the bundle ID or the team ID. Each has a `name`, a `description`, an `example`, an optional `default`, and `infer`: where to read the value in the repository, tried in order.

| `from` | Reads |
| --- | --- |
| `build-setting` | `key` from `xcodebuild -showBuildSettings` for the project's scheme, in the Release configuration when the project has one. With `separator`, the setting is a list separated by white space, such as `SUPPORTED_PLATFORMS`: `map` replaces each word, a value already in the list is dropped, and the values are joined with `separator`. |
| `fastlane-config` | The first argument of the call `key` in `file`, such as `team_id("…")` in `fastlane/Appfile`. An array's values are joined with commas. |
| `toml` | The dotted `key` in the TOML `file`, such as `app` in `fly.toml`. |
| `yaml` | The dotted `key` in the YAML `file`, such as `global_secrets` in `.arkana.yml`. A list's values are joined with `separator`, a comma by default. |
| `glob` | The path of the first file that matches `glob` and, with `contains`, whose contents match that regular expression; with `stem = true`, that file's name without its directory and extension; with `exists = true`, `true` or `false`. |
| `regex` | The first capture group of `pattern` in the first file that matches `glob`. |

Any rule can have `map`, which replaces the value found with the value of its key, such as `{ iphoneos = "ios" }`. A rule that reads a file, every source but `build-setting`, can have `root = true`, as a `detect` rule can, to read its `file` or `glob` from the repository root instead of the component's `directory`, such as `{ from = "toml", file = "server/fly.toml", key = "app", root = true }`. An input with no `infer`, or whose value is not found and has no `default`, is asked for one time.

### `secrets`

Secrets, by name. Each has a `description`, a `source` — `keychain:<item>`, `1password:op://<vault>/<item>/<field>`, or `generate:<kind>`, where `<kind>` is `ssh-key`, `password` or `hex32` — and a `scope`: `team` (one value for every project), `app` or `repo`, each set as a GitHub Actions secret; or `local`, a value kept only in the owner's Keychain for commands run on their Mac, such as `make deploy-beta`, and never set as a GitHub secret. A `local` secret's source is a Keychain item. A source can name an input, such as `keychain:templatr.fly.{{inputs.fly_app}}.deploy-token` for a value that each app has. `human` is a step a person must do to get the value, with `twoFactor = true` when it needs a two-factor prompt. `rotateEvery`, such as `90d` or `1y`, is how often to make a new value.

### `steps`

Ordered. Each has an `id`, a `description`, a `check` — a shell command, run in the component's `directory`, or at the repository root when it has none, that exits 0 when the step is done — and a `fix`: a shell command, or `{ human = { text = "…" } }`, which becomes a Needs human issue. `scope = "app"` marks a step done one time for each app.

### `shared`

The reusable pieces that the component uses: `kind` (`workflow`, `fastlane`, `make`, `brewfile` or `script`), `path`, `version` and a `description`. A piece in another repository has `repo`, such as `armcknight/workflows`, and its `version` is the tag projects call it at, such as `4`; the validator does not look for its path here. For a piece in this repository, `version` is the tag that has it in its current form, such as `v1`. This README links to each piece: one in another repository at `https://github.com/<repo>/blob/<version>/<path>`.

### `docs`

Sections of the superlinear guide that explain the component, each with a `title` and an `anchor` listed in its [Anchors](https://github.com/armcknight/superlinear/blob/main/docs/anchors.md) page, as `<page>.md#<id>`, such as `builds.md#testflight`.

### `certificates`

Optional. Signing certificates, provisioning profiles and other files that stop working on a date. Each has an `id`, a `description`, a `list` command — a shell command, run in the component's `directory`, or at the repository root when it has none, that prints one line for each certificate: its expiry as an ISO 8601 date and time, such as `2027-03-01T12:00:00Z`, a tab, and its name — and `renew`, the human step to replace one, as `{ text = "…", twoFactor = true }`. `templatr check` reports each one that expires within 30 days, or has expired, with the `renew` text. A `list` command that exits with a status other than 0, or prints a line in another form, is reported as an error. The `apple-app` component lists the certificates and profiles in the fastlane match repository with [components/apple-app/bin/list-match-certificates](components/apple-app/bin/list-match-certificates), which runs the Swift package in [components/apple-app/match-certificates](components/apple-app/match-certificates). It decrypts them in memory with `MATCH_PASSWORD`.

```toml
[[certificates]]
id = "match"
description = "The signing certificates and provisioning profiles in the fastlane match repository."
list = "{{templates}}/components/apple-app/bin/list-match-certificates {{inputs.match_git_url}} {{inputs.app_identifiers}}"
renew = { text = "Renew them with match.", twoFactor = true }
```

### Placeholders

Scaffold files, step commands, certificates' `list` commands, secrets' sources, human texts and blurbs can contain:

* `{{inputs.<name>}}`: an input's value. In `check`, `fix` and `list` commands, the value is quoted for the shell.
* `{{templates}}`: the path of a checkout of this repository at the project's tag, for the scripts in `components/<name>/bin/`.
* `{{templates.tag}}`: the project's tag, such as `v1`.

GitHub Actions expressions, `${{ … }}`, are not placeholders.

## The root README

The base component's `scaffold/README.md`, the project's root README.md, has a section between these markers:

```
<!-- templatr:begin how-this-is-built -->
<!-- templatr bootstrap writes this section from the components' manifests. Do not edit it. -->
## How this project is built

This project uses these components from [armcknight/templatr](https://github.com/armcknight/templatr):

* [base](https://github.com/armcknight/templatr/tree/v1/components/base) at `v1`: The project's root files, which every project has with its other components: the Makefile that includes each component's targets, and the README.md that links to each component's README.
* [github-repo](https://github.com/armcknight/templatr/tree/v1/components/github-repo) at `v1`: A repository on GitHub whose pull requests are squashed when they merge, and whose default branch cannot be deleted or force-pushed except by the owner.
* [linear-workspace](https://github.com/armcknight/templatr/tree/v1/components/linear-workspace) at `v1`: A Linear workspace that superlinear works from: each team has an In Review state, a Todo state, Triage and superlinear's labels, the owner has a view of the pending proposals, and no onboarding issue is open.

### Shared pieces

* [components/github-repo/bin/check-merge-options](https://github.com/armcknight/templatr/blob/v1/components/github-repo/bin/check-merge-options), script: Checks that pull requests merge only by squashing, titled with the pull request's title, that branches can be updated, and that they are deleted after a merge.
* [components/github-repo/bin/check-rulesets-available](https://github.com/armcknight/templatr/blob/v1/components/github-repo/bin/check-rulesets-available), script: Checks that GitHub offers rulesets for the repository, which it does not for a private repository on the free plan.
* [components/github-repo/bin/check-default-branch-protection](https://github.com/armcknight/templatr/blob/v1/components/github-repo/bin/check-default-branch-protection), script: Checks that a ruleset that the owner can bypass stops the default branch from being deleted or force-pushed, when GitHub offers rulesets for the repository.
* [components/github-repo/bin/protect-default-branch](https://github.com/armcknight/templatr/blob/v1/components/github-repo/bin/protect-default-branch), script: Makes or updates the Default branch ruleset, which stops the default branch from being deleted or force-pushed, with a bypass for the repository's admins.
* [components/linear-workspace/bin/linear-workspace](https://github.com/armcknight/templatr/blob/v1/components/linear-workspace/bin/linear-workspace), script: Checks, and sets up, a Linear workspace's teams' states, Triage and labels, the superlinear proposals view, the onboarding issues and the initiatives, with Linear's API and a key from the environment.

### Steps a person does

* The root Makefile includes each component's component.mk, and has the help and templates-update targets. If not: Copy the Makefile from the base scaffold, or add its TEMPLATES_TAG, NAMESPACES, TEMPLATES_FRAGMENTS, the include of */component.mk, the namespace rule, the fragment download rule, help and templates-update to the project's Makefile. Move the targets that were in it for one component, such as its VAPOR_FLY_* or APPLE_APP_* values, into that component's component.mk.
* The GitHub CLI is logged in. If not: Run `gh auth login` on this Mac, as the owner of the repository.
* The repository is on GitHub, and the logged-in user can administer it. If not: Push the repository to GitHub, with a remote that points to it, and run `gh auth login` as its owner or as an admin of it.
* GitHub offers rulesets for the repository: it is public, or its owner has a paid plan. If not: The repository is private on GitHub's free plan, so GitHub offers no rulesets, and nothing stops its default branch from being deleted or force-pushed. Make the repository public, or upgrade to GitHub Pro; or accept the risk.
* LINEAR_API_KEY, else LINCTL_API_KEY, is set, Linear accepts it, and its user is an admin of each team. If not: As the owner of the Linear workspace, make a personal API key in Linear's settings (Security & access), and export it as LINCTL_API_KEY in the project's .envrc. Its user must be an admin of the workspace or of each team.
* Each team has at least one state of type unstarted, such as Todo, which superlinear's ready mode starts issues from. If not: In each team's settings in Linear (Issue statuses & automations), add a status of the Todo type.
* When the project's spec should be under an initiative (linear_initiatives is true), the workspace has initiatives. If not: Turn on initiatives in the Linear workspace's settings (Initiatives), and make the project's initiative. The API cannot turn them on.

### Further reading

* [The life of an issue](https://github.com/armcknight/superlinear/blob/main/docs/lifecycle.md#overview)
* [Planning](https://github.com/armcknight/superlinear/blob/main/docs/planning.md#proposals)
* [Bootstrap](https://github.com/armcknight/superlinear/blob/main/docs/bootstrap.md#components)
* [Builds](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#ci)
* [bootstrap --check](https://github.com/armcknight/superlinear/blob/main/docs/bootstrap.md#bootstrap-check)
* [The pull request](https://github.com/armcknight/superlinear/blob/main/docs/lifecycle.md#pull-request)
* [The merge](https://github.com/armcknight/superlinear/blob/main/docs/lifecycle.md#merge)
* [A workspace's API key](https://github.com/armcknight/superlinear/blob/main/docs/configuration.md#api-key)
* [A workspace's teams](https://github.com/armcknight/superlinear/blob/main/docs/configuration.md#team-ids)
<!-- templatr:end -->
```

`templatr bootstrap` writes it one time for the whole project, from the manifests of the components the project uses, and changes nothing outside the markers. The components' own READMEs, in their directories, do not have it. It has a "How this project is built" heading and:

* the components the project uses, each linked to `components/<name>` here at the pinned tag, with its directory;
* each shared workflow, lane, Makefile fragment and Brewfile the project uses, linked here at the pinned tag, or in its own repository at its `version`;
* the secrets by name, never their values, with where each comes from, and the human steps;
* links to the superlinear guide's [life of an issue](https://github.com/armcknight/superlinear/blob/main/docs/lifecycle.md#overview), [planning](https://github.com/armcknight/superlinear/blob/main/docs/planning.md#proposals), [bootstrap](https://github.com/armcknight/superlinear/blob/main/docs/bootstrap.md#components) and [builds](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#ci) sections, and to the components' own `docs` anchors;
* a link to the project's Linear team and, when it has one, its spec document.

Above it, each component with a `blurb` has its own section, which bootstrap writes between `<!-- templatr:begin <name> -->` and `<!-- templatr:end -->`: a link to its directory's README.md and its blurb.

## Setting up a project

Run `templatr` from a checkout of this repository. It is not in a Homebrew tap. `make init` installs what it and the Makefile targets shell out to, from the [Brewfile](Brewfile); `make install` puts a release build in `~/.local/bin`, which runs against this checkout; its `--version` names the commit it was built from, such as `0.1.0+d0a4bc2`, with `.dirty` when the tree had changes.

```sh
git clone https://github.com/armcknight/templatr && cd templatr
make init
swift run templatr bootstrap ~/Code/babysittr     # set the project up
swift run templatr check ~/Code/babysittr         # report what it still needs, and change nothing
```

`bootstrap` needs `gh`, logged in, in the project's directory to read and set its secrets; `security` for the Keychain; `op` for 1Password secrets; and `xcodebuild` for build settings. `{{templates}}` in the steps is the checkout it runs from.

### `templatr bootstrap [<repository>]`

1. **Which components.** On the first run it matches each component's `detect` rules against the files in its directory, or the repository's for a rule with `root = true`; it can find more than one, and the base component comes with them. It reads each input from where its `infer` says, then shows the values it found to confirm, and asks for the ones it did not find. Leave an answer empty to skip it: the steps and scaffold files that need it wait for a later run.
2. **The record.** It writes `.templatr.toml` at the repository's root: each component, the tag it is pinned to, and its inputs. Later runs read it instead of detecting again, and a change made to it by hand wins. A component that detection finds later, such as a watch app added to the project, is reported, not added: add it to the file to use it.

   ```toml
   [components.apple-app]
   tag = "v1"

   [components.apple-app.inputs]
   bundle_id = "io.mcknight.babysittr"
   ```

3. **Scaffold.** It copies each scaffold file that the project does not have yet, with its placeholders filled in. It never overwrites a file. A path that two components' scaffolds have is an error, and neither file is copied.
4. **Steps.** It runs each step's `check`, and its `fix` command when the check fails, then the check again. A failing step whose fix is `human` is reported with its text, whether it needs two-factor, and links to the manifest and the guide. A step that is done one time for each app (`scope = "app"`) runs one time.
5. **Secrets.** It reads the repository's secret names with `gh secret list`. For each missing one, after it asks, it reads the value from its `source` and gives it to `gh secret set` on standard input. A `generate:` secret is made on this Mac and stored first in the Keychain item `templatr.<name>`, such as `templatr.match-deploy-key`, with an SSH key's public half in `templatr.<name>.pub`. A `local` secret is only looked for in the Keychain, and never set in GitHub. Values never go to a log, the output or a file.
6. **README and CLAUDE.md.** It writes the root README's "How this project is built" section between its markers, adding them at the end when the README does not have them, and each component's blurb between its own markers, adding them above that section; it changes nothing outside them. It copies each component's `CLAUDE.md` to `.templatr/<name>/CLAUDE.md` and imports those copies in the project's `CLAUDE.md`, between `<!-- templatr:begin components -->` and `<!-- templatr:end -->`.

It then reports what is left, as `check` does. Running it again changes nothing that is already done.

Options: `--yes` accepts the inputs found and sets missing secrets without asking; without a terminal, nothing is asked, and secrets are set only with `--yes`. `--link TITLE=URL`, which can be given more than one time, adds a link to the README section, such as the project's Linear team or spec document. `--tag TAG` is the tag new components are pinned to, the checkout's newest alias, such as `v1`, by default (a full tag, such as `v1.0.1`, can be given), and `--templates DIR` another checkout of this repository.

### `templatr check [<repository>] [--json]`

The checks only; it changes nothing. It reports the steps whose checks fail, the human steps, the inputs and the secrets that are missing (by name), secrets due for a new value within 30 days of their `rotateEvery`, certificates and profiles that expire within 30 days, from the manifests' `certificates`, components pinned to an older major version than the newest alias (`v1` when `v2` exists, but not when only `v1.0.1` does), and links in the README that no longer resolve. `--offline` skips the web links.

With `--json`, it prints the report in the format of [schema/check-report.schema.json](schema/check-report.schema.json), which superlinear reads. Its `version` changes only when a change would break a reader.

The exit status is 0 when nothing is left to do, 1 when the report lists something or an error stops the run, and 64 for a usage error. `templatr --help` and `templatr <subcommand> --help` show all the options.

### Storing the App Store Connect keys and Fly deploy tokens

[bin/store-secrets](bin/store-secrets) stores the secrets that the owner makes for the `apple-app` and `vapor-fly` components in the Keychain, under the item names that the manifests' `source` fields give. Apple has no command line or API that makes an App Store Connect team API key: first make each key on the website (Users and Access, Integrations, App Store Connect API, Team Keys) and download its `.p8` file, which downloads only one time. Fly deploy tokens it makes itself, with `fly tokens create deploy`, when `fly` is logged in.

```sh
bin/store-secrets \
  --asc-key ~/Downloads/AuthKey_ABC123DEFG.p8 --asc-key-id ABC123DEFG --asc-issuer-id <issuer-id> \
  --asc-admin-key ~/Downloads/AuthKey_HIJ456KLMN.p8 --asc-admin-key-id HIJ456KLMN --asc-admin-issuer-id <issuer-id> \
  --fly-app mtg-armcknight \
  --check ~/Code/babysittr --check ~/Code/mtg
```

* `--asc-key`, `--asc-key-id` and `--asc-issuer-id` are the Uploads key, with the App Manager role, stored as `ASC_KEY_P8_BASE64` (the file, base64 encoded), `ASC_KEY_ID` and `ASC_ISSUER_ID`. The `--asc-admin-…` options are the same for the Admin key, which match needs to make or renew certificates and profiles, stored as `ASC_ADMIN_KEY_P8_BASE64`, `ASC_ADMIN_KEY_ID` and `ASC_ADMIN_ISSUER_ID`. Give a key's three options together, or none of them.
* `--fly-app`, which can be given more than one time, makes a deploy token for the app that expires in a year, and stores it as the app's `FLY_API_TOKEN`.
* `--check`, which can be given more than one time, runs `swift run templatr check` on the repository at the end.
* `--dry-run` prints the item that each value would go in, and stores nothing, makes no token and runs no check.

It also looks for `MATCH_PASSWORD` and `MATCH_DEPLOY_KEY` in the Keychain, and says how to add each one that is missing; it does not make them. It never prints a value, and never puts one in a command's arguments, where `ps` can show it: values go to `security -i` on standard input, as `templatr` stores them. Running it again replaces the values. The exit status is 0 when everything was stored and nothing is missing, 1 when something failed or is missing, and 2 for a usage error.

## Adding a component

1. Make `components/<name>/` with `component.toml`, with its `directory` and `blurb`, `CLAUDE.md`, and `scaffold/<directory>/README.md`, without the markers. Put its files under `scaffold/<directory>/`, its Makefile targets in `scaffold/<directory>/component.mk`, and its workflows in `scaffold/.github/workflows/<name>-*.yml`.
2. Put shared lanes, Makefile fragments and scripts at the top level, and reusable workflows in armcknight/workflows. Add them to the manifest's `shared` and to the table above.
3. Add any new guide section to superlinear's `docs/`, with its anchor listed in `docs/anchors.md`, first.
4. Add it to the `[Unreleased]` section of [components/CHANGELOG.md](components/CHANGELOG.md), and run the checks below. Its release is the next `make templates-minor` and `make templates-deploy`.

## The package

[Package.swift](Package.swift) has four products:

* `ComponentManifest`, a library: `Manifest` and its `Codable` types for `component.toml`, and `Validator`, the checks below. Decoding is strict: an unknown key, an empty text, a value that does not match its pattern, or an empty list is an error with its path in the file, such as `secrets/0/source`. The library does not run `detect` rules or `infer` rules; the `Templatr` library below does that on these types.
* `validate-components`, a command: `validate-components [--root DIR] [--anchors PATH_OR_URL|none]`. The root is the current directory by default. The anchors come from superlinear's `docs/anchors.md` on `main` by default; a path or a URL replaces that, and `none` skips the check. It prints each problem to stderr and exits 1 when there are any.
* `Templatr`, a library on the `ComponentManifest` types: `Bootstrapper`'s `resolve`, `bootstrap` and `check` do what [Setting up a project](#setting-up-a-project) says, and return a `Report`, the same values that `check --json` prints. Only the `linear-workspace` component's steps use Linear, with a key from the environment: superlinear turns the report into issues. The programs it runs, the Keychain, 1Password and GitHub are behind the protocols in `Services`, which the tests replace. `ProcessRunner(environment:)` adds environment variables to the commands it runs, such as a Linear API key for the steps. Its tests run each component's `detect` and `infer` rules with `resolve`, against fixtures taken from the projects the component comes from; set `MTG_REPOSITORY` to a checkout of mtg to also test `vapor-fly` against it.
* `templatr`, a command: a thin layer on the library, which asks the questions.

The package builds on macOS and Linux. [TOMLKit](https://github.com/LebJe/TOMLKit) parses the TOML, and [Yams](https://github.com/jpsim/Yams) the YAML.

superlinear uses the library at a templates release. The alias `v1` is not a three-part version, so a `Package.swift` pins it as a revision:

```swift
.package(url: "https://github.com/armcknight/templatr", revision: "v1")
```

### What the validator checks

For each `components/<name>/component.toml`:

* the manifest decodes;
* `name` is the directory's name;
* input names, secret names, step IDs and `certificates` IDs are unique;
* a `local` secret's source is a Keychain item;
* `CLAUDE.md` exists;
* a component with a `directory` has `scaffold/<directory>/README.md`, without the generated section's markers, and its other scaffold files are under `scaffold/<directory>/` or are workflows named `.github/workflows/<name>-*`; a component with neither has only such workflows;
* the base component has `scaffold/README.md`, with the generated section's markers, one time each and in order;
* there is at most one base component, no two components have the same `directory`, no two scaffolds have a file at the same path, and no scaffold has a file in another component's directory;
* each `{{placeholder}}` in the scaffold, the steps, the certificates' `list` commands, the secrets' sources, the human texts and the blurb names a declared input, `templates` or `templates.tag`;
* each regular expression compiles, and each `regex` infer rule has a capture group;
* a `detect` or `infer` rule has `root = true` only in a component with a `directory`;
* each shared path in this repository exists; a path in another `repo` is not checked;
* each docs anchor is listed in superlinear's `docs/anchors.md`.

And `README.md` links to each component and each shared piece: a path in this repository, or `https://github.com/<repo>/blob/<version>/<path>`.

## Checks

CI runs these on each pull request and push, in the `swift` Docker image on Linux:

```sh
swift build
swift test                                    # the validator's and the Templatr library's tests, and the components' detect and infer rules against fixtures
swift run validate-components                 # the manifests, and the guide's docs/anchors.md
```

and checks every link in the Markdown files with [lychee](https://github.com/lycheeverse/lychee). It also runs `swift test` on macOS, where the tests also run the `linear-workspace` component's script against a fake Linear API.

<!-- superlinear:begin how-this-is-built -->
<!-- templatr bootstrap writes this section from the components' manifests. Do not edit it. -->
## How this project is built

This project uses these components from [armcknight/templatr](https://github.com/armcknight/templatr):

* [base](https://github.com/armcknight/templatr/tree/v1/components/base) at `v1`: The project's root files, which every project has with its other components: the Makefile that includes each component's targets, and the README.md that links to each component's README.
* [github-repo](https://github.com/armcknight/templatr/tree/v1/components/github-repo) at `v1`: A repository on GitHub whose pull requests are squashed when they merge, and whose default branch cannot be deleted or force-pushed except by the owner.
* [linear-workspace](https://github.com/armcknight/templatr/tree/v1/components/linear-workspace) at `v1`: A Linear workspace that superlinear works from: each team has an In Review state, a Todo state, Triage and superlinear's labels, the owner has a view of the pending proposals, and no onboarding issue is open.

### Shared pieces

* [components/github-repo/bin/check-merge-options](https://github.com/armcknight/templatr/blob/v1/components/github-repo/bin/check-merge-options), script: Checks that pull requests merge only by squashing, titled with the pull request's title, that branches can be updated, and that they are deleted after a merge.
* [components/github-repo/bin/check-rulesets-available](https://github.com/armcknight/templatr/blob/v1/components/github-repo/bin/check-rulesets-available), script: Checks that GitHub offers rulesets for the repository, which it does not for a private repository on the free plan.
* [components/github-repo/bin/check-default-branch-protection](https://github.com/armcknight/templatr/blob/v1/components/github-repo/bin/check-default-branch-protection), script: Checks that a ruleset that the owner can bypass stops the default branch from being deleted or force-pushed, when GitHub offers rulesets for the repository.
* [components/github-repo/bin/protect-default-branch](https://github.com/armcknight/templatr/blob/v1/components/github-repo/bin/protect-default-branch), script: Makes or updates the Default branch ruleset, which stops the default branch from being deleted or force-pushed, with a bypass for the repository's admins.
* [components/linear-workspace/bin/linear-workspace](https://github.com/armcknight/templatr/blob/v1/components/linear-workspace/bin/linear-workspace), script: Checks, and sets up, a Linear workspace's teams' states, Triage and labels, the superlinear proposals view, the onboarding issues and the initiatives, with Linear's API and a key from the environment.

### Steps a person does

* The root Makefile includes each component's component.mk, and has the help and templates-update targets. If not: Copy the Makefile from the base scaffold, or add its TEMPLATES_TAG, NAMESPACES, TEMPLATES_FRAGMENTS, the include of */component.mk, the namespace rule, the fragment download rule, help and templates-update to the project's Makefile. Move the targets that were in it for one component, such as its VAPOR_FLY_* or APPLE_APP_* values, into that component's component.mk.
* The GitHub CLI is logged in. If not: Run `gh auth login` on this Mac, as the owner of the repository.
* The repository is on GitHub, and the logged-in user can administer it. If not: Push the repository to GitHub, with a remote that points to it, and run `gh auth login` as its owner or as an admin of it.
* GitHub offers rulesets for the repository: it is public, or its owner has a paid plan. If not: The repository is private on GitHub's free plan, so GitHub offers no rulesets, and nothing stops its default branch from being deleted or force-pushed. Make the repository public, or upgrade to GitHub Pro; or accept the risk.
* LINEAR_API_KEY, else LINCTL_API_KEY, is set, Linear accepts it, and its user is an admin of each team. If not: As the owner of the Linear workspace, make a personal API key in Linear's settings (Security & access), and export it as LINCTL_API_KEY in the project's .envrc. Its user must be an admin of the workspace or of each team.
* Each team has at least one state of type unstarted, such as Todo, which superlinear's ready mode starts issues from. If not: In each team's settings in Linear (Issue statuses & automations), add a status of the Todo type.
* When the project's spec should be under an initiative (linear_initiatives is true), the workspace has initiatives. If not: Turn on initiatives in the Linear workspace's settings (Initiatives), and make the project's initiative. The API cannot turn them on.

### Further reading

* [The life of an issue](https://github.com/armcknight/superlinear/blob/main/docs/lifecycle.md#overview)
* [Planning](https://github.com/armcknight/superlinear/blob/main/docs/planning.md#proposals)
* [Bootstrap](https://github.com/armcknight/superlinear/blob/main/docs/bootstrap.md#components)
* [Builds](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#ci)
* [bootstrap --check](https://github.com/armcknight/superlinear/blob/main/docs/bootstrap.md#bootstrap-check)
* [The pull request](https://github.com/armcknight/superlinear/blob/main/docs/lifecycle.md#pull-request)
* [The merge](https://github.com/armcknight/superlinear/blob/main/docs/lifecycle.md#merge)
* [A workspace's API key](https://github.com/armcknight/superlinear/blob/main/docs/configuration.md#api-key)
* [A workspace's teams](https://github.com/armcknight/superlinear/blob/main/docs/configuration.md#team-ids)
<!-- superlinear:end -->
