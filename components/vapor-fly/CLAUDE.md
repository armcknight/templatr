# vapor-fly

This project is a Swift server built with Vapor and run on [Fly.io](https://fly.io), with the `vapor-fly` component from [armcknight/templatr](https://github.com/armcknight/templatr). `.superlinear/components.toml` has the tag it is pinned to.

## Building and testing

* `make server build` builds the server, and `make server serve` runs it on this Mac. `make server serve-docker` runs the image that Fly runs, with docker compose, for Linux parity.
* `swift test` runs the tests. CI builds and tests the package on Linux in the swift image on each pull request, and builds the Docker image, through `vapor-ci.yml` from [armcknight/workflows](https://github.com/armcknight/workflows). Code that builds on macOS can fail on Linux: Foundation differs, and Darwin-only packages do not build. Put a Darwin-only dependency behind `condition: .when(platforms: [.macOS])`.
* The Swift version in the Dockerfile's `FROM swift:` lines and in the `swift-image` of `.github/workflows/ci.yml` stay the same.

## The health check

* The path in `fly.toml`'s `[[http_service.checks]]` answers 200 when the server is ready, and its body has the `GIT_SHA` environment variable: the commit the image was built from. A deploy waits until the body has the new commit, so do not remove it from the answer.
* The health check needs no login and no database write. Keep it fast: Fly calls it every 30 seconds, and a machine that does not answer is restarted.

## Web pages

When `resources/templates` exists, the server also serves web pages: it renders the HTML templates there (with Leaf, when the project uses it), and serves CSS, JS and images from `resources` or `Public`, which the Dockerfile copies into the image. The image reads them relative to `/app`, its working directory. When pages use htmx, a route that htmx calls returns a fragment of HTML, not a whole page. There is no separate web frontend: the pages are part of the server.

## Rules

* Never deploy. Do not run `make server deploy`, `fly deploy`, `fly secrets set` or `fly secrets import`, and do not start the Deploy workflow. Only the owner deploys, by hand or by merging. `make server deploy` refuses a dirty checkout, or one that is not the tip of the default branch.
* Do not change `deploy-on` in `.github/workflows/deploy.yml`, `fly.toml`'s `app`, its scaling settings or its `[[vm]]` size without being asked: each of them changes what runs or what it costs.
* Runtime secrets, such as `DATABASE_URL`, are Fly secrets. Never put a value in `fly.toml`, the Dockerfile, `docker-compose.yml` or a log. `docker-compose.yml` has local values only.
* A new runtime secret is a change the owner must act on: name it in the pull request description, and read it from the environment with a clear error when it is missing.
* The CI and deploy workflows in `.github/workflows/` call armcknight/workflows at its major tag. Do not point them at `main`.
* The `vapor-fly-*` targets come from the templatr repository; the Makefile includes them from `make/vapor-fly.mk`. Do not copy them into this project. To change them, change the templatr repository and move this project to its new tag.
* Never print, log or commit a secret's value. The secrets are named in the README's "How this project is built" section.

## Further reading

* [CI](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#ci)
* [The release rule](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#release-rule)
* [Secrets](https://github.com/armcknight/superlinear/blob/main/docs/bootstrap.md#secrets)
