#!/usr/bin/env bash
#
# Copia de seguridad de PostgreSQL comprimida y con retención.
# Uso: bash scripts/backup.sh [días_de_retención]
#
set -euo pipefail

RETENTION_DAYS="${1:-7}"
DIR="backups"
STAMP="$(date +%Y%m%d-%H%M%S)"
FILE="${DIR}/billing-${STAMP}.sql.gz"

mkdir -p "$DIR"

if ! docker compose ps --status running --services | grep -qx db; then
  echo "El servicio 'db' no está en marcha. Ejecuta 'make up' primero." >&2
  exit 1
fi

echo "Volcando base de datos en ${FILE}…"
docker compose exec -T db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --no-owner --clean --if-exists' \
  | gzip -9 > "$FILE"

# Comprobar que el archivo no está vacío y que el gzip es válido.
gzip -t "$FILE"
if [ "$(wc -c < "$FILE")" -lt 100 ]; then
  echo "La copia parece vacía. Abortando." >&2
  rm -f "$FILE"
  exit 1
fi

echo "Copia completada: $(du -h "$FILE" | cut -f1)"
echo "Limpiando copias de más de ${RETENTION_DAYS} días…"
find "$DIR" -name 'billing-*.sql.gz' -type f -mtime "+${RETENTION_DAYS}" -print -delete
