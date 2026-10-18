# Project layout

Each component's files are in its own directory, such as `server/` for the server and `apple/` for the Apple app, with that directory's README.md, .gitignore and Brewfile. Only the files that every component shares are at the root: the Makefile, README.md, CLAUDE.md and `.github/workflows/`, where each workflow's name starts with its component's name, such as `vapor-fly-ci.yml`.

Run `make` at the root. `make <namespace> <command>`, such as `make server deploy` or `make apple test`, runs the target `<namespace>-<command>` from that directory's `component.mk`, which the root Makefile includes. A command of more than one word has its words joined with dashes: `make apple ios test` runs `apple-ios-test`. `make help` lists every target.

Put a new target for one part of the project in its directory's `component.mk`, named with the namespace first. Do not edit the files in `.superlinear/make/`: they are downloaded from armcknight/templatr at TEMPLATES_TAG.

The root README.md's "How this project is built" section and the components' summaries between `<!-- templatr:begin <component> -->` and `<!-- templatr:end -->` are written by `templatr bootstrap`. Do not edit them by hand.
