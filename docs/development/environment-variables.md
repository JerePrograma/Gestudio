# Variables de entorno

Los archivos versionados `.env.example` y `.env.local.example` contienen plantillas comentadas. `.env` y variantes locales permanecen ignorados por Git. Sólo Docker Compose los carga automáticamente; Maven, Vite y los scripts leen el entorno del proceso.

## Backend

| Variable | Perfil | Obligatoria | Valor local / comportamiento |
| --- | --- | --- | --- |
| `SPRING_PROFILES_ACTIVE` | todos | prod: sí | `dev` |
| `SPRING_DATASOURCE_URL` | todos | prod: sí | `jdbc:postgresql://localhost:5432/gestudio_db` |
| `SPRING_DATASOURCE_USERNAME` | todos | prod: sí | `postgres` |
| `SPRING_DATASOURCE_PASSWORD` | todos | prod: sí, secreta | valor local explícito |
| `APP_PLATFORM_DATASOURCE_URL` | todos | prod: sí | misma base que `SPRING_DATASOURCE_URL` |
| `APP_PLATFORM_DATASOURCE_USERNAME` | todos | prod: sí | login dedicado, miembro de `gestudio_platform`; distinto de runtime y migrador |
| `APP_PLATFORM_DATASOURCE_PASSWORD` | todos | prod: sí, secreta | credencial independiente del control-plane |
| `SPRING_JPA_HIBERNATE_DDL_AUTO` | todos | no | `validate`; no usar `update` |
| `SPRING_FLYWAY_ENABLED` | todos | no | `true`; test usa `false` por defecto |
| `SPRING_FLYWAY_BASELINE_ON_MIGRATE` | todos | no | `false`; habilitar sólo tras revisar un esquema sin historial |
| `SPRING_FLYWAY_BASELINE_VERSION` | todos | no | `1`; sólo se usa con baseline habilitado |
| `JWT_SECRET` | todos | prod: sí, secreta | mínimo 32 caracteres; local no reutilizable |
| `JWT_ISSUER` | todos | prod: sí | `gestudio-local` |
| `JWT_ACCESS_TOKEN_TTL` | todos | prod: sí | duración ISO-8601; local `PT15M` |
| `JWT_REFRESH_TOKEN_TTL` | todos | prod: sí | duración ISO-8601; local `P7D` |
| `JWT_PLATFORM_AUDIENCE` | todos | prod: sí | audiencia exclusiva para tokens de plataforma |
| `APP_PLATFORM_ACCESS_TOKEN_TTL` | todos | prod: sí | duración ISO-8601; local `PT5M` |
| `APP_PLATFORM_REFRESH_TOKEN_TTL` | todos | prod: sí | duración ISO-8601; local `PT8H` |
| `APP_PLATFORM_STEP_UP_TTL` | todos | prod: sí | duración ISO-8601; local `PT5M` |
| `APP_PLATFORM_MFA_ENCRYPTION_KEY` | todos | prod: sí, secreta | clave AES-256 independiente, exactamente 32 bytes codificados en Base64 |
| `APP_PLATFORM_MFA_KEY_VERSION` | todos | prod: sí | entero positivo usado para rotación explícita |
| `APP_PLATFORM_REFRESH_COOKIE_*` | todos | prod: sí | cookie separada; `Secure`, `Strict` y path `/api/platform/auth` en entornos públicos |
| `APP_EMAIL_ENABLED` | todos | no | `false`; una de las cinco guardas Gmail |
| `APP_EMAIL_PROVIDER` | todos | no | `NOOP`; admite `FAKE` y `GMAIL_SMTP` explícitos |
| `APP_EMAIL_DRY_RUN` | todos | no | `true`; bloquea SMTP real |
| `APP_EMAIL_REAL_NETWORK_ALLOWED` | todos | no | `false`; política explícita de red |
| `APP_EMAIL_KILL_SWITCH` | todos | no | `true`; corte operativo dominante |
| `APP_EMAIL_FROM_ADDRESS` | Gmail real | sí | sender validado; debe coincidir con el usuario SMTP actual |
| `APP_EMAIL_FROM_NAME` | todos | no | `Gestudio`; máximo 100 caracteres, sin CR/LF |
| `APP_EMAIL_SENT_COPY_MODE` | todos | no | `DISABLED`; `BEST_EFFORT` opcional, `REQUIRED` rechazado |
| `APP_EMAIL_FAKE_OUTCOME` | FAKE | no | `SUCCESS`, `TEMPORARY_FAILURE` o `PERMANENT_FAILURE` |
| `APP_EMAIL_GMAIL_HOST` | Gmail real | sí | sin fallback real; no se versiona un destino |
| `APP_EMAIL_GMAIL_PORT` | Gmail real | sí | `587` por defecto |
| `APP_EMAIL_GMAIL_USERNAME` | Gmail real | sí | cuenta sender válida |
| `APP_EMAIL_GMAIL_APP_PASSWORD` | Gmail real transitorio | sí, secreta | sólo secret manager; nunca `.env` versionado |
| `APP_EMAIL_SMTP_CONNECTION_TIMEOUT_MS` | Gmail real | no | `5000`; debe ser positivo |
| `APP_EMAIL_SMTP_READ_TIMEOUT_MS` | Gmail real | no | `5000`; debe ser positivo |
| `APP_EMAIL_SMTP_WRITE_TIMEOUT_MS` | Gmail real | no | `5000`; debe ser positivo |
| `APP_EMAIL_SENT_COPY_HOST` | Sent `BEST_EFFORT` | sí | host IMAPS externo |
| `APP_EMAIL_SENT_COPY_PORT` | Sent `BEST_EFFORT` | sí | `993` por defecto |
| `APP_EMAIL_SENT_COPY_USERNAME` | Sent `BEST_EFFORT` | sí | dirección válida |
| `APP_EMAIL_SENT_COPY_APP_PASSWORD` | Sent `BEST_EFFORT` | sí, secreta | sólo secret manager |
| `APP_EMAIL_SENT_COPY_FOLDER` | Sent `BEST_EFFORT` | sí | nombre exacto verificado con la cuenta |
| `APP_EMAIL_SENT_COPY_CONNECTION_TIMEOUT_MS` | Sent `BEST_EFFORT` | no | `5000`; debe ser positivo |
| `APP_EMAIL_SENT_COPY_READ_TIMEOUT_MS` | Sent `BEST_EFFORT` | no | `5000`; debe ser positivo |
| `APP_TIME_ZONE` | todos | prod: sí | `America/Argentina/Buenos_Aires` |
| `APP_RECEIPTS_PATH` | todos | prod: sí | directorio escribible y persistente |
| `APP_CORS_ALLOWED_ORIGINS` | todos | prod: sí | lista separada por comas; HTTPS en prod |
| `APP_SCHEDULING_ENABLED` | todos | no | `false` en dev/test, `true` en prod |
| `APP_SECURITY_REFRESH_COOKIE_SECURE` | todos | no | `false` en `dev` para HTTP local; `docker-compose.prod.yml` fuerza `true` |
| `APP_SECURITY_REFRESH_COOKIE_SAME_SITE` | todos | no | `Strict` |
| `APP_SECURITY_REFRESH_COOKIE_PATH` | todos | no | `/api/login` |
| `GESTUDIO_HOME` | todos | sí para assets heredados | raíz del repositorio o `/app` en Docker |
| `APP_BOOTSTRAP_SUPERADMIN_ENABLED` | bootstrap único | no | `false`; habilitar sólo para crear el `SUPERADMIN` inicial. |
| `APP_BOOTSTRAP_SUPERADMIN_USERNAME` | bootstrap único | si se habilita | nombre explícito del `SUPERADMIN` inicial. |
| `APP_BOOTSTRAP_SUPERADMIN_PASSWORD` | bootstrap único | si se habilita | secreto externo de 16 a 72 bytes UTF-8. |
| `APP_BOOTSTRAP_PLATFORM_TOTP_SECRET` | bootstrap único | si se habilita, secreta | secreto Base32 externo para provisionar MFA; sólo existe en el job one-shot. |
| `APP_BOOTSTRAP_PLATFORM_TOTP_CODE` | bootstrap único | si se habilita, secreta | código TOTP vigente que verifica la credencial inicial; sólo existe en el job one-shot. |
| `APP_BOOTSTRAP_PLATFORM_RECOVERY_CODES_FILE` | bootstrap único | si se habilita | ruta interna del job donde se escriben exactamente diez códigos antes del commit; el script operativo los copia a un destino nuevo con ACL restringida. |
| `APP_LOCAL_ADMIN_PASSWORD_RESET_ENABLED` | sólo `dev` | no | `false`; restablece una vez el BCrypt de un `ADMINISTRADOR` existente. |
| `APP_LOCAL_ADMIN_PASSWORD_RESET_USERNAME` | reset local habilitado | sí | `ADMINISTRADOR` activo que se restablecerá. |
| `APP_LOCAL_ADMIN_PASSWORD_RESET_PASSWORD` | reset local habilitado | sí, secreta | nueva clave local, de 12 a 72 bytes UTF-8. |
| `SERVER_PORT` | todos | no | `8080` |
| `LOGGING_LEVEL_ROOT` | todos | no | `INFO` |
| `APP_JERE_PLATFORM_STUDENT_EXPORT_ENABLED` | integración | no | `false`; habilita el emisor sólo con mapping y secreto válidos. |
| `APP_JERE_PLATFORM_STUDENT_EXPORT_ORGANIZATION_ID` | integración habilitada | sí | identificador interno estable y sanitizado del deployment/academia. |
| `APP_JERE_PLATFORM_STUDENT_EXPORT_TENANT_ID` | integración habilitada | sí | UUID externo explícito de Jere Platform; nunca se deriva por nombre. |
| `APP_JERE_PLATFORM_STUDENT_EXPORT_CURRENT_SECRET` | integración habilitada | sí, secreta | secreto independiente de al menos 32 bytes UTF-8, suministrado por el secret manager. |
| `APP_JERE_PLATFORM_STUDENT_EXPORT_PAGE_SIZE` | integración | no | `1000`; rango válido 1..1000. |

