# Estado del proyecto y handoff

## Snapshot activo

| Campo | Valor |
|---|---|
| Fecha | 2026-07-20 |
| Main inicial | `15481e38f0cf714607d0f7d5c3279a46315d7b5d` |
| Main integrado | `ef4f9c31dab9a3dfce43f913177089f80ae0205a` |
| Rama activa | `feature/signed-student-source-export-v1` |
| Issue | #14 |
| PR | #15, draft |
| Implementación | `4c88635e76d7814b91e1a8baacf7a9db3a8ca81d` |
| Merge de main | `a1c27dd082d8078acf6d631cbf36ba20a661fd24` |
| Head publicado | `b4063800aff8b90378397ccc090d22d3448cc0d2` |
| CI | runs `29765652183`/`29765652777`: backend/frontend PASS; smoke y seed FAIL por expectativa obsoleta V1-V6, corregida y validada localmente; nuevo head pendiente |
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
| Suite completa previa al avance de main | PASS | `mvn -B -f backend/pom.xml clean verify`: 142/142 |
| Suite completa tras integrar main | PASS | `mvn -B -f backend/pom.xml clean verify`: 162/162; la fixture del scheduler ahora aísla las inscripciones activas heredadas del contenedor compartido |
| Frontend | PASS | `npm ci`, lint, 22 archivos/142 tests y build |
| Smoke local | PASS | `scripts/smoke-local.ps1`: 20/20, Flyway V1-V7, RBAC, restart e integridad |
| Seed demo | PASS | `scripts/validate-demo-seed.ps1 -SkipBackendBuild`: PostgreSQL efímero, V1-V7, RBAC, HTTP, segunda aplicación idéntica y limpieza |
| Parser demo local | PASS | parser nativo PowerShell sin errores |
| CI del head | PENDIENTE | PR #15; publicar las correcciones y validar el SHA nuevo |

## Riesgos y próxima acción

1. Publicar las correcciones de los gates operacionales; validar CI del SHA nuevo
   y revisar comentarios.
2. No volver a fijar en scripts operacionales una cantidad histórica de
   migraciones sin actualizar el gate junto con una migración nueva.
3. Mantener la copia offline del contrato sincronizada con el SHA y checksum de
   procedencia ante cualquier cambio posterior.
4. No afirmar deployment: el estado máximo de esta misión es validado localmente.


## Reconciliación de release gates

- GATE-1B permanece cerrado e integrado en `main` desde `ef4f9c31dab9a3dfce43f913177089f80ae0205a`.
- El emisor V7 no habilita despliegue ni transporte automático.
- La integración multi-página sigue bloqueada externamente por `JerePrograma/jere-platform#59`; Gestudio sólo materializa y expone artefactos administrativos con la función deshabilitada por defecto.
- Smoke, seed, documentación y scripts deben validar V1-V7 antes de fusionar PR #15.
