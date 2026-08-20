# Seguridad

> Estado: IMPLEMENTADO; EVIDENCIA INTEGRAL PENDIENTE
> Última revisión: 2026-08-13
> Fuentes principales: `SecurityConfigurations`, `PermissionCodes`, autenticación, pruebas y configuración

## Modelo

Spring Security usa dos `SecurityFilterChain` stateless:

1. `/actuator/**`: health público; Prometheus exige token; lo demás se deniega.
2. Aplicación: JWT, CORS, sin form login/basic, y autorización explícita por método/ruta.

CSRF está deshabilitado porque la API usa bearer access token; refresh/logout compensan el uso de cookie validando `Origin`.

El control plane añade una cadena/namespace separado para `/api/platform/**`.
Los tokens declaran scope, audiencia y tipo: PLATFORM prohíbe claims tenant y
TENANT no satisface rutas globales. La capacidad global procede de
`platform_admins`, no de un rol tenant llamado `SUPERADMIN`. Login/refresh usan
cookie de plataforma separada; MFA es obligatorio y las mutaciones sensibles
requieren step-up ligado a sesión/acción/target/idempotencia. Ver
[ADR-0009](../architecture/adr-0009-platform-control-plane.md) y el
[threat model](../architecture/threat-model-platform-control-plane.md).

## Tokens y sesiones

- Access token se devuelve en JSON.
- Refresh token se guarda en cookie `HttpOnly`.
- Cookie configurable: `Secure`, `SameSite`, path y dominio.
- Refresh rota sesión y tokens.
- Reutilización de refresh produce 409 y revocación.
- Token expirado, firma/issuer/tipo inválido o usuario inactivo produce 401.
- `authVersion` invalida tokens emitidos previamente.

## Autorización

Cada endpoint funcional exige:

```text
PERM_APP_ACCESO + permiso funcional
```

Dos permisos se exigen simultáneamente en exportaciones específicas. Roles activos suman permisos activos. Ruta nueva no declarada queda denegada.

Hay 32 códigos; ver [25-rbac-and-route-matrix.md](25-rbac-and-route-matrix.md).

## Respuestas

- 401: falta o invalidez de autenticación.
- 403: autenticado sin permiso.
- 400: validación.
- 500: mensaje sanitizado sin excepción interna.

`ApiErrorResponse` es el contrato común.

## CORS y navegador

Producción exige orígenes explícitos HTTPS. Preflight `OPTIONS` está permitido. Se exponen `Authorization` y `X-Request-ID` cuando corresponde. Frontend no debe tratar 403 como expiración.

## Observabilidad

- `/actuator/health/**`: público.
- `/actuator/prometheus`: cabecera `X-Gestudio-Metrics-Token`.
- Token ausente, inválido o repetido: 401.
- El token de métricas no se reutiliza como `JWT_SECRET` ni se envía al navegador.

## Entrada y datos sensibles

Bean Validation limita tamaños y formatos. No registrar contraseñas, tokens, cookies, payloads completos, datos personales extensos, cuerpos de email ni credenciales DB.

Secretos esperados: DB, JWT, SMTP/IMAP, métricas, bootstrap/reset local y firma Jere Platform. Sólo nombres de variables y plantillas pueden versionarse.

## Producción fail-closed

Perfil productivo exige configuración externa de datasource, JWT, correo, timezone, CORS, recibos y métricas. La exportación Jere permanece apagada si mapping o secreto no son válidos.

## Pruebas de seguridad

`SecurityHttpIntegrationTest` cubre 146 mappings, 401/403, roles múltiples, permisos inactivos, authVersion, CORS, sanitización de 500 y políticas por familia. La certificación integral ejecuta además smoke y demo pública.

## Riesgos

Ver [18-known-risks-and-technical-debt.md](18-known-risks-and-technical-debt.md): endpoint generativo de notificaciones, controlador dormante, infraestructura productiva no acreditada y permisos catalogados sin ruta explícita.