## Frontend

| Variable | Obligatoria | Comportamiento |
| --- | --- | --- |
| `VITE_API_BASE_URL` | build prod: sí | En dev usa `http://localhost:8080/api`; fuera de localhost exige HTTPS. |
| `VITE_APP_TIME_ZONE` | no | `America/Argentina/Buenos_Aires` |

Vite incorpora estas variables durante el build. Cambiar una variable requiere reconstruir el frontend.

## Docker Compose

| Variable | Obligatoria | Valor local |
| --- | --- | --- |
| `POSTGRES_DB` | prod: sí | `gestudio_db` |
| `POSTGRES_USER` | prod: sí | `postgres` |
| `POSTGRES_PASSWORD` | prod: sí, secreta | valor local explícito |
| `POSTGRES_APP_USER` | prod: sí | `gestudio_app_local`; login tenant runtime |
| `POSTGRES_APP_PASSWORD` | prod: sí, secreta | credencial independiente del runtime tenant |
| `POSTGRES_CONTROL_USER` | prod: sí | `gestudio_control_local`; login externo miembro de `gestudio_platform` |
| `POSTGRES_CONTROL_PASSWORD` | prod: sí, secreta | credencial independiente del control-plane |
| `POSTGRES_PORT` | no | `5432` |
| `BACKEND_PORT` | no | `8080` |
| `FRONTEND_PORT` | no | `8081` |
| `COMPOSE_PROJECT_NAME` | no | derivado del directorio; definir uno único si hace falta |
| `BACKEND_IMAGE` | prod: sí | `gestudio-backend:local` |
| `FRONTEND_IMAGE` | prod: sí | `gestudio-frontend:local` |

