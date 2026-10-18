# linear-workspace

superlinear works on this project from a Linear workspace, set up with the `linear-workspace` component from [armcknight/templatr](https://github.com/armcknight/templatr). `.templatr.toml` has the tag it is pinned to, and in `linear_teams` the teams it checks.

## The key

* The project's `.envrc` exports the owner's Linear API key as `LINCTL_API_KEY`, for `linctl` and for `templatr check`. Run commands that need it with `direnv exec . <command>`.
* Never print the key, never put it on a command line, and never commit `.envrc`: git ignores it.

## Rules

* Do not remove or rename a team's "In Review" or Todo states, its labels `Needs human`, `superlinear`, `superlinear: proposed`, `superlinear: spec` and `superlinear: hands off`, or the "superlinear proposals" view, and do not turn Triage off: superlinear uses them, and `templatr check` checks them.
* The issues Linear makes in a new workspace ("Get familiar with Linear", "Set up your teams", "Connect your tools", "Import your data") are not tasks. Do no work for them.

## Further reading

* [Proposals](https://github.com/armcknight/superlinear/blob/main/docs/planning.md#proposals)
* [The pull request](https://github.com/armcknight/superlinear/blob/main/docs/lifecycle.md#pull-request)
* [A workspace's API key](https://github.com/armcknight/superlinear/blob/main/docs/configuration.md#api-key)
* [`bootstrap --check`](https://github.com/armcknight/superlinear/blob/main/docs/bootstrap.md#bootstrap-check)
