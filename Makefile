.PHONY: up down logs immich photoprism both

STACK ?= both
STACK_TARGETS := immich photoprism both

FIRST_GOAL := $(firstword $(MAKECMDGOALS))

ifneq ($(filter $(STACK_TARGETS),$(FIRST_GOAL)),)
override STACK := $(FIRST_GOAL)
override MAKECMDGOALS := $(filter-out $(FIRST_GOAL),$(MAKECMDGOALS))
endif

ENV_FILE ?= .env
COMPOSE_DIR := compose

COMPOSE_FILES_immich := $(COMPOSE_DIR)/immich.yml
COMPOSE_FILES_photoprism := $(COMPOSE_DIR)/photoprism.yml
COMPOSE_FILES_both := $(COMPOSE_FILES_immich) $(COMPOSE_FILES_photoprism)

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

logs:
	@echo "Tailing logs for $(STACK) stack..."
	@$(call compose_with,$(COMPOSE_FILES)) logs --tail=$(TAIL) $(FOLLOW)

immich photoprism both:
	@true
