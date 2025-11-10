.PHONY: up down pull logs index immich photoprism all caddy cloudflare follow force

STACK ?= all
STACK_TARGETS := immich photoprism all caddy cloudflare

FIRST_GOAL := $(firstword $(MAKECMDGOALS))

ifneq ($(filter $(STACK_TARGETS),$(FIRST_GOAL)),)
override STACK := $(FIRST_GOAL)
override MAKECMDGOALS := $(filter-out $(FIRST_GOAL),$(MAKECMDGOALS))
endif

ENV_FILE ?= .env
COMPOSE_DIR := compose

COMPOSE_FILES_immich := $(COMPOSE_DIR)/immich.yml
COMPOSE_FILES_photoprism := $(COMPOSE_DIR)/photoprism.yml
COMPOSE_FILES_caddy := $(COMPOSE_DIR)/caddy.yml
COMPOSE_FILES_cloudflare := $(COMPOSE_DIR)/cloudflare.yml
COMPOSE_FILES_all := $(COMPOSE_FILES_immich) $(COMPOSE_FILES_photoprism) $(COMPOSE_FILES_caddy) $(COMPOSE_FILES_cloudflare)

COMPOSE_FILES = $(COMPOSE_FILES_$(STACK))

DOCKER_COMPOSE = docker compose --env-file $(ENV_FILE)

TAIL ?= 100
FOLLOW ?= --follow

define compose_with
$(DOCKER_COMPOSE) $(foreach file,$(1),-f $(file))
endef

up:
	@echo "Starting $(STACK) stack..."
	@$(call compose_with,$(COMPOSE_FILES)) up -d

down:
	@echo "Stopping $(STACK) stack..."
	@$(call compose_with,$(COMPOSE_FILES)) down

pull:
	@echo "Pulling images for $(STACK) stack..."
	@$(call compose_with,$(COMPOSE_FILES)) pull

logs:
	@echo "Tailing logs for $(STACK) stack..."
	@$(call compose_with,$(COMPOSE_FILES)) logs --tail=$(TAIL) $(FOLLOW)

index:
	@if [ "$(STACK)" != "photoprism" ]; then \
		echo "Error: index target is only supported for the photoprism stack."; \
		exit 1; \
	fi
	@extra="$(filter force,$(MAKECMDGOALS))"; \
	cmd="photoprism index --cleanup"; \
	if [ -n "$$extra" ]; then \
		cmd="$$cmd --force"; \
	fi; \
	echo "Running PhotoPrism indexing command: $$cmd"; \
	$(call compose_with,$(COMPOSE_FILES)) exec photoprism $$cmd

immich photoprism all caddy cloudflare:
	@true

follow:
	@true

force:
	@true
