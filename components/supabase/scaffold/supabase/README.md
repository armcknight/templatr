# Database

The server's Postgres database, on Supabase, with the `{{inputs.migration_style}}` migration style. In the `cli` style, the Supabase CLI's `config.toml` and `migrations/` are in this directory.

Run these from the repository's root:

* `make local-db init` makes the local development database and runs the migrations, `make local-db reset` deletes it and makes it again, and `make local-db migrate` runs only the new migrations.
* `make local-db test-start` starts the isolated test database on port 5433, and `make local-db test-stop` stops it.
* `make local-db status` writes the local database's tables, columns, row counts and migrations to `supabase/status/local.json`, and `make server status-diff` compares them with the remote database's.
* `make server refresh-ca` downloads Supabase's root CA to `server/{{inputs.ca_cert_path}}`, which the server's image copies in.

`DATABASE_URL`, the remote database's connection string, is in the root's `.envrc`, which git ignores; `.envrc.example` names it.
