# {{inputs.product}}

The server's database is Postgres on [Supabase](https://supabase.com), in the project {{inputs.project_ref}}.

* `make local-db init` makes the local database, and `make local-db reset` makes it again. `make local-db test-start` starts an isolated database for the tests.
* `make server status-diff` compares the local and the remote databases.

<!-- superlinear:begin how-this-is-built -->
<!-- superlinear:end -->
