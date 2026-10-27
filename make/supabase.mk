# The supabase component's Makefile targets. A project's supabase/component.mk,
# from the supabase scaffold, includes this file, which the root Makefile
# downloads at its pinned tag, and maps `make local-db <command>` and `make
# server <command>` to these targets. The targets are namespaced so that the project's own targets can
# depend on them, or do more, such as importing data after supabase-db-init.
#
# Set these before the include, as make reads a rule's prerequisites when it
# reads the rule:
#
#   TEMPLATES_TAG                  the templatr tag that the scripts are downloaded at
#   TEMPLATES_MAKE                 where the fragments and the scripts are downloaded to
#   SUPABASE_MIGRATION_STYLE       cli: SQL in supabase/migrations, run by the Supabase CLI;
#                                  fluent: Fluent migrations, run by the server
#   SUPABASE_PRODUCT               the executable product that runs the server (fluent)
#   SUPABASE_PACKAGE_PATH          the directory of the server's Swift package (fluent)
#   SUPABASE_MIGRATE_ARGS          the arguments that run its migrations (fluent)
#   SUPABASE_DB_NAME               the local development database (fluent)
#   SUPABASE_PG_VERSION            the major version of Homebrew's postgresql@<version>
#   SUPABASE_CA_CERT               where the repository keeps Supabase's root CA certificate
#   SUPABASE_DB_RESET_PREREQUISITES targets supabase-db-reset runs first, such as stopping the server
#   SUPABASE_TEST_DIR              the test database's data directory
#   SUPABASE_STATUS_DIR            where supabase-db-status and supabase-status-diff write the snapshots
#   SUPABASE_LOG_DIR               where the targets write their logs
#
# The remote database is DATABASE_URL in the environment, as direnv exports it
# from .envrc. Nothing here writes to it.
#
# supabase comes from supabase/tap/supabase, and psql, pg_ctl and the other
# Postgres tools from postgresql@$(SUPABASE_PG_VERSION).

TEMPLATES_TAG ?=
TEMPLATES_MAKE ?= .templatr/make
SUPABASE_MIGRATION_STYLE ?= fluent
SUPABASE_PRODUCT ?=
SUPABASE_PACKAGE_PATH ?= .
SUPABASE_MIGRATE_ARGS ?= migrate --yes
SUPABASE_DB_NAME ?= postgres
SUPABASE_PG_VERSION ?= 17
SUPABASE_CA_CERT ?= deploy/supabase-root-2021-ca.crt
SUPABASE_DB_RESET_PREREQUISITES ?=

# The isolated test database: its own Postgres server, on its own port and
# data directory, so that tests never touch the development database.
SUPABASE_TEST_PORT ?= 5433
SUPABASE_TEST_DIR ?= .test-pgdata
SUPABASE_TEST_DATABASE_URL ?= postgres://$(USER)@localhost:$(SUPABASE_TEST_PORT)/postgres

SUPABASE_STATUS_DIR ?= status
SUPABASE_LOG_DIR ?= .
SUPABASE_BREW_PREFIX := $(shell brew --prefix 2>/dev/null)
SUPABASE_PG_BIN ?= $(SUPABASE_BREW_PREFIX)/opt/postgresql@$(SUPABASE_PG_VERSION)/bin
# macOS's openssl cannot start TLS in the Postgres protocol; OpenSSL 3 can.
SUPABASE_OPENSSL ?= $(SUPABASE_BREW_PREFIX)/opt/openssl@3/bin/openssl

# The local development database. The Supabase CLI's local stack listens on
# 54322 with these credentials; a fluent project's database is in Homebrew's
# Postgres, on the default port.
ifeq ($(SUPABASE_MIGRATION_STYLE),cli)
SUPABASE_LOCAL_DATABASE_URL ?= postgresql://postgres:postgres@127.0.0.1:54322/postgres
else
SUPABASE_LOCAL_DATABASE_URL ?= postgres://localhost:5432/$(SUPABASE_DB_NAME)
endif

# The scripts that the targets run, downloaded from templatr at TEMPLATES_TAG
# on first use, like the fragments.
SUPABASE_BIN = $(TEMPLATES_MAKE)/supabase
SUPABASE_SCRIPTS = $(SUPABASE_BIN)/db-snapshot $(SUPABASE_BIN)/db-snapshot-diff $(SUPABASE_BIN)/supabase-ca

