# The supabase component's targets, for the database whose Supabase CLI files
# are in this directory. The root Makefile includes this file; the fragment
# comes from armcknight/templatr at TEMPLATES_TAG.
#
# `make local-db <command>` runs local-db-<command>, such as `make local-db
# reset`. `make server refresh-ca` and `make server status-diff` are with the
# server's commands.
#
# Nothing here writes to the remote database. In the cli style, the deploy
# workflow applies the migrations; in the fluent style, the server does when it
# starts.

SUPABASE_MIGRATION_STYLE = {{inputs.migration_style}}
SUPABASE_PRODUCT = {{inputs.product}}
# The server's Swift package, which runs the Fluent migrations.
SUPABASE_PACKAGE_PATH = server
# The arguments that run the server's Fluent migrations and exit.
SUPABASE_MIGRATE_ARGS = migrate --yes
SUPABASE_DB_NAME = {{inputs.database_name}}
SUPABASE_PG_VERSION = {{inputs.pg_version}}
SUPABASE_CA_CERT = server/{{inputs.ca_cert_path}}
# The test database, the parity snapshots and the logs, which supabase/.gitignore
# ignores.
SUPABASE_TEST_DIR = supabase/.test-pgdata
SUPABASE_STATUS_DIR = supabase/status
SUPABASE_LOG_DIR = supabase
# Targets `make local-db reset` runs first, such as one that stops the server.
SUPABASE_DB_RESET_PREREQUISITES =

NAMESPACES += local-db
TEMPLATES_FRAGMENTS += $(TEMPLATES_MAKE)/supabase.mk

include $(TEMPLATES_MAKE)/supabase.mk

.PHONY: local-db-init local-db-reset local-db-migrate local-db-test-start local-db-test-stop local-db-status server-status-diff server-refresh-ca

## local-db-init: make the local database and run the migrations
local-db-init: supabase-db-init

## local-db-reset: delete the local database and make it again
local-db-reset: supabase-db-reset

## local-db-migrate: run the migrations that the local database does not have yet
local-db-migrate: supabase-db-migrate

## local-db-test-start: start the isolated test database
local-db-test-start: supabase-db-test-start

## local-db-test-stop: stop the isolated test database
local-db-test-stop: supabase-db-test-stop

## local-db-status: write the local database's state to supabase/status/local.json
local-db-status: supabase-db-status

## server-status-diff: compare the local and the remote databases; exits 1 when they differ
server-status-diff: supabase-status-diff

## server-refresh-ca: download Supabase's root CA and verify the database's TLS against it
server-refresh-ca: supabase-refresh-ca
