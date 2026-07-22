# Fase 2 - Seguridad crítica (snapshot histórico)

> Este documento precede V5. El contrato vigente usa `roles[]`, `permisos[]`,
> authorities efectivas y refresh por cookie HttpOnly; consulte
> `docs/development/local-development.md#contrato-rbac`.

> Evidencia anterior a la política catch-all administrativa. El inventario
> vigente es `07-security-endpoints.md`.

Fecha de cierre local: 2026-06-28.

Estado: gate de Fase 2 completo. No se ejecutó commit, push, deploy, bootstrap real ni conexión a una base de datos.

## Diagnóstico confirmado

- `POST /api/usuarios/registro` era público y aceptaba el rol enviado por el cliente.
- `/api/roles` era público para lectura y escritura.
- `GET /api/pagos/recibo/{id}` era público y enumerable.
- `POST /api/login/refresh` no estaba permitido explícitamente por la cadena de seguridad.
- El mismo JWT se verificaba por separado para subject, tipo y rol.
- El filtro podía autenticar usuarios inactivos, sin rol o con rol inactivo.
- Access y refresh se diferenciaban por un string extraído después de verificaciones repetidas.
- El refresh devolvía mensajes internos y respondía 403 para un usuario inactivo.
- Los errores 500 devolvían el mensaje interno de la excepción.
- La baja de usuario eliminaba físicamente la fila y anulaba referencias históricas de pagos.
- El frontend todavía exponía una ruta y un enlace de autorregistro.

## Cambios aplicados

### Autenticación y JWT

- `TokenService` construye un verificador único y cada solicitud produce un solo `VerifiedToken` tipado.
- Los tokens incluyen issuer, subject, user ID, rol, tipo cerrado, `iat`, `exp` y `jti`.
- Firma, issuer, expiración, formato, claims faltantes o tipo incorrecto producen 401 genérico.
- Access y refresh no son intercambiables.
- El filtro carga el usuario por ID y exige subject, rol, estado del usuario y estado del rol coherentes.
- Login/refresh omiten side effects de recargos y notificaciones, preservando la modificación local previa de `AutenticacionControlador`; también se eliminaron sus dependencias constructoras ya inactivas.
- Refresh usa `Authorization: Bearer`, emite un par nuevo y nunca expone el motivo interno del rechazo.
- Se agregó un `Clock` de aplicación como frontera explícita de tiempo.

### Autorización

- Públicos: login, refresh y OPTIONS.
- Perfil propio: cualquier usuario autenticado.
- Usuarios y roles: sólo `ROLE_ADMINISTRADOR`.
- Recibos y facturas: sólo `ROLE_ADMINISTRADOR`.
- Resto del monolito: usuario autenticado.
- 401 y 403 se resuelven explícitamente en la cadena; se deshabilitaron form login y HTTP Basic.
- La política completa está en `07-security-endpoints.md`.

### Bootstrap de administrador

- El runner legacy de administrador estaba deshabilitado por defecto; el contrato
  actual lo reemplaza por el bootstrap de SUPERADMIN de un solo uso.
- Exige username externo y contraseña externa de 12 a 72 bytes UTF-8.
- Sólo crea si no existe ningún usuario y el rol `ADMINISTRADOR` está activo.
- Codifica la clave con BCrypt y no la registra.
- Si se reinicia todavía habilitado después de crear el usuario, falla cerrado y exige deshabilitarlo.
- Compose y documentación exponen las variables sin contraseña por defecto.

### Frontend

- Se eliminó `/registro` de rutas públicas, del guard de auth y de la pantalla de login.
- Axios ya enviaba refresh como Bearer y su contrato queda alineado con backend.
- 403 conserva la sesión y 401 usa una única promesa de refresh compartida.

### Historial de usuarios

- `DELETE /api/usuarios/{id}` ahora desactiva al usuario.
- Ya no elimina la fila ni pone a null referencias de pagos/detalles.
- La respuesta cambió de “eliminado” a “desactivado”.

### Errores

- Login inválido devuelve 401 con detalle genérico.
- Falta de permiso devuelve 403.
- Los 500 siguen registrando la excepción del lado servidor, pero la respuesta sólo contiene `Ocurrió un error inesperado`.

## Archivos principales