$(SUPABASE_BIN)/%:
	@test -n "$(TEMPLATES_TAG)" || { echo "Set TEMPLATES_TAG to the templatr tag that the project is pinned to." >&2; exit 1; }
	mkdir -p $(@D)
	curl -fsSL https://raw.githubusercontent.com/armcknight/templatr/$(TEMPLATES_TAG)/components/supabase/bin/$* -o $@
	chmod +x $@

# The recipes use pipefail, which /bin/sh may not have.
SHELL := /bin/bash

.PHONY: supabase-db-init supabase-db-reset supabase-db-migrate supabase-db-test-start supabase-db-test-stop supabase-db-status supabase-status-diff supabase-refresh-ca supabase-style supabase-database-url

## supabase-db-init: make the local database and run the migrations
supabase-db-init: supabase-style
ifeq ($(SUPABASE_MIGRATION_STYLE),cli)
	@# supabase start applies supabase/migrations and supabase/seed.sql the first time.
	@set -o pipefail; supabase start 2>&1 | tee $(SUPABASE_LOG_DIR)/supabase-db-init.log
else
	@set -o pipefail; { \
	  export PATH="$(SUPABASE_PG_BIN):$$PATH"; \
	  if psql -lqt | cut -d '|' -f 1 | grep -qw "$(SUPABASE_DB_NAME)"; then \
	    echo "The database $(SUPABASE_DB_NAME) exists."; \
	  else \
	    createdb "$(SUPABASE_DB_NAME)" && echo "Made the database $(SUPABASE_DB_NAME)."; \
	  fi; \
	} 2>&1 | tee $(SUPABASE_LOG_DIR)/supabase-db-init.log
	@$(MAKE) --no-print-directory supabase-db-migrate
endif

## supabase-db-reset: delete the local database and make it again
supabase-db-reset: supabase-style $(SUPABASE_DB_RESET_PREREQUISITES)
ifeq ($(SUPABASE_MIGRATION_STYLE),cli)
	@set -o pipefail; supabase db reset 2>&1 | tee $(SUPABASE_LOG_DIR)/supabase-db-reset.log
else
	@set -o pipefail; PATH="$(SUPABASE_PG_BIN):$$PATH" dropdb --if-exists "$(SUPABASE_DB_NAME)" 2>&1 | tee $(SUPABASE_LOG_DIR)/supabase-db-reset.log
	@$(MAKE) --no-print-directory supabase-db-init
endif

## supabase-db-migrate: run the migrations that the local database does not have yet
supabase-db-migrate: supabase-style
ifeq ($(SUPABASE_MIGRATION_STYLE),cli)
	@set -o pipefail; supabase migration up 2>&1 | tee $(SUPABASE_LOG_DIR)/supabase-db-migrate.log
else
	@test -n "$(SUPABASE_PRODUCT)" || { echo "Set SUPABASE_PRODUCT to the executable product that runs the migrations." >&2; exit 1; }
	@set -o pipefail; swift run --package-path $(SUPABASE_PACKAGE_PATH) $(SUPABASE_PRODUCT) $(SUPABASE_MIGRATE_ARGS) 2>&1 | tee $(SUPABASE_LOG_DIR)/supabase-db-migrate.log
endif

