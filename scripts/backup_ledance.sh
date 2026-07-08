#!/bin/bash

# Configuración
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_DIR="/opt/gestudio/basebackup"
BACKUP_FILE="${BACKUP_DIR}/gestudio_db_${TIMESTAMP}.backup"
DB_NAME="gestudio_db"
DB_USER="postgres"
DB_HOST="localhost"
DB_PORT="5432"

# Crear directorio si no existe
mkdir -p "$BACKUP_DIR"

# Ejecutar el backup
pg_dump -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -F c -f "$BACKUP_FILE"

# Permisos seguros
chown postgres:postgres "$BACKUP_FILE"
chmod 600 "$BACKUP_FILE"

# Mantener sólo los 7 backups más recientes
cd "$BACKUP_DIR"
ls -1t gestudio_db_*.backup | tail -n +8 | xargs -r rm --

