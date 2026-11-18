SHELL := /bin/bash
COMPOSE := docker compose --env-file .env
HTTP_PORT ?= 8080

.PHONY: help up down restart logs ps psql config backup restore clean

help: ## Muestra esta ayuda
	@grep -hE '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

.env:
	@cp .env.example .env
	@echo ""
	@echo "He creado .env a partir de .env.example."
	@echo "Cambia POSTGRES_PASSWORD, JWT_SECRET y GRAFANA_PASSWORD y vuelve a lanzar 'make up'."
	@exit 1

up: .env ## Levanta todo el stack en segundo plano
	$(COMPOSE) up -d --build
	@echo ""
	@echo "  API        http://localhost:$(HTTP_PORT)/api/docs"
	@echo "  Grafana    http://localhost:$(HTTP_PORT)/grafana/"
	@echo "  Health     http://localhost:$(HTTP_PORT)/api/actuator/health"
	@echo ""
	$(COMPOSE) ps

down: .env ## Para los contenedores (conserva los datos)
	$(COMPOSE) down

restart: .env ## Reinicia un servicio: make restart S=api
	$(COMPOSE) restart $(S)

logs: .env ## Sigue los logs: make logs o make logs S=api
	$(COMPOSE) logs -f --tail=100 $(S)

ps: .env ## Estado y salud de los servicios
	$(COMPOSE) ps

psql: .env ## Consola de PostgreSQL
	$(COMPOSE) exec db psql -U "$${POSTGRES_USER:-billing}" -d "$${POSTGRES_DB:-billing}"

config: ## Valida y muestra la configuración resuelta
	$(COMPOSE) config --quiet && echo "compose.yaml válido"

backup: .env ## Copia de seguridad comprimida en backups/
	@bash scripts/backup.sh

restore: .env ## Restaura una copia: make restore F=backups/billing-XXXX.sql.gz
	@test -n "$(F)" || { echo "Uso: make restore F=backups/billing-20260101-030000.sql.gz"; exit 1; }
	@gunzip -c "$(F)" | $(COMPOSE) exec -T db psql -U "$${POSTGRES_USER:-billing}" -d "$${POSTGRES_DB:-billing}"
	@echo "Restaurado $(F)"

clean: ## Borra contenedores, redes y volúmenes (pide confirmación)
	@read -p "Esto elimina la base de datos y los paneles. ¿Seguro? [s/N] " ok; \
	if [ "$$ok" = "s" ]; then $(COMPOSE) down -v --remove-orphans; else echo "Cancelado."; fi
