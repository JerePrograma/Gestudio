# Estado del proyecto y handoff

## Snapshot activo

| Campo | Valor |
|---|---|
| Fecha | 2026-07-20 |
| Main inicial | `15481e38f0cf714607d0f7d5c3279a46315d7b5d` |
| Rama activa | `feature/signed-student-source-export-v1` |
| Issue | #14 |
| PR | pendiente |
| Head | pendiente de commit |
| CI | pendiente; main tiene un fallo previo en `DataAuditSqlPostgreSqlTest` |
| Integración plataforma | issues Jere Platform #51/#59; contrato `bebfe716780a1ea42cc65be6441af9cc5dfe5bae` |

Git y GitHub son autoridad si este snapshot queda desactualizado.

## Capacidad

| Área | Estado | Evidencia |
|---|---|---|
| Tenant mapping explícito | IMPLEMENTADO | configuración fail-closed y tests negativos |
| Lectura mínima de estudiantes | IMPLEMENTADO | ID, nombre, apellido y activo, orden por ID |
| Snapshot materializado | IMPLEMENTADO | Flyway V7, payload y firma inmutables |
| Serialización/HMAC | IMPLEMENTADO | bytes únicos UTF-8 y HMAC-SHA256 |
| Transporte administrativo | IMPLEMENTADO | POST/GET internos, `no-store` |
| Autorización/auditoría | IMPLEMENTADO | dos permisos efectivos y auditoría sanitizada |
| Conformidad offline | IMPLEMENTADO | copia controlada del schema v1 y pruebas |
| Smoke cruzado | VALIDADO LOCALMENTE | artefactos runtime old/new consumidos por receptor PostgreSQL |
| Deployment productivo | PENDIENTE | no existe evidencia de infraestructura |
| Scalaris | BLOQUEADO | tenant mapping no definido |

## Archivos y migración

- `backend/src/main/java/gestudio/integraciones/jereplatform/`: contrato,
  aplicación, transporte, firma y persistencia.
- `backend/src/main/resources/db/migration/V7__jere_platform_student_source_exports.sql`:
  snapshots y páginas append-only.
- `backend/src/test/java/gestudio/integraciones/jereplatform/`: mapping,
  criptografía, contrato y PostgreSQL.
- `docs/integrations/jere-platform-student-export-v1.md`: operación y recovery.

V1-V7 son forward-only. Un error operacional se corrige con un checkpoint nuevo;
un error de schema requiere una migración posterior, nunca editar V7 fusionada.

## Validación ejecutada

| Control | Estado | Evidencia |
|---|---|---|
| Compilación backend | PASS | `mvn -B -f backend/pom.xml -DskipTests compile` |
| Tests unitarios focales | PASS | 7/7, incluidos límites 1.000/1 MB |
| PostgreSQL focal | PASS | 6/6, incluida generación de artefactos runtime |
| Smoke cruzado | PASS | secretos old/new runtime, receptor V8, import/replay/rotación/negativos |
| Suite completa | PASS | `mvn -B -f backend/pom.xml clean verify`: 142/142 |
| Frontend | PASS | `npm ci`, lint, 22 archivos/142 tests y build |
| CI del head | PENDIENTE | PR aún no abierto |

## Riesgos y próxima acción

1. Abrir PR draft, congelar el head, validar CI y revisar comentarios.
2. Mantener la copia offline del contrato sincronizada con el SHA y checksum de
   procedencia ante cualquier cambio posterior.
3. No afirmar deployment: el estado máximo de esta misión es validado localmente.
