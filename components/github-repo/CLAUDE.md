# github-repo

This project is on GitHub, with the `github-repo` component from [armcknight/templatr](https://github.com/armcknight/templatr). `.templatr.toml` has the tag it is pinned to.

## Pull requests

* Pull requests merge only by squashing. The squashed commit on the default branch has the pull request's title, so write the title as a conventional commit, such as `feat(api): add the health check`.
* GitHub deletes a pull request's branch after it merges. Do not push to a branch whose pull request has merged; start a new branch from the default branch.
* When a pull request's base branch moves ahead of it, bring it up to date by merging the base branch into it. Never rebase or force-push a pull request's branch: see [never rewritten](https://github.com/armcknight/superlinear/blob/main/docs/lifecycle.md#never-rewritten).

## Rules

* Never force-push to the default branch, and never delete it. A ruleset stops both; only the owner can bypass it, and an agent never asks to. A private repository on GitHub's free plan has no rulesets, so nothing stops either there: the rule still holds.
* Do not change the repository's merge settings or its rulesets without being asked: `templatr check` checks them.

## Further reading

* [The pull request](https://github.com/armcknight/superlinear/blob/main/docs/lifecycle.md#pull-request)
* [The merge](https://github.com/armcknight/superlinear/blob/main/docs/lifecycle.md#merge)
* [`bootstrap --check`](https://github.com/armcknight/superlinear/blob/main/docs/bootstrap.md#bootstrap-check)
