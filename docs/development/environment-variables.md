# Variables de entorno

Los archivos versionados `.env.example` y `.env.local.example` contienen plantillas comentadas. `.env` y variantes locales permanecen ignorados por Git. Sólo Docker Compose los carga automáticamente; Maven, Vite y los scripts leen el entorno del proceso.

## Backend

| Variable | Perfil | Obligatoria | Valor local / comportamiento |
| --- | --- | --- | --- |
| `SPRING_PROFILES_ACTIVE` | todos | prod: sí | `dev` |
| `SPRING_DATASOURCE_URL` | todos | prod: sí | `jdbc:postgresql://localhost:5432/ledance_db` |
| `SPRING_DATASOURCE_USERNAME` | todos | prod: sí | `postgres` |
| `SPRING_DATASOURCE_PASSWORD` | todos | prod: sí, secreta | valor local explícito |
| `SPRING_JPA_HIBERNATE_DDL_AUTO` | todos | no | `validate`; no usar `update` |
| `SPRING_FLYWAY_ENABLED` | todos | no | `true`; test usa `false` por defecto |
| `SPRING_FLYWAY_BASELINE_ON_MIGRATE` | todos | no | `false`; habilitar sólo tras revisar un esquema sin historial |
| `SPRING_FLYWAY_BASELINE_VERSION` | todos | no | `1`; sólo se usa con baseline habilitado |
| `JWT_SECRET` | todos | prod: sí, secreta | mínimo 32 caracteres; local no reutilizable |
| `JWT_ISSUER` | todos | prod: sí | `le-dance-local` |
| `JWT_ACCESS_TOKEN_HOURS` | todos | prod: sí | `2` |
| `JWT_REFRESH_TOKEN_HOURS` | todos | prod: sí | `168` |
| `SPRING_MAIL_HOST` | prod | sí | sin fallback |
| `SPRING_MAIL_PORT` | prod | sí | `587` habitual |
| `SPRING_MAIL_USERNAME` | prod | sí | sin fallback |
| `SPRING_MAIL_PASSWORD` | prod | sí, secreta | sin fallback |
| `SPRING_MAIL_IMAP_HOST` | prod | sí | sin fallback |
| `SPRING_MAIL_IMAP_PORT` | prod | sí | `993` habitual |
| `SPRING_MAIL_IMAP_USERNAME` | prod | sí | sin fallback |
| `SPRING_MAIL_IMAP_PASSWORD` | prod | sí, secreta | sin fallback |
| `SPRING_MAIL_IMAP_SENT_FOLDER` | prod | no | `INBOX.Sent` |
| `APP_TIME_ZONE` | todos | prod: sí | `America/Argentina/Buenos_Aires` |
| `APP_RECEIPTS_PATH` | todos | prod: sí | directorio escribible y persistente |
| `APP_CORS_ALLOWED_ORIGINS` | todos | prod: sí | lista separada por comas; HTTPS en prod |
| `APP_SCHEDULING_ENABLED` | todos | no | `false` en dev/test, `true` en prod |
| `APP_SECURITY_REFRESH_COOKIE_SECURE` | todos | no | `false` en `dev` para HTTP local; `true` por defecto fuera de `dev` |
| `APP_SECURITY_REFRESH_COOKIE_SAME_SITE` | todos | no | `Strict` |
| `APP_SECURITY_REFRESH_COOKIE_PATH` | todos | no | `/api/login` |
| `LEDANCE_HOME` | todos | sí para assets heredados | raíz del repositorio o `/app` en Docker |
| `APP_BOOTSTRAP_SUPERADMIN_ENABLED` | bootstrap único | no | `false`; habilitar sólo para crear el `SUPERADMIN` inicial. |
| `APP_BOOTSTRAP_SUPERADMIN_USERNAME` | bootstrap único | si se habilita | nombre explícito del `SUPERADMIN` inicial. |
| `APP_BOOTSTRAP_SUPERADMIN_PASSWORD` | bootstrap único | si se habilita | secreto externo de 16 a 72 bytes UTF-8. |
| `APP_BOOTSTRAP_ADMIN_ENABLED` | legado / reset local | no | alias deprecado del bootstrap de `SUPERADMIN`; debe ser `false` durante un reset local. |
| `APP_BOOTSTRAP_ADMIN_USERNAME` | reset local | si se habilita | `ADMINISTRADOR` existente que se restablecerá. |
| `APP_BOOTSTRAP_ADMIN_PASSWORD` | reset local | si se habilita | nueva clave local, de 12 a 72 bytes UTF-8. |
| `APP_BOOTSTRAP_ADMIN_RESET_EXISTING_PASSWORD` | sólo `dev` | no | `false`; restablece una vez el BCrypt del `ADMINISTRADOR` indicado e invalida sus sesiones. |
| `SERVER_PORT` | todos | no | `8080` |
| `LOGGING_LEVEL_ROOT` | todos | no | `INFO` |

## Frontend

