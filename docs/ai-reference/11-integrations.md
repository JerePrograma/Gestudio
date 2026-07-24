# Integraciones

> Estado: CONFIRMADO  
> Última revisión: 2026-07-24  
> Fuentes principales: exportador Jere Platform, correo, observabilidad y almacenamiento

## Jere Platform

### Finalidad

Publicar referencias mínimas `GESTUDIO_STUDENT` sin exponer el dominio académico.

| Campo | Fuente |
|---|---|
| `sourceId` | `alumnos.id` como string |
| `displayName` | nombre + apellido normalizados |
| `active` | `alumnos.activo` |

No se exportan documento, contacto, nacimiento, responsables, salud, deuda, asistencia ni disciplina.

### Protocolo

```text
POST /api/integraciones/jere-platform/estudiantes/snapshots
GET  /api/integraciones/jere-platform/estudiantes/snapshots/{checkpoint}?cursor=...
```

- JSON UTF-8 persistido.
- HMAC-SHA256 sobre bytes exactos.
- Checkpoint y cursor opacos.
- Páginas 1..1000 registros, payload máximo 1 MB.
- `Cache-Control: no-store`.
- Headers de firma, checkpoint, página, total, correlación y cursor.
- Requiere `PERM_CONFIG_ADMIN` + `PERM_REPORTES_EXPORTAR`.

### Configuración

Mapping por deployment: organización interna estable, tenant UUID externo, flag de habilitación, secreto actual independiente y page size. Gestudio no es multitenant.

### Fallos y recuperación

La creación es atómica. Páginas son append-only e inmutables. Reintentar GET devuelve los mismos bytes. No hay push, broker, scheduler ni UI. Transporte desplegado y retención automática están pendientes.

## Email

`IEmailService` es la frontera. En `prod`, `EmailService`:

1. construye MIME UTF-8;
2. envía por SMTP;
3. intenta guardar el mensaje en carpeta Sent por IMAPS.

Si falla el append IMAPS, registra error después de que SMTP pudo haber enviado. En perfiles no productivos existe `NoOpEmailService`.

No se confirmaron reintentos ni timeouts explícitos en esta inspección.

## Observabilidad

Actuator ofrece liveness/readiness y Prometheus. `RequestCorrelationFilter` propaga `X-Request-ID`. El repositorio no incluye el servidor externo, dashboards, alertas ni retención de logs.

## Almacenamiento de recibos

Filesystem configurable mediante `APP_RECEIPTS_PATH`; metadata en PostgreSQL. Backup/restore trata DB y recibos como conjunto con manifiesto y hashes.

## Cloudflare/demo remota

La documentación contiene contratos para Cloudflare Pages y demo remota. Es infraestructura demostrativa, no evidencia de staging/productivo.

## Pruebas/mocks

- Contrato Jere copiado a test con procedencia y hash.
- Testcontainers para snapshots/páginas.
- Perfil dev/test usa email no-op.
- Workflows verifican observabilidad, rollback y backup/restore.
