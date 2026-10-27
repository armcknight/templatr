# The project's Makefile. Each component's targets are in its directory's
# component.mk, such as server/component.mk or apple/component.mk, which this
# file includes. Their Makefile fragments come from armcknight/templatr at
# TEMPLATES_TAG: each is downloaded on first use, and `make templates-update`
# downloads them again, as after changing the tag.
#
# Commands are namespaced: `make server deploy` runs the server-deploy target,
# and `make apple ios test` runs apple-ios-test. The direct form, `make
# server-deploy`, works too. `make help` lists them.

TEMPLATES_TAG = {{templates.tag}}
TEMPLATES_MAKE = .templatr/make

# Each component.mk adds its namespace, such as server, and the fragments it
# includes.
NAMESPACES :=
TEMPLATES_FRAGMENTS :=

.DEFAULT_GOAL = help
.PHONY: help templates-update

include $(sort $(wildcard */component.mk))

# `make <namespace> <command>` runs `<namespace>-<command>`, and the words after
# the namespace do nothing by themselves. A command can be more than one word,
# joined with dashes: `make apple ios test` runs `apple-ios-test`. A namespace
# with no command lists the targets.
ifneq ($(filter $(firstword $(MAKECMDGOALS)),$(NAMESPACES)),)
NS  := $(firstword $(MAKECMDGOALS))
EMPTY :=
SPACE := $(EMPTY) $(EMPTY)
CMD := $(subst $(SPACE),-,$(strip $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))))
.PHONY: $(NS)
$(NS):
	@$(MAKE) --no-print-directory $(if $(strip $(CMD)),$(NS)-$(CMD),help)
%:
	@:
endif

$(TEMPLATES_MAKE)/%.mk:
	mkdir -p $(@D)
	curl -fsSL https://raw.githubusercontent.com/armcknight/templatr/$(TEMPLATES_TAG)/make/$*.mk -o $@

## help: list these targets
help:
	@awk '/^## /{ t = substr($$0, 4); c = index(t, ":"); printf "  make %-28s %s\n", substr(t, 1, c - 1), substr(t, c + 2) }' $(filter-out $(TEMPLATES_MAKE)/%,$(MAKEFILE_LIST))

## templates-update: download the Makefile fragments again at TEMPLATES_TAG
templates-update:
	rm -rf $(TEMPLATES_MAKE)
	$(if $(strip $(TEMPLATES_FRAGMENTS)),$(MAKE) $(TEMPLATES_FRAGMENTS))