## Variables recomendadas para Codex

La interfaz de Codex debe usar valores de desarrollo, nunca secretos productivos:

| Nombre | Valor |
| --- | --- |
| `JAVA_HOME` | ruta local al JDK 21; no se versiona ni se presupone una distribución |
| `SPRING_PROFILES_ACTIVE` | `dev` |
| `SPRING_DATASOURCE_URL` | `jdbc:postgresql://localhost:5432/gestudio_db` |
| `SPRING_DATASOURCE_USERNAME` | `postgres` |
| `SPRING_DATASOURCE_PASSWORD` | `local-only-change-me` |
| `SPRING_JPA_HIBERNATE_DDL_AUTO` | `validate` |
| `SPRING_FLYWAY_ENABLED` | `true` |
| `JWT_SECRET` | `local-only-jwt-secret-change-before-sharing` |
| `JWT_ISSUER` | `gestudio-local` |
| `JWT_ACCESS_TOKEN_TTL` | `PT15M` |
| `JWT_REFRESH_TOKEN_TTL` | `P7D` |
| `APP_TIME_ZONE` | `America/Argentina/Buenos_Aires` |
| `APP_RECEIPTS_PATH` | subdirectorio local no versionado bajo la raíz del repositorio |
| `APP_CORS_ALLOWED_ORIGINS` | `http://localhost:5173,http://localhost:8081` |
| `APP_SCHEDULING_ENABLED` | `false` |
| `APP_EMAIL_ENABLED` | `false` |
| `APP_EMAIL_PROVIDER` | `NOOP` |
| `APP_EMAIL_DRY_RUN` | `true` |
| `APP_EMAIL_REAL_NETWORK_ALLOWED` | `false` |
| `APP_EMAIL_KILL_SWITCH` | `true` |
| `APP_EMAIL_SENT_COPY_MODE` | `DISABLED` |
| `GESTUDIO_HOME` | raíz del checkout actual |
| `VITE_API_BASE_URL` | `http://localhost:8080/api` |

