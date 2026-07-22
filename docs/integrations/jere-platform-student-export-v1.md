# Emisor Jere Platform de estudiantes v1

## Propósito y ownership

Gestudio es propietario del perfil, estado académico y selección de estudiantes.
Esta integración publica únicamente referencias mínimas `GESTUDIO_STUDENT` para
que Jere Platform mantenga su Party Reference Directory sin leer la base de
Gestudio ni copiar el dominio Estudiante.

Contrato controlado:

- repositorio: `JerePrograma/jere-platform`;
- ruta: `contracts/parties/source-export-v1.schema.json`;
- versión: `1`;
- commit de contrato auditado: `bebfe716780a1ea42cc65be6441af9cc5dfe5bae`;
- extensión multipágina compatible: issue de plataforma #59 y ADR 0010.

La copia de test en
`backend/src/test/resources/contracts/party-source-export-v1.schema.json` existe
sólo para conformidad offline. Su procedencia y SHA-256 normalizado están fijados
en `party-source-export-v1.provenance.properties`; debe compararse con el schema
publicado en cada cambio de contrato. No es una dependencia Java ni autoriza
copiar modelos.

## Tenant mapping

Gestudio opera una academia por deployment y no tiene una entidad tenant u
organización multiempresa. El mapping es por configuración del deployment y
falla cerrado:

| Dato | Variable | Regla |
|---|---|---|
| Organización interna | `APP_JERE_PLATFORM_STUDENT_EXPORT_ORGANIZATION_ID` | Identificador estable, 1..100 caracteres, no un nombre derivado |
| Tenant externo | `APP_JERE_PLATFORM_STUDENT_EXPORT_TENANT_ID` | UUID explícito de Jere Platform |
| Estado | `APP_JERE_PLATFORM_STUDENT_EXPORT_ENABLED` | Debe ser `true` |
| Fuente | configuración operacional | Administrada por el operador del deployment |

No existe tenant en el request ni fallback por nombre o ID coincidente. Si el
mapping cambia, los snapshots anteriores dejan de ser recuperables bajo el nuevo
tenant. Un usuario de Gestudio no puede elegir otro tenant.

## Datos y minimización

| Campo del contrato | Fuente Gestudio | Transformación | Sensibilidad | Justificación |
|---|---|---|---|---|
| `sourceId` | `alumnos.id` | decimal como string | identificador interno | referencia estable y tenant-bound |
| `displayName` | `alumnos.nombre`, `alumnos.apellido` | trim y espacios colapsados; máximo 200 | dato personal mínimo | identificación operativa exigida por el contrato |
| `active` | `alumnos.activo` | booleano sin inferencias | baja | reconciliar estado sin copiar semántica académica |

La consulta no lee ni exporta documento, email, teléfono, domicilio, nacimiento,
responsables, notas, salud, becas, cuotas, deuda, asistencia, disciplina ni
metadata libre. Los tests inspeccionan los bytes emitidos y bloquean campos extra.

## Snapshot, checkpoint y cursor

- Un `POST` materializa todos los alumnos ordenados por ID ascendente.
- Cada ejecución recibe un checkpoint UUID nuevo e inmutable.
- Las páginas, bytes UTF-8, hash SHA-256 y firma se guardan en PostgreSQL dentro
  de una sola transacción.
- El primer cursor es implícito; los siguientes son UUID opacos aleatorios.
- `GET` recupera los bytes persistidos. Cambios posteriores o reinicios no
  alteran un snapshot existente.
- `pageNumber` y `pageCount` permiten al receptor probar orden y completitud.
- Sólo la última página tiene `fullSnapshot: true` y `nextCursor: null`.
- El tamaño configurado es 1..1000 registros y cada payload se limita a
  1.000.000 bytes.
- Un error durante creación revierte header y páginas; no se expone un snapshot
  parcialmente materializado.

Flyway V7 crea `jere_platform_student_export_snapshots` y
`jere_platform_student_export_pages`. Los snapshots son append-only. La política
automática de retención queda pendiente del diseño operacional previo a despliegue.

## Serialización y firma

`StudentSourceExportSerializer` usa una copia configurada de Jackson, UTF-8,
propiedades en orden explícito, inclusión de nulls y sin pretty printing. El flujo
serializa una sola vez, firma exactamente ese `byte[]` con HMAC-SHA256 y persiste
los mismos bytes que entrega el controller.

