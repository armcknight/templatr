# {{inputs.product}}

A Swift server built with Vapor, at https://{{inputs.fly_app}}.fly.dev. Its Swift package, Dockerfile and fly.toml are in this directory.

Run these from the repository's root:

* `make server serve` runs it on this Mac, and `make server serve-docker` runs its image with docker compose.
* `make server deploy` deploys it to Fly.io. Only the owner deploys.
* `brew bundle --file server/Brewfile` installs the tools that these commands use.
