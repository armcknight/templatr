# supabase

This project's server keeps its data in Postgres on [Supabase](https://supabase.com), with the `supabase` component from [armcknight/templatr](https://github.com/armcknight/templatr). `.templatr.toml` has the tag it is pinned to, and the component's inputs, such as its `migration_style`.

The component's files are in `supabase/`: in the `cli` style, the Supabase CLI's `config.toml` and `migrations/`, and its `component.mk`. Run `supabase` commands from the repository's root, where the CLI finds `supabase/config.toml`. The server, with its Dockerfile and `fly.toml`, is in `server/`. The `make local-db …` commands run from the repository's root.

## Databases

* `make local-db init` makes the local development database and runs the migrations; `make local-db reset` deletes it and makes it again; `make local-db migrate` runs only the new migrations. In the `cli` style they use the Supabase CLI's local stack (`supabase start`, `supabase db reset`); in the `fluent` style, Homebrew's Postgres and the server's `migrate` command.
* Tests use the isolated test database: `make local-db test-start`, at `SUPABASE_TEST_DATABASE_URL` (port 5433), and `make local-db test-stop`. Never point tests at the development database or the remote one.
* `make local-db status` writes the local database's tables, columns, row counts and migrations to `supabase/status/local.json`. `make server status-diff` compares them with the remote database's, and exits 1 when they differ. It only reads the remote database.

## Migrations

* `cli` style: each schema change is a new SQL file in `supabase/migrations`, made with `supabase migration new <name>`. Never edit a migration that is on the default branch: the remote database has run it. The deploy workflow applies new migrations with `supabase db push` before it deploys, and a failed migration stops the deploy.
* `fluent` style: each schema change is a new Fluent migration, added to the list after the others. Never edit or reorder a migration that is on the default branch. The server applies the migrations when it starts, so a deploy applies them.
* A migration must work on the database as the remote one is, with its data: add columns with a default or as optional, and change data in the migration, not by hand.

## TLS

* Supabase's databases chain to Supabase's own root CA, which the system does not trust. The server keeps it, such as `server/deploy/supabase-root-2021-ca.crt`; `server/Dockerfile` copies it into the image, and an environment variable in `server/fly.toml`'s `[env]` gives the server its path.
* When that variable is set, the server requires TLS and verifies the database's certificate against that file, with `TLSConfiguration.makeClientConfiguration()`, `trustRoots = .file(path)` and `certificateVerification = .fullVerification`. Without it, as in local runs, it uses the connection string's `sslmode`. Do not turn verification off to make a connection work.
* `make server refresh-ca` downloads the CA again and verifies against it, when Supabase changes it.

## Rules

* Never write to the remote database: do not run `supabase db push`, `supabase db reset --linked`, `supabase migration repair`, or `psql` with `DATABASE_URL`, and do not start the Deploy workflow. Only the owner changes the remote database, through a deploy.
* `DATABASE_URL` is a Fly secret and is in the owner's `.envrc`, which git ignores. Never put a connection string, a password or an access token in a file, a commit or a log. The root's `.envrc.example` has the names only.
* Settings of the Supabase project that are not in `supabase/config.toml`, such as Auth providers, are changed by the owner in Supabase's dashboard. Name a needed change in the pull request description.
* The `supabase-*` targets come from the templatr repository; `supabase/component.mk` includes them from `make/supabase.mk`, and the root Makefile includes `supabase/component.mk`. Do not copy them into this project. To change them, change the templatr repository and move this project to its new tag.

## Further reading

* [Secrets](https://github.com/armcknight/superlinear/blob/main/docs/bootstrap.md#secrets)
* [Steps that need a person](https://github.com/armcknight/superlinear/blob/main/docs/bootstrap.md#needs-human-steps)
* [The release rule](https://github.com/armcknight/superlinear/blob/main/docs/builds.md#release-rule)
