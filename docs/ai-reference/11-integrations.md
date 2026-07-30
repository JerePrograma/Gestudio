# Integraciones

> Estado: CONFIRMADO  
> Última revisión: 2026-07-30
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

`IEmailService` es la frontera única para cumpleaños y recibos. La selección por
`APP_EMAIL_PROVIDER` ofrece `NOOP`, `FAKE` y `GMAIL_SMTP`; el default de todos
los perfiles, incluido `prod`, es `NOOP`.

Gmail SMTP sólo alcanza `JavaMailSender` cuando enabled, dry-run, kill switch y
política de red lo permiten y la configuración completa es válida. El sender
sale de configuración, MIME/adjuntos tienen límites, TLS y timeouts son
explícitos. La copia Sent está deshabilitada por defecto; `BEST_EFFORT` distingue
un append fallido de un SMTP aceptado y no reenvía. `REQUIRED` se rechaza porque
SMTP e IMAP no son atómicos.

NOOP y FAKE se ejecutan sin red. Gmail SMTP fue probado con dobles, no con una
cuenta real. OAuth2 no está implementado y la producción no está desplegada.
Contrato y runbook: [entrega de email controlada](../integrations/gmail-email-delivery.md).

## Observabilidad

Actuator ofrece liveness/readiness y Prometheus. `RequestCorrelationFilter` propaga `X-Request-ID`. El repositorio no incluye el servidor externo, dashboards, alertas ni retención de logs.

## Almacenamiento de recibos

Filesystem configurable mediante `APP_RECEIPTS_PATH`; metadata en PostgreSQL. Backup/restore trata DB y recibos como conjunto con manifiesto y hashes.

## Cloudflare/demo remota

La documentación contiene contratos para Cloudflare Pages y demo remota. Es infraestructura demostrativa, no evidencia de staging/productivo.

## Pruebas/mocks

- Contrato Jere copiado a test con procedencia y hash.
- Testcontainers para snapshots/páginas.
- Selección de beans, política, MIME, SMTP/IMAP simulado, recibos y cumpleaños
  tienen regresiones sin red; `verify-email-delivery.ps1` las agrupa.
- Workflows verifican observabilidad, rollback y backup/restore.
