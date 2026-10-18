# The supabase component's targets come from armcknight/templatr at
# TEMPLATES_TAG. The Makefile includes this file; the fragment is downloaded on
# first use, and `make templates-update` downloads it again.
#
# `make local-db <command>` runs local-db-<command>, such as `make local-db
# reset`. `make server refresh-ca` and `make server status-diff` are with the
# server's commands. The direct forms, such as `make local-db-reset`, work too.
#
# Nothing here writes to the remote database. In the cli style, the deploy
# workflow applies the migrations; in the fluent style, the server does when it
# starts.

# This file, for local-db-help; read before the include below.
LOCAL_DB_MAKEFILE := $(lastword $(MAKEFILE_LIST))

TEMPLATES_TAG ?= {{templates.tag}}
TEMPLATES_MAKE ?= .superlinear/make
SUPABASE_MIGRATION_STYLE = {{inputs.migration_style}}
SUPABASE_PRODUCT = {{inputs.product}}
# The arguments that run the server's Fluent migrations and exit.
SUPABASE_MIGRATE_ARGS = migrate --yes
SUPABASE_DB_NAME = {{inputs.database_name}}
SUPABASE_PG_VERSION = {{inputs.pg_version}}
SUPABASE_CA_CERT = {{inputs.ca_cert_path}}
# Targets `make local-db reset` runs first, such as one that stops the server.
SUPABASE_DB_RESET_PREREQUISITES =

include $(TEMPLATES_MAKE)/supabase.mk

$(TEMPLATES_MAKE)/supabase.mk:
	mkdir -p $(@D)
	curl -fsSL https://raw.githubusercontent.com/armcknight/templatr/$(TEMPLATES_TAG)/make/supabase.mk -o $@

# `make local-db <command>`, when the Makefile does not list local-db in its
# NAMESPACES already. The words after local-db do nothing by themselves.
ifeq ($(firstword $(MAKECMDGOALS)),local-db)
ifeq ($(filter local-db,$(NAMESPACES)),)
LOCAL_DB_CMD := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
.PHONY: local-db
local-db:
	@$(MAKE) --no-print-directory $(if $(strip $(LOCAL_DB_CMD)),local-db-$(LOCAL_DB_CMD),local-db-help)
%:
	@:
endif
endif

.PHONY: local-db-help local-db-init local-db-reset local-db-migrate local-db-test-start local-db-test-stop local-db-status server-status-diff server-refresh-ca

## local-db-help: list these targets
local-db-help:
	@awk '/^## /{ t = substr($$0, 4); c = index(t, ":"); printf "  make %-28s %s\n", substr(t, 1, c - 1), substr(t, c + 2) }' $(LOCAL_DB_MAKEFILE)

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

## local-db-status: write the local database's state to status/local.json
local-db-status: supabase-db-status

## server-status-diff: compare the local and the remote databases; exits 1 when they differ
server-status-diff: supabase-status-diff

## server-refresh-ca: download Supabase's root CA and verify the database's TLS against it
server-refresh-ca: supabase-refresh-ca
