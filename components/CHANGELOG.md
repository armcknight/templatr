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

### Changed

- The supabase component needs `SUPABASE_ACCESS_TOKEN` and
  `SUPABASE_DB_PASSWORD` only when its `migration_style` is `cli`, with the
  manifests' new `when`. A `fluent` project no longer gets them as missing
  secrets or steps for a person, or in its README.

## [v2.0.0] 2026-11-06

### Added

- The static-site component: a website in `site/`, built with Jekyll, Hugo,
  Vite or nothing, served from a private S3 bucket through CloudFront. One
  CloudFormation template, `components/static-site/cloudformation/site.yml`,
  owns the bucket, the certificate, the distribution (with the managed
  security headers, a 404 page, and a viewer-request function for directory
  indexes, the trailing-slash redirect and the www redirect) and the DNS
  records; the `hosting-stack` step deploys it, and `templatr check` compares
  the stack with it. `make/static-site.mk` has `build`, `serve`,
  `endserve`, `deploy`, `bust-cache`, `invalidations`, `stack` and `status`.
  `make site deploy` refuses uncommitted changes, uploads the build, clears
  CloudFront, and commits `site/DEPLOYED`, the commit that is live, as
  `deploy(site): <commit>`; `https://<domain>/DEPLOYED` is the same file. The
  scaffold's `site/README.md` is the checklist of what a site needs before
  and after it is deployed: titles, descriptions, canonical links, Open Graph
  tags, icons, `404.html`, `robots.txt`, the sitemap, Search Console, Bing,
  the link-preview debuggers and the quality checks. Old domains in the
  `redirect_from` input, such as `armcknight.com tworingsoft.com`, each get a
  stack from `redirect.yml`: a certificate for the domain and its www, and a
  distribution whose function answers every request with a permanent redirect
  to the same path on the site; `make site redirects` makes them, and
  `templatr check` checks them and that each domain redirects. The manifest's
  `shared` pieces have a new kind, `template`.
- The linear-workspace component links the Linear workspace from the README's
  "Further reading". Its new input `linear_workspace` is the workspace's URL
  key, the path after `linear.app/`, which its script reads from the API with
  `print workspace` when the key is in the environment. A project that already
  uses the component gets the input on its next `bootstrap`.
- The root Makefile downloads its fragments to `.templatr/make/`, next to the
  components' `CLAUDE.md` copies, and no longer to `.superlinear/make/`. The
  base component's `.gitignore` check and fix follow. A project with the old
  directory can delete it: the fragments download again on first use.
- The root README's "How this project is built" section sits between
  `<!-- templatr:begin how-this-is-built -->` and `<!-- templatr:end -->`, the
  same family as the component sections, and no longer `superlinear:begin`. A
  README that has the old markers must be edited, or bootstrap adds a second
  section at its end.
- The Keychain items that every component's secrets come from are named
  `templatr.<name>`, such as `templatr.asc.key-id` and
  `templatr.fly.<app>.deploy-token`, and no longer `superlinear.<name>`. An
  item stored under the old name must be moved by hand: `security` has no
  rename, so read it with `find-generic-password -w`, add it under the new
  name, and delete the old one.
- The `mcknight-io-listing` component, for a project listed on mcknight.io's
  projects page: the `SITE_DISPATCH_TOKEN` repository secret, a fine-grained
  personal access token for armcknight/mcknight.io only, from the Keychain item
  `templatr.mcknight-io.dispatch-token` and made again each year, and a step
  that checks that each job that calls a workflow in armcknight/workflows has
  `secrets: inherit`, so that the shared workflows' notify step can ask the
  site to refresh. It is opt-in: it is detected only when `.templatr.toml`
  lists it.
- The `apple-app` component's `ASC_ADMIN_KEY_ID`, `ASC_ADMIN_ISSUER_ID` and
  `ASC_ADMIN_KEY_P8_BASE64` local secrets: the App Store Connect API key with
  the Admin role, which match needs to make or renew certificates and
  profiles. `templatr check` reports them as missing until they are in the
  Keychain.

### Changed

- The apple-app component's `app_name` is the name people see, which can have
  spaces, such as `Bae Today`: it is inferred from the display name
  (`INFOPLIST_KEY_CFBundleDisplayName`, else `APP_DISPLAY_NAME`) before
  `PRODUCT_NAME`. The staging IPA, `apple/fastlane/Fastfile`'s
  `APPLE_APP_NAME` and a new app's `PRODUCT_NAME` are the name without spaces,
  and a new app's display name is the name as given. The shared `stage` lane
  also removes spaces from `APPLE_APP_NAME`. A project whose name has no
  spaces changes nothing.
- The `make/*.mk` fragments write their logs to a `logs/` directory in the
  component's directory, such as `apple/logs/deploy-beta-44.log` and
  `server/logs/vapor-fly-deploy-abc1234.log`, and no longer next to the
  project files. The scaffolds' `.gitignore` files ignore `logs/`, and the
  supabase component's `gitignore` step checks for it. `APPLE_APP_LOG_DIR`,
  `VAPOR_FLY_LOG_DIR` and `SUPABASE_LOG_DIR` change the directory.

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
