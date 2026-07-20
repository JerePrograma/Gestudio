# Estado del proyecto y handoff

## Snapshot activo

| Campo | Valor |
|---|---|
| Fecha | 2026-07-20 |
| Main inicial | `15481e38f0cf714607d0f7d5c3279a46315d7b5d` |
| Main previo al emisor | `ef4f9c31dab9a3dfce43f913177089f80ae0205a` |
| Main posterior al emisor | `e1afec960ddeb72d61932a1eb1f4a83a65899540` |
| Rama documental | `agent/record-student-emitter-merge` |
| Issues | #14 cerrado por el emisor; #16 continuidad post-merge |
| Entrega | PR #15, head `0650d18599da173a3443f73e979f2842ab1357ea`, merge `e1afec960ddeb72d61932a1eb1f4a83a65899540` |
| CI exacta | runs `29767996880` y `29767996913`, PASS |
| Integración plataforma | Jere Platform PR #60, CI `29765655168`, merge `22b1d2bd02d2a7b3d3dd415b26f56761285611a2`; issue coordinador #51 continúa abierto |

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
| Smoke cruzado | VALIDADO LOCALMENTE Y EN CI POR REPOSITORIO | artefactos runtime old/new consumidos por receptor PostgreSQL; ambos heads con CI verde |
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
| Suite completa previa al avance de main | PASS | `mvn -B -f backend/pom.xml clean verify`: 142/142 |
| Suite completa tras integrar main | PASS | `mvn -B -f backend/pom.xml clean verify`: 162/162; la fixture del scheduler ahora aísla las inscripciones activas heredadas del contenedor compartido |
| Frontend | PASS | `npm ci`, lint, 22 archivos/142 tests y build |
| Smoke local | PASS | `scripts/smoke-local.ps1`: 20/20, Flyway V1-V7, RBAC, restart e integridad |
| Seed demo | PASS | `scripts/validate-demo-seed.ps1 -SkipBackendBuild`: PostgreSQL efímero, V1-V7, RBAC, HTTP, segunda aplicación idéntica y limpieza |
| Parser demo local | PASS | parser nativo PowerShell sin errores |
| CI del head | PASS | `29767996880`: validate, imágenes y smoke; `29767996913`: alcance, smoke local, seed demo y entorno; GitGuardian PASS |

## Riesgos y próxima acción

1. Mantener el emisor deshabilitado hasta contar con configuración, secretos y
   operación de despliegue verificables; el merge no es evidencia de producción.
2. No volver a fijar en scripts operacionales una cantidad histórica de
   migraciones sin actualizar el gate junto con una migración nueva.
3. Mantener la copia offline del contrato sincronizada con el SHA y checksum de
   procedencia ante cualquier cambio posterior.
4. No afirmar deployment: el estado máximo de esta misión es validado localmente.


## Reconciliación de release gates

- GATE-1B permanece cerrado e integrado en `main` desde `ef4f9c31dab9a3dfce43f913177089f80ae0205a`.
- El emisor V7 no habilita despliegue ni transporte automático.
- El receptor multi-página quedó integrado por `JerePrograma/jere-platform#60`; Gestudio sólo materializa y expone artefactos administrativos con la función deshabilitada por defecto.
- Smoke, seed, documentación y scripts validan V1-V7 en los runs exactos `29767996880` y `29767996913`.