| Variable | Obligatoria | Comportamiento |
| --- | --- | --- |
| `VITE_API_BASE_URL` | build prod: sí | En dev usa `http://localhost:8080/api`; fuera de localhost exige HTTPS. |
| `VITE_APP_TIME_ZONE` | no | `America/Argentina/Buenos_Aires` |

Vite incorpora estas variables durante el build. Cambiar una variable requiere reconstruir el frontend.

## Docker Compose

| Variable | Obligatoria | Valor local |
| --- | --- | --- |
| `POSTGRES_DB` | prod: sí | `ledance_db` |
| `POSTGRES_USER` | prod: sí | `postgres` |
| `POSTGRES_PASSWORD` | prod: sí, secreta | valor local explícito |
| `POSTGRES_PORT` | no | `5432` |
| `BACKEND_PORT` | no | `8080` |
| `FRONTEND_PORT` | no | `8081` |
| `COMPOSE_PROJECT_NAME` | no | derivado del directorio; definir uno único si hace falta |
| `BACKEND_IMAGE` | prod: sí | `le-dance-backend:local` |
| `FRONTEND_IMAGE` | prod: sí | `le-dance-frontend:local` |

## Variables recomendadas para Codex

La interfaz de Codex debe usar valores de desarrollo, nunca secretos productivos:

| Nombre | Valor |
| --- | --- |
| `JAVA_HOME` | `C:\Program Files\Java\corretto-21.0.7` |
| `SPRING_PROFILES_ACTIVE` | `dev` |
| `SPRING_DATASOURCE_URL` | `jdbc:postgresql://localhost:5432/ledance_db` |
| `SPRING_DATASOURCE_USERNAME` | `postgres` |
| `SPRING_DATASOURCE_PASSWORD` | `local-only-change-me` |
| `SPRING_JPA_HIBERNATE_DDL_AUTO` | `validate` |
| `SPRING_FLYWAY_ENABLED` | `true` |
| `JWT_SECRET` | `local-only-jwt-secret-change-before-sharing` |
| `JWT_ISSUER` | `le-dance-local` |
| `JWT_ACCESS_TOKEN_HOURS` | `2` |
| `JWT_REFRESH_TOKEN_HOURS` | `168` |
| `APP_TIME_ZONE` | `America/Argentina/Buenos_Aires` |
| `APP_RECEIPTS_PATH` | `C:\laburo\le-dance\pdfs` |
| `APP_CORS_ALLOWED_ORIGINS` | `http://localhost:5173,http://localhost:8081` |
| `APP_SCHEDULING_ENABLED` | `false` |
| `LEDANCE_HOME` | `C:\laburo\le-dance` |
| `VITE_API_BASE_URL` | `http://localhost:8080/api` |

Para tests aislados de `FilePathResolver` existe el override de JVM
`-Dledance.home=<ruta>`. La ejecución normal continúa usando `LEDANCE_HOME`; no
se recomienda el override de JVM para producción.
| `VITE_APP_TIME_ZONE` | `America/Argentina/Buenos_Aires` |
| `POSTGRES_DB` | `ledance_db` |
| `POSTGRES_USER` | `postgres` |
| `POSTGRES_PASSWORD` | `local-only-change-me` |
| `POSTGRES_PORT` | `5432` |
| `BACKEND_PORT` | `8080` |
| `FRONTEND_PORT` | `8081` |

No configures SMTP/IMAP en Codex: el perfil `dev` usa email no-op.

## Bootstrap y smoke

El bootstrap inicial canónico usa `APP_BOOTSTRAP_SUPERADMIN_*` y está deshabilitado
por defecto. Al habilitarlo, reclama una ejecución única en
`bootstrap_ejecuciones`, exige el rol activo `SUPERADMIN` y un username que no
exista, y crea una cuenta activa con BCrypt. No modifica usuarios, hashes ni
roles existentes. `APP_BOOTSTRAP_ADMIN_ENABLED` es sólo un alias deprecado para
ese mismo bootstrap; habilitar ambos hace fallar el arranque.

Para recuperar una contraseña local existente, use el perfil `dev`, mantenga
`APP_BOOTSTRAP_ADMIN_ENABLED=false` y habilite temporalmente
`APP_BOOTSTRAP_ADMIN_RESET_EXISTING_PASSWORD=true` con el username y la clave en
`APP_BOOTSTRAP_ADMIN_USERNAME` y `APP_BOOTSTRAP_ADMIN_PASSWORD`. El reset sólo
acepta un `ADMINISTRADOR` activo, no reescribe un BCrypt que ya coincide e
invalida las sesiones anteriores. Deshabilite la bandera y reinicie después de
un arranque exitoso. El bean no existe fuera del perfil `dev`.

`scripts/smoke-local.ps1` genera valores temporales para PostgreSQL, JWT y el
administrador, los escribe únicamente en un archivo de `%TEMP%`, restaura el
entorno del proceso y elimina el archivo al terminar. No agregues esos valores a
`.env.example`, `.env.local.example` ni a otro archivo versionado.
