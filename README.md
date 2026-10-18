# templatr

Components: reusable parts of a project, such as an Apple app, a Swift command-line tool, a Vapor server on Fly, or a Supabase database. Each one says how to recognize a project that uses it, what it needs to know about the project, which secrets it needs and where they come from, what to check and set up, and which shared workflows, lanes and Makefile fragments it uses.

Shared lanes and Makefile fragments are here. Reusable GitHub workflows are in [armcknight/workflows](https://github.com/armcknight/workflows), and the components' scaffolds call them.

The `templatr` command, and the `Templatr` library under it, read the components and set projects up with them: see [Setting up a project](#setting-up-a-project). [superlinear](https://github.com/armcknight/superlinear)'s `bootstrap` command uses the library. People can also follow a manifest by hand.

This repository holds no secrets: only their names and where to get them.

## Components

| Component | What it sets up |
| --- | --- |
| [apple-app](components/apple-app) | An iOS (with an optional embedded watch app), tvOS or macOS app, tested on each pull request, with staging builds on demand, and uploaded to TestFlight by hand with `make deploy-beta`. |
| [github-repo](components/github-repo) | A repository on GitHub whose pull requests are squashed when they merge, with their branches deleted, and whose default branch cannot be deleted or force-pushed except by the owner. |
| [vapor-fly](components/vapor-fly) | A Swift server built with Vapor and run on Fly.io, built and tested on Linux on each pull request, and deployed by the owner, by hand with `make server deploy` or on a merge. |

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
schema/check-report.schema.json    the format of `templatr check --json`
Package.swift                      the libraries and the commands
Sources/ComponentManifest/         the manifest's types and the checks
Sources/validate-components/       the validator command
Sources/Templatr/                  the library that sets projects up
Sources/TemplatrCLI/               the templatr command
Tests/ComponentManifestTests/      the validator's tests
Tests/TemplatrTests/               the Templatr library's tests
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
| [components/vapor-fly/bin/check-fly-secrets](components/vapor-fly/bin/check-fly-secrets) | script | vapor-fly | Checks that the Fly app has each runtime secret, by name. |
| [components/github-repo/bin/check-merge-options](components/github-repo/bin/check-merge-options) | script | github-repo | Checks that pull requests merge only by squashing, titled with the pull request's title, that GitHub offers to update their branches, and that it deletes them after a merge. |
| [components/github-repo/bin/check-rulesets-available](components/github-repo/bin/check-rulesets-available) | script | github-repo | Checks that GitHub offers rulesets for the repository, which it does not for a private repository on the free plan. |
| [components/github-repo/bin/check-default-branch-protection](components/github-repo/bin/check-default-branch-protection) | script | github-repo | Checks that a ruleset that the owner can bypass stops the default branch from being deleted or force-pushed, when GitHub offers rulesets for the repository. |
| [components/github-repo/bin/protect-default-branch](components/github-repo/bin/protect-default-branch) | script | github-repo | Makes or updates the `Default branch` ruleset, which stops the default branch from being deleted or force-pushed, with a bypass for the repository's admins. |

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

`templatr bootstrap` writes it from the manifests of the components the project uses, and changes nothing outside the markers. It has a "How this project is built" heading and:

* the components the project uses, each linked to `components/<name>` here at the pinned tag;
* each shared workflow, lane, Makefile fragment and Brewfile the project uses, linked here at the pinned tag, or in its own repository at its `version`;
* the secrets by name, never their values, with where each comes from, and the human steps;
* links to the superlinear guide's [life of an issue](https://github.com/armcknight/superlinear/blob/main/docs/lifecycle.md#overview), [planning](https://github.com/armcknight/superlinear/blob/main/docs/planning.md#proposals), [bootstrap](https://github.com/armcknight/superlinear/blob/main/docs/bootstrap.md#components) and [builds](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#ci) sections, and to the components' own `docs` anchors;
* a link to the project's Linear team and, when it has one, its spec document.

## Setting up a project

Run `templatr` from a checkout of this repository. It is not in a Homebrew tap.

```sh
git clone https://github.com/armcknight/templatr && cd templatr
swift run templatr bootstrap ~/Code/babysittr     # set the project up
swift run templatr check ~/Code/babysittr         # report what it still needs, and change nothing
```

`bootstrap` needs `gh`, logged in, in the project's directory to read and set its secrets; `security` for the Keychain; `op` for 1Password secrets; and `xcodebuild` for build settings. `{{templates}}` in the steps is the checkout it runs from.

### `templatr bootstrap [<repository>]`

1. **Which components.** On the first run it matches each component's `detect` rules against the repository; it can find more than one. It reads each input from where its `infer` says, then shows the values it found to confirm, and asks for the ones it did not find. Leave an answer empty to skip it: the steps and scaffold files that need it wait for a later run.
2. **The record.** It writes `.templatr.toml` at the repository's root: each component, the tag it is pinned to, and its inputs. Later runs read it instead of detecting again, and a change made to it by hand wins. A component that detection finds later, such as a watch app added to the project, is reported, not added: add it to the file to use it.

   ```toml
   [components.apple-app]
   tag = "v1"

   [components.apple-app.inputs]
   bundle_id = "io.mcknight.babysittr"
   ```

3. **Scaffold.** It copies each scaffold file that the project does not have yet, with its placeholders filled in. It never overwrites a file.
4. **Steps.** It runs each step's `check`, and its `fix` command when the check fails, then the check again. A failing step whose fix is `human` is reported with its text, whether it needs two-factor, and links to the manifest and the guide. A step that is done one time for each app (`scope = "app"`) runs one time.
5. **Secrets.** It reads the repository's secret names with `gh secret list`. For each missing one, after it asks, it reads the value from its `source` and gives it to `gh secret set` on standard input. A `generate:` secret is made on this Mac and stored first in the Keychain item `superlinear.<name>`, such as `superlinear.match-deploy-key`, with an SSH key's public half in `superlinear.<name>.pub`. A `local` secret is only looked for in the Keychain, and never set in GitHub. Values never go to a log, the output or a file.
6. **README and CLAUDE.md.** It writes the README's "How this project is built" section between its markers, adding them at the end when the README does not have them, and changes nothing outside them. It copies each component's `CLAUDE.md` to `.templatr/<name>/CLAUDE.md` and imports those copies in the project's `CLAUDE.md`, between `<!-- templatr:begin components -->` and `<!-- templatr:end -->`.

It then reports what is left, as `check` does. Running it again changes nothing that is already done.

Options: `--yes` accepts the inputs found and sets missing secrets without asking; without a terminal, nothing is asked, and secrets are set only with `--yes`. `--link TITLE=URL`, which can be given more than one time, adds a link to the README section, such as the project's Linear team or spec document. `--tag TAG` is the tag new components are pinned to, the checkout's newest `v*` tag by default, and `--templates DIR` another checkout of this repository.

### `templatr check [<repository>] [--json]`

The checks only; it changes nothing. It reports the steps whose checks fail, the human steps, the inputs and the secrets that are missing (by name), secrets due for a new value within 30 days of their `rotateEvery`, components pinned to a tag older than the newest, and links in the README that no longer resolve. `--offline` skips the web links.

With `--json`, it prints the report in the format of [schema/check-report.schema.json](schema/check-report.schema.json), which superlinear reads. Its `version` changes only when a change would break a reader.

The exit status is 0 when nothing is left to do, 1 when the report lists something or an error stops the run, and 64 for a usage error. `templatr --help` and `templatr <subcommand> --help` show all the options.

## Adding a component

1. Make `components/<name>/` with `component.toml`, `CLAUDE.md` and `scaffold/README.md` with the markers.
2. Put shared lanes, Makefile fragments and scripts at the top level, and reusable workflows in armcknight/workflows. Add them to the manifest's `shared` and to the table above.
3. Add any new guide section to superlinear's `docs/`, with its anchor listed in `docs/anchors.md`, first.
4. Run the checks below, then tag a release.

## The package

[Package.swift](Package.swift) has four products:

* `ComponentManifest`, a library: `Manifest` and its `Codable` types for `component.toml`, and `Validator`, the checks below. Decoding is strict: an unknown key, an empty text, a value that does not match its pattern, or an empty list is an error with its path in the file, such as `secrets/0/source`. The library does not run `detect` rules or `infer` rules; the `Templatr` library below does that on these types. The validator's tests have their own reference that runs them, `Tests/ComponentManifestTests/Detection.swift`, to test each component's rules against fixtures taken from the projects it comes from; set `MTG_REPOSITORY` to a checkout of mtg to also test `vapor-fly` against it.
* `validate-components`, a command: `validate-components [--root DIR] [--anchors PATH_OR_URL|none]`. The root is the current directory by default. The anchors come from superlinear's `docs/anchors.md` on `main` by default; a path or a URL replaces that, and `none` skips the check. It prints each problem to stderr and exits 1 when there are any.
* `Templatr`, a library on the `ComponentManifest` types: `Bootstrapper`'s `resolve`, `bootstrap` and `check` do what [Setting up a project](#setting-up-a-project) says, and return a `Report`, the same values that `check --json` prints. It knows nothing of Linear: superlinear turns the report into issues. The programs it runs, the Keychain, 1Password and GitHub are behind the protocols in `Services`, which the tests replace.
* `templatr`, a command: a thin layer on the library, which asks the questions.

The package builds on macOS and Linux. [TOMLKit](https://github.com/LebJe/TOMLKit) parses the TOML, and [Yams](https://github.com/jpsim/Yams) the YAML.

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
swift test                                    # the validator's and the Templatr library's tests, and the components' detect and infer rules against fixtures
swift run validate-components                 # the manifests, and the guide's docs/anchors.md
```

and checks every link in the Markdown files with [lychee](https://github.com/lycheeverse/lychee).
