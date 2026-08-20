#!/bin/sh
set -eu

: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${POSTGRES_APP_USER:?POSTGRES_APP_USER is required}"
: "${POSTGRES_APP_PASSWORD:?POSTGRES_APP_PASSWORD is required}"
: "${POSTGRES_CONTROL_USER:?POSTGRES_CONTROL_USER is required}"
: "${POSTGRES_CONTROL_PASSWORD:?POSTGRES_CONTROL_PASSWORD is required}"

migrator_user_lower=$(printf '%s' "$POSTGRES_USER" | tr '[:upper:]' '[:lower:]')
app_user_lower=$(printf '%s' "$POSTGRES_APP_USER" | tr '[:upper:]' '[:lower:]')
control_user_lower=$(printf '%s' "$POSTGRES_CONTROL_USER" | tr '[:upper:]' '[:lower:]')

case "$migrator_user_lower" in
  gestudio_app|gestudio_platform)
    echo 'POSTGRES_USER no puede usar un rol técnico congelado.' >&2
    exit 1
    ;;
esac
case "$app_user_lower" in
  postgres|gestudio_app|gestudio_platform)
    echo 'POSTGRES_APP_USER debe ser un login externo dedicado.' >&2
    exit 1
    ;;
esac
case "$control_user_lower" in
  postgres|gestudio_app|gestudio_platform)
    echo 'POSTGRES_CONTROL_USER debe ser un login externo dedicado.' >&2
    exit 1
    ;;
esac
if [ "$migrator_user_lower" = "$app_user_lower" ] ||
   [ "$migrator_user_lower" = "$control_user_lower" ] ||
   [ "$app_user_lower" = "$control_user_lower" ]; then
  echo 'Los usuarios migrador, tenant runtime y control-plane deben ser distintos.' >&2
  exit 1
fi

psql --set ON_ERROR_STOP=1 \
  --username "$POSTGRES_USER" \
  --dbname "$POSTGRES_DB" \
  --set app_user="$POSTGRES_APP_USER" \
  --set app_password="$POSTGRES_APP_PASSWORD" \
  --set control_user="$POSTGRES_CONTROL_USER" \
  --set control_password="$POSTGRES_CONTROL_PASSWORD" <<'SQL'
SELECT 'CREATE ROLE gestudio_app NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gestudio_app') \gexec

SELECT 'CREATE ROLE gestudio_platform NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS'
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gestudio_platform') \gexec

ALTER ROLE gestudio_app NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
ALTER ROLE gestudio_platform NOLOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;

SELECT format(
    'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS',
    :'app_user', :'app_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'app_user') \gexec

SELECT format(
    'ALTER ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS',
    :'app_user', :'app_password') \gexec

SELECT format('GRANT gestudio_app TO %I', :'app_user') \gexec
SELECT format('REVOKE gestudio_platform FROM %I', :'app_user') \gexec

SELECT format(
    'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS',
    :'control_user', :'control_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'control_user') \gexec

SELECT format(
    'ALTER ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE INHERIT NOREPLICATION NOBYPASSRLS',
    :'control_user', :'control_password') \gexec

SELECT format('GRANT gestudio_platform TO %I', :'control_user') \gexec
SELECT format('REVOKE gestudio_app FROM %I', :'control_user') \gexec
SQL