Para tests aislados de `FilePathResolver` existe el override de JVM
`-Dgestudio.home=<ruta>`. La ejecución normal continúa usando `GESTUDIO_HOME`; no
se recomienda el override de JVM para producción.
| `VITE_APP_TIME_ZONE` | `America/Argentina/Buenos_Aires` |
| `POSTGRES_DB` | `gestudio_db` |
| `POSTGRES_USER` | `postgres` |
| `POSTGRES_PASSWORD` | `local-only-change-me` |
| `POSTGRES_PORT` | `5432` |
| `BACKEND_PORT` | `8080` |
| `FRONTEND_PORT` | `8081` |

No configures SMTP/IMAP en Codex. El proveedor, no el perfil, selecciona el
adaptador; estos valores mantienen NOOP incluso si se ejecuta `prod`. La guía
completa está en `docs/integrations/gmail-email-delivery.md`.

El secreto de exportación no aparece en `.env.example` ni en esta tabla como
valor de ejemplo. No debe reutilizar JWT, credenciales de base ni otros secretos.
La rotación y el procedimiento local están documentados en
`docs/integrations/jere-platform-student-export-v1.md`.

## Bootstrap y smoke

El bootstrap inicial canónico usa `APP_BOOTSTRAP_SUPERADMIN_*` únicamente en un
contenedor externo one-shot y está deshabilitado de forma fija en el servicio
ordinario. Tras un deploy healthy se ejecuta
`scripts/ops/bootstrap-platform-admin.ps1` con el env efectivo, proyecto,
username, un `RecoveryCodesPath` nuevo y `-ConfirmBootstrap`; el script solicita
password, secreto Base32 y código TOTP como `SecureString`, rechaza
`gestudio-remote-demo`, copia los diez recovery codes a ese archivo sin
imprimirlos, restringe su ACL al usuario Windows actual, elimina el job temporal
y verifica identidad activa, MFA inicial y ausencia de memberships antes de
terminar. Al habilitarlo en ese job, reclama una ejecución única en
`bootstrap_ejecuciones`, exige que todavía no exista ningún administrador de
plataforma y que el username sea nuevo, y crea una identidad global activa con
BCrypt y una fila activa en `platform_admins`. La política de complejidad usa el
nivel privilegiado `SUPERADMIN`, pero no crea un rol tenant: `usuarios.rol_id`
queda `NULL` y no se agrega membership. No modifica usuarios, hashes, roles ni
memberships existentes. No existen aliases legacy para este bootstrap.

Para recuperar una contraseña local existente, use el perfil `dev`, mantenga
`APP_BOOTSTRAP_SUPERADMIN_ENABLED=false` y habilite temporalmente
`APP_LOCAL_ADMIN_PASSWORD_RESET_ENABLED=true` con el username y la clave en
`APP_LOCAL_ADMIN_PASSWORD_RESET_USERNAME` y
`APP_LOCAL_ADMIN_PASSWORD_RESET_PASSWORD`. El reset sólo
acepta un `ADMINISTRADOR` activo, no reescribe un BCrypt que ya coincide e
invalida las sesiones anteriores. Deshabilite la bandera y reinicie después de
un arranque exitoso. El bean no existe fuera del perfil `dev`.

`scripts/smoke-local.ps1` genera valores temporales para PostgreSQL, JWT y el
administrador, los escribe únicamente en un archivo de `%TEMP%`, restaura el
entorno del proceso y elimina el archivo al terminar. No agregues esos valores a
`.env.example`, `.env.local.example` ni a otro archivo versionado.
