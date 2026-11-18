# infra-lab

Stack local completo y observable para las aplicaciones del portfolio: **API + PostgreSQL + Redis + Caddy + Prometheus + Grafana**, con un solo `make up`.

[![Infra](https://github.com/HazSy/infra-lab/actions/workflows/infra.yml/badge.svg)](https://github.com/HazSy/infra-lab/actions/workflows/infra.yml)
![Docker](https://img.shields.io/badge/Docker%20Compose-v2-2496ED?logo=docker&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-17-4169E1?logo=postgresql&logoColor=white)
![Prometheus](https://img.shields.io/badge/Prometheus-3-E6522C?logo=prometheus&logoColor=white)
![Grafana](https://img.shields.io/badge/Grafana-11-F46800?logo=grafana&logoColor=white)
![License](https://img.shields.io/badge/license-MIT-blue)

---

## Qué demuestra

Un `docker-compose.yml` de tutorial levanta dos contenedores y ya. Este repositorio resuelve lo que aparece cuando el stack crece:

| Problema | Solución aplicada |
| :--- | :--- |
| Todo habla con todo | **Dos redes**: `edge` (proxy, API, Grafana) y `data` (`internal: true`, sin salida a Internet) |
| La API arranca antes que la base de datos | `depends_on` con `condition: service_healthy` y `pg_isready` |
| «¿Está vivo?» no es «¿puede atender?» | Healthcheck contra `/actuator/health/readiness`, no solo el puerto abierto |
| Secretos en el repositorio | `.env` obligatorio: compose **falla** si falta `POSTGRES_PASSWORD`, `JWT_SECRET` o `GRAFANA_PASSWORD` |
| Nadie sabe qué pasa en producción | Prometheus scrapea métricas de la JVM y 4 alertas listas (`prometheus/alerts.yml`) |
| Copias de seguridad «cuando me acuerde» | `make backup` con `pg_dump`, verificación de que el gzip no está vacío y retención de 7 días |
| Configuración sin validar | CI ejecuta `docker compose config`, `promtool check config`, `promtool check rules`, `jq` y `shellcheck` |

## Arranque

Requisitos: Docker con Compose v2 y, para `make`, el binario `make` (en Windows: `choco install make` o usa los comandos de abajo).

```bash
git clone https://github.com/HazSy/infra-lab && cd infra-lab
git clone https://github.com/HazSy/billing-api ../billing-api   # repositorio hermano
cp .env.example .env      # cambia las tres contraseñas
make up
```

| Servicio | URL | Notas |
| :--- | :--- | :--- |
| API + Swagger | http://localhost:8080/api/docs | Vía Caddy |
| Grafana | http://localhost:8080/grafana/ | Panel «Billing API» ya provisionado |
| Prometheus | interno (`data`) | Solo accesible desde la red privada |
| PostgreSQL | interno | Sin puerto publicado a propósito |
| Health | http://localhost:8080/api/actuator/health | `readiness` y `liveness` |

Comandos:

```bash
make help            # lista de objetivos
make logs S=api      # logs de un servicio
make psql            # consola de PostgreSQL
make backup          # copia comprimida en backups/
make restore F=backups/billing-20260101-030000.sql.gz
make clean           # borra también los volúmenes (pide confirmación)
```

Sin `make`:

```bash
docker compose --env-file .env up -d --build
docker compose --env-file .env ps
docker compose --env-file .env logs -f --tail=100 api
```

## Arquitectura

```text
                    :8080
                      │
                 ┌────▼────┐
                 │  Caddy  │  TLS automático en producción, gzip/zstd, cabeceras
                 └──┬───┬──┘
          /api/*    │   │    /grafana/*
              ┌─────▼┐ ┌▼────────┐
              │ API  │ │ Grafana │      red: edge
              └──┬───┘ └────┬────┘
                 │          │ scrape
        ┌────────┼──────────▼───────┐
        │        │   Prometheus     │  red: data (internal)
   ┌────▼───┐ ┌──▼───┐              │
   │ Postgres│ │ Redis│              │
   └─────────┘ └──────┘              │
```

- **Caddy** termina TLS y unifica el acceso; la API nunca se publica directamente.
- La **red `data` es `internal`**: si alguien compromete el proxy, no llega a la base de datos.
- **Grafana** está en `edge` para servirse por el proxy, pero consulta Prometheus por `data`.
- Los **volúmenes son nombrados**: `docker compose down` conserva los datos; solo `clean` los borra.

## Observabilidad

Métricas expuestas por Spring Boot Actuator + Micrometer (`/actuator/prometheus`) y recolectadas cada 15 s.

Alertas incluidas:

| Alerta | Condición | Severidad |
| :--- | :--- | :--- |
| `ApiCaida` | `up == 0` durante 2 min | critical |
| `TasaDeErrores5xx` | > 5 % de respuestas 5xx durante 5 min | warning |
| `LatenciaAltaP95` | p95 > 800 ms durante 10 min | warning |

El dashboard «Billing API» se aprovisiona solo (`grafana/dashboards/billing-api.json`): estado del scrape, peticiones/s, errores 5xx, memoria JVM, latencia p95 por endpoint y peticiones por código HTTP.

## Copias de seguridad

`scripts/backup.sh`:

1. Comprueba que `db` está en marcha (falla claro si no).
2. `pg_dump --no-owner --clean --if-exists` comprimido con gzip.
3. Verifica el gzip (`gzip -t`) y que el archivo no esté vacío.
4. Aplica retención por días.

Para programarlo en el servidor:

```cron
0 3 * * * cd /srv/infra-lab && bash scripts/backup.sh 14 >> backups/cron.log 2>&1
```

## Decisiones

1. **Sin puertos para la base de datos.** `5432` no se publica: si necesitas acceso, `make psql` abre una sesión dentro del contenedor.
2. **Dos redes y no una.** La separación `edge`/`data` con `internal: true` es la diferencia entre un stack doméstico y uno defendible.
3. **Healthchecks que prueban la dependencia real** (`pg_isready`, `redis-cli ping`, `actuator/health/readiness`), no un `sleep 10`.
4. **Secretos obligatorios**, sin valores por defecto peligrosos: `${VAR:?mensaje}` aborta el arranque con un mensaje útil.
5. **Todo validado en CI** antes de tocar un servidor: sintaxis de compose, reglas de Prometheus, JSON del dashboard y scripts con `shellcheck`.
6. **La API se construye desde su repositorio** (`../billing-api`), no se publica una imagen opaca: el `Dockerfile` multi-stage vive con el código.

## Producción

Para un servidor real falta: TLS con dominio (Caddy lo resuelve solo si expones 80/443 y un DNS), backups fuera de la máquina, límites de recursos (`deploy.resources`) y `restart: unless-stopped` ya está puesto.

## Hoja de ruta

- [ ] Loki + Promtail para centralizar logs y un panel de errores.
- [ ] `docker compose --profile monitoring` para no cargar Prometheus en local.
- [ ] Testcontainers en la API usando este mismo PostgreSQL.
- [ ] Manifiestos de Kubernetes equivalentes (Deployment, Service, HPA).
- [ ] Terraform para provisionar el VPS y el DNS.

## Licencia

MIT © Óscar López Pellicer
