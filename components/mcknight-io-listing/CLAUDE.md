# mcknight-io-listing

This project is listed on [mcknight.io](https://mcknight.io)'s projects page, with the `mcknight-io-listing` component from [armcknight/templatr](https://github.com/armcknight/templatr). `.templatr.toml` has the tag it is pinned to.

When the project releases or merges to its default branch, the shared workflows from [armcknight/workflows](https://github.com/armcknight/workflows) ask mcknight.io to refresh its projects page, with the repository secret `SITE_DISPATCH_TOKEN`.

## Rules

* Each job in `.github/workflows/` that calls a workflow in armcknight/workflows has `secrets: inherit`, so that the notify step gets the token. Keep it when you add or change such a job: `templatr check` checks it.
* Never print, log or commit the token. It is a fine-grained personal access token for armcknight/mcknight.io only, and the owner makes a new one each year.
* The component is chosen in `.templatr.toml`, not detected: do not add it to a project, or remove it, without being asked.

## Further reading

* [Secrets](https://github.com/armcknight/superlinear/blob/main/docs/bootstrap.md#secrets)
* [CI](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#ci)