# The test database is made the first time; to make it again, run
# supabase-db-test-stop and delete SUPABASE_TEST_DIR. In the cli style, its
# migrations are applied with psql when it is made: a migration that needs the
# roles or the extensions of Supabase's stack needs the local stack instead.
# Postgres on macOS does not start without a locale, so LC_ALL is C when it is
# not set.
## supabase-db-test-start: start the isolated test database, at SUPABASE_TEST_DATABASE_URL
supabase-db-test-start: supabase-style
	@set -o pipefail; { \
	  export PATH="$(SUPABASE_PG_BIN):$$PATH"; \
	  export LC_ALL="$${LC_ALL:-C}"; \
	  made=0; \
	  if [ ! -d "$(SUPABASE_TEST_DIR)" ]; then \
	    echo "Making the test database in $(SUPABASE_TEST_DIR)..."; \
	    initdb -D "$(SUPABASE_TEST_DIR)" --no-locale -E UTF8 >/dev/null || exit 1; \
	    made=1; \
	  fi; \
	  if pg_ctl -D "$(SUPABASE_TEST_DIR)" status >/dev/null 2>&1; then \
	    echo "The test database is running."; \
	  else \
	    echo "Starting the test database on port $(SUPABASE_TEST_PORT)..."; \
	    pg_ctl -D "$(SUPABASE_TEST_DIR)" -o "-p $(SUPABASE_TEST_PORT)" -l "$(SUPABASE_TEST_DIR)/logfile" -w start || exit 1; \
	  fi; \
	  if [ "$$made" = 1 ] && [ "$(SUPABASE_MIGRATION_STYLE)" = cli ]; then \
	    for f in supabase/migrations/*.sql; do \
	      [ -e "$$f" ] || continue; \
	      echo "Applying $$f"; \
	      psql "$(SUPABASE_TEST_DATABASE_URL)" -q -v ON_ERROR_STOP=1 -f "$$f" || exit 1; \
	    done; \
	  fi; \
	  echo "The test database is at $(SUPABASE_TEST_DATABASE_URL)"; \
	} 2>&1 | tee $(SUPABASE_LOG_DIR)/supabase-db-test-start.log

## supabase-db-test-stop: stop the isolated test database
supabase-db-test-stop:
	@PATH="$(SUPABASE_PG_BIN):$$PATH" pg_ctl -D "$(SUPABASE_TEST_DIR)" stop 2>&1 | tee $(SUPABASE_LOG_DIR)/supabase-db-test-stop.log || echo "The test database is not running."

## supabase-db-status: write the local database's state to SUPABASE_STATUS_DIR/local.json
supabase-db-status: $(SUPABASE_BIN)/db-snapshot
	@set -o pipefail; \
	PATH="$(SUPABASE_PG_BIN):$$PATH" DATABASE_URL="$(SUPABASE_LOCAL_DATABASE_URL)" \
	  $(SUPABASE_BIN)/db-snapshot local "$(SUPABASE_STATUS_DIR)/local.json" 2>&1 | tee $(SUPABASE_LOG_DIR)/supabase-db-status.log

# Only reads the remote database. It exits 1 when the two differ, so a deploy
# can run it first.
## supabase-status-diff: compare the local and the remote databases' tables, columns, row counts and migrations
supabase-status-diff: supabase-database-url supabase-db-status $(SUPABASE_BIN)/db-snapshot $(SUPABASE_BIN)/db-snapshot-diff
	@set -o pipefail; { \
	  PATH="$(SUPABASE_PG_BIN):$$PATH" $(SUPABASE_BIN)/db-snapshot remote "$(SUPABASE_STATUS_DIR)/remote.json" >/dev/null && \
	  $(SUPABASE_BIN)/db-snapshot-diff "$(SUPABASE_STATUS_DIR)/local.json" "$(SUPABASE_STATUS_DIR)/remote.json"; \
	} 2>&1 | tee $(SUPABASE_LOG_DIR)/supabase-status-diff.log

# The host is SUPABASE_DB_HOST, or DATABASE_URL's. The certificate is public;
# commit it. The Dockerfile copies it into the image.
## supabase-refresh-ca: download Supabase's root CA to SUPABASE_CA_CERT and verify the database's TLS against it
supabase-refresh-ca: $(SUPABASE_BIN)/supabase-ca
	@set -o pipefail; { \
	  host="$${SUPABASE_DB_HOST:-$$(printf '%s' "$$DATABASE_URL" | sed -E 's#^[^@]*@([^:/?]+).*#\1#')}"; \
	  test -n "$$host" || { echo "Set DATABASE_URL, or SUPABASE_DB_HOST to the database's host." >&2; exit 1; }; \
	  OPENSSL="$(SUPABASE_OPENSSL)" $(SUPABASE_BIN)/supabase-ca "$$host" "$(SUPABASE_CA_CERT)"; \
	} 2>&1 | tee $(SUPABASE_LOG_DIR)/supabase-refresh-ca.log

supabase-style:
	@case "$(SUPABASE_MIGRATION_STYLE)" in cli|fluent) ;; *) echo "SUPABASE_MIGRATION_STYLE is '$(SUPABASE_MIGRATION_STYLE)'; set it to cli or fluent." >&2; exit 1 ;; esac

supabase-database-url:
	@test -n "$$DATABASE_URL" || { echo "DATABASE_URL, the remote database's connection string, is not set. Export it in .envrc; see .envrc.example." >&2; exit 1; }
