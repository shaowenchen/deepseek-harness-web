.PHONY: help up down restart logs build pull ps shell clean

COMPOSE ?= docker compose
IMAGE ?= deepseek-harness-web:local

help:
	@echo "Targets:"
	@echo "  make up       Build (if needed) and start dsh web in the background"
	@echo "  make down     Stop containers (keep data volume)"
	@echo "  make restart  Restart the running service"
	@echo "  make logs     Follow container logs"
	@echo "  make build    Build the local image"
	@echo "  make ps       Show compose service status"
	@echo "  make shell    Open a shell in the running container"
	@echo "  make clean    Stop and remove containers plus the data volume"

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

restart:
	$(COMPOSE) restart

logs:
	$(COMPOSE) logs -f dsh-web

build:
	$(COMPOSE) build

ps:
	$(COMPOSE) ps

shell:
	$(COMPOSE) exec dsh-web sh

clean:
	$(COMPOSE) down -v