`APP_JERE_PLATFORM_STUDENT_EXPORT_CURRENT_SECRET` es obligatorio al habilitar la
integración, independiente y de al menos 32 bytes UTF-8. No se versiona, imprime
ni incluye en archivos de ejemplo. El emisor firma siempre con el secreto actual.

Rotación coordinada:

1. configurar en el receptor el secreto nuevo como actual y el anterior en su
   slot previo;
2. cambiar el secreto actual del emisor mediante el secret manager y reiniciar;
3. generar un checkpoint nuevo, que queda firmado con el secreto nuevo;
4. mantener el anterior en el receptor durante la ventana acordada para replays
   de snapshots ya persistidos;
5. retirar el anterior del receptor al cerrar la ventana.

Para rollback del emisor se restaura la versión anterior desde el secret manager;
no existe un segundo secreto de firma activo dentro de Gestudio.

## Transporte y autorización

La v1 usa un endpoint administrativo interno; no agrega broker, scheduler ni
envío automático:

```text
POST /api/integraciones/jere-platform/estudiantes/snapshots
GET  /api/integraciones/jere-platform/estudiantes/snapshots/{checkpoint}?cursor=...
```

La respuesta es el JSON persistido exacto. Los headers incluyen source type,
firma, checkpoint, página, total, correlation ID y, cuando corresponde, próximo
cursor. `Cache-Control: no-store` impide cache intermedia.

Spring Security y el servicio exigen simultáneamente `PERM_CONFIG_ADMIN` y
`PERM_REPORTES_EXPORTAR`. El mapping, el secreto y el actor se vuelven a validar
en cada operación. La creación y cada emisión registran auditoría `SISTEMA` con
metadata sanitizada; logs y auditoría omiten payload, firma y secreto.

## Errores

| Código | HTTP | Significado |
|---|---:|---|
| `tenant_mapping_disabled` | 503 | integración deshabilitada |
| `tenant_mapping_missing` | 503 | mapping incompleto |
| `tenant_mapping_invalid` | 400 | organización o UUID inválido |
| `source_secret_missing` | 503 | secreto ausente |
| `source_secret_too_short` | 503 | secreto menor a 32 bytes |
| `snapshot_not_found` | 404 | checkpoint inexistente o inválido |
| `cursor_invalid` | 400 | cursor malformado o ajeno al snapshot |
| `page_too_large` | 422 | configuración o total de páginas fuera de límite |
| `payload_too_large` | 422 | JSON mayor a 1 MB |
| `student_reference_invalid` | 422 | ID o display name inválido |
| `serialization_failed` | 500 | no se pudo producir JSON |
| `signature_failed` | 500 | no se pudo firmar |

El transporte v1 no llama al receptor: `receiver_rejected`, `receiver_conflict`,
`receiver_unauthorized` y `receiver_unavailable` pertenecen al harness/operador
que reenvía el artefacto, no al API de exportación. Un receptor indisponible no
modifica el snapshot; se reintenta luego con los mismos bytes y firma.

## Operación y recovery

1. crear el snapshot una vez;
2. conservar checkpoint, cursor y headers sin registrar body o firma;
3. reconciliar cada página y sólo luego importarla en Jere Platform;
4. continuar con el cursor devuelto por Gestudio;
5. ante error transitorio, repetir exactamente la misma página;
6. ante conflicto de contenido, abandonar el checkpoint y crear uno nuevo;
7. una ausencia reportada por la página final requiere revisión; nunca elimina
   automáticamente un estudiante o referencia.

El smoke cruzado se ejecuta desde Jere Platform:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\smoke-gestudio-source-export.ps1 `
  -GestudioRepository (Resolve-Path '<raíz-del-checkout-de-Gestudio>').Path
```

Genera secreto y artefactos sintéticos sólo durante la ejecución, usa
Testcontainers/PostgreSQL para ambos sistemas y produce un informe sanitizado.
No demuestra deployment productivo.

## Limitaciones explícitas

- una academia por deployment; no hay contexto multi-organización en Gestudio;
- transporte manual/operador, no push automático;
- sin UI, scheduler, broker ni almacenamiento externo;
- sin política automática de retención;
- sin Scalaris;
- sin sincronización bidireccional ni datos académicos/financieros.