- Seguridad: `SecurityConfigurations`, `SecurityFilter`, `TokenService`, `VerifiedToken`, `TokenType`, `InvalidTokenException`, `AutenticacionService`.
- Bootstrap actual: `SuperadminBootstrapRunner`,
  `LocalAdminPasswordResetProperties`, `LocalAdminPasswordResetRunner`,
  `application.yml` y `docker-compose.yml`. Las clases legacy de bootstrap
  administrativo fueron retiradas.
- API/servicios: `AutenticacionControlador`, `UsuarioControlador`, `UsuarioServicio`, `TratadorDeErrores`.
- Frontend: `routes.ts`, `Login.tsx`, `authContext.tsx` y test de login.
- Documentación: inventario de endpoints, variables y flujo local.

## Invariantes afectadas

- Un JWT sólo autoriza si token, usuario y rol siguen siendo válidos y coherentes.
- Un refresh nunca puede actuar como access y viceversa.
- La administración de identidades y roles no es pública.
- Un documento financiero no es accesible por enumeración anónima.
- Una baja de usuario preserva identidad y referencias históricas.
- Ninguna contraseña administrativa fija existe en código, migraciones o Compose.

## Migraciones

Ninguna. V1-V060 permanecen sin cambios.

## Pruebas agregadas

- `SecurityHttpIntegrationTest`: 11 pruebas MockMvc con la cadena real.
- `TokenServiceTest`: 5 pruebas, incluida concurrencia de verificación y `jti` único.
- `SuperadminBootstrapRunnerTest`: 3 pruebas.
- `UsuarioServicioTest`: 1 prueba de baja lógica.

Cobertura explícita del gate:

- login válido e inválido;
- access válido, vencido, firma inválida e issuer inválido;
- refresh usado como access y access usado como refresh;
- refresh válido y vencido;
- usuario inactivo y usuario sin rol;
- endpoint administrativo con 401/403/200;
- recibo financiero para usuario no administrador;
- CORS preflight;
- respuesta 500 sin detalle interno;
- verificación concurrente de JWT.

## Comandos y resultados finales

| Comando | Resultado |
| --- | --- |
| `backend\.\mvnw.cmd -B -ntp clean verify` | PASS; 44 tests, 0 fallos, 0 errores, 0 omitidos; JAR generado. |
| suite dirigida `TokenServiceTest,SecurityHttpIntegrationTest,SuperadminBootstrapRunnerTest,UsuarioServicioTest` | PASS; 20 tests en ese corte. |
| `frontend\npm run lint` | PASS; 0 errores, 0 warnings. |
| `frontend\npm test -- --run` | PASS; 3 archivos, 8 tests. |
| `frontend\npm run build` | PASS; 2295 módulos. |
| `docker compose config --quiet` | PASS. |
| Compose local + productivo con placeholders | PASS. |
| `docker build --pull -t gestudio-backend:phase2-test .\backend` | PASS; 44 tests dentro de la imagen. |
| `docker build --pull ... -t gestudio-frontend:phase2-test .\frontend` | PASS. |

## Fallos durante la fase

La primera ejecución de la suite WebMvc tuvo 10 errores de `ParameterResolutionException` porque el constructor de test no estaba marcado para autowiring. Producción compilaba y los tests unitarios pasaban. Se corrigió el wiring del test y las siguientes ejecuciones pasaron. No quedó un fallo de código o infraestructura abierto.

## Riesgo pendiente: reutilización de refresh

Cada refresh emitido es distinto y tiene `jti`, pero no existe persistencia de sesiones o familias de tokens. Un refresh anterior sigue siendo criptográficamente válido hasta expirar. No se implementó un denylist en memoria porque fallaría con reinicios o múltiples instancias y daría una garantía falsa.

La corrección durable requiere una migración forward-only, estado de sesión asociado al usuario y rotación atómica probada con PostgreSQL concurrente. Queda registrada para las fases 7 y 8. Esta limitación es heredada; no fue introducida por la fase.

## Otros riesgos pendientes

- Cualquier rol adicional existente en una base real debe inventariarse: las migraciones auditadas sólo crean `ADMINISTRADOR`.
- No existe identidad de alumno, por lo que recibos/facturas usan autorización administrativa y no ownership de alumno.
- Las autoridades de negocio granulares requieren un modelo real de permisos; no se agregaron strings ceremoniales.
- Los warnings de compilación preexistentes continúan sin silenciar.

## Gate

El gate MockMvc de Fase 2 está completo y los gates de Fase 1 continúan verdes. Se puede iniciar Fase 3.
