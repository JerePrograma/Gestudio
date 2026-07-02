# Gates de performance e integridad

| Flujo | Consulta/estrategia | Índice/constraint | Evidencia |
| --- | --- | --- | --- |
| Cargos pendientes | página por alumno/estado/fecha/id | `ix_cargos_alumno_pendientes` parcial | 20.000 cargos sintéticos; index-only, sin seq scan/sort |
| Alumnos | página con filtro y orden estable | `ix_alumnos_activos_nombre` | integración de primera/intermedia/última/vacía |
| Inscripciones | JPQL filtrado en DB + EntityGraph | índices alumno/estado y disciplina/estado | filtro combinado y página real |
| Pagos alumno | resumen proyectado por página | `ix_pagos_alumno_fecha` | sin hidratar aplicaciones en lista |
| Egresos | página fecha/id | `ix_egresos_fecha_metodo` | contrato máximo 200 |
| Stock | página nombre/id | `ix_stocks_activos_nombre` | contrato máximo 200 |
| Caja | agregados `FILTER` + página separada | fecha/método | signos y rango PostgreSQL |
| Schedulers | lock de IDs + lectura batch | uniques de período/origen | dos ejecuciones simultáneas |
| Outbox | `FOR UPDATE SKIP LOCKED` + lease | índice estado/next/lease, unique efecto | dos workers/recuperación |

El plan de cargos se valida por propiedades semánticas: resultado correcto,
ausencia de sequential scan, índice esperado o equivalente y orden correcto. No
hay umbral absoluto de milisegundos.

## Gate de reproducibilidad CI y Docker - 2026-07-01

| Gate | Evidencia |
| --- | --- |
| Backend | `mvnw.cmd clean verify`: PASS; 70 tests, 0 failures, 0 errors, 0 skipped; PostgreSQL 15.12 Testcontainers, Flyway V1, Hibernate validate, JaCoCo y JAR |
| Frontend | `npm ci`, lint, `npm test` y build: PASS; Vitest ejecutó una vez 7 archivos/16 tests y terminó sin modo watch |
| Scripts raíz | `status.ps1`, `setup.ps1` y `validate.ps1`: PASS; setup no inició servicios y validate cerró todos sus gates |
| Compose | Local y productivo con placeholders no sensibles: PASS; producción no publica PostgreSQL ni conserva builds de aplicación |
| Imágenes | Backend y frontend con `--pull`: PASS; tests/Testcontainers fuera de BuildKit, frontend con `npm ci`, runtimes mínimos y sin placeholders sensibles |

Advertencias no bloqueantes: auto-attach de Mockito/Byte Buddy, dialecto
PostgreSQL explícito, `open-in-view` predeterminado, aviso futuro de annotation
processing de `javac`, puerto host 5432 ocupado y nueva versión mayor de npm
disponible. No se corrigieron porque no son fallos de este gate.

La confirmación remota posterior quedó registrada en `CI Le Dance` run
`28544656047`: commit `33c03bbd7cadaa1342134156bc7cb8c9de22e795`, jobs
`validate` y `build-images` en `SUCCESS`.

## Gate de aislamiento PostgreSQL y concurrencia - 2026-07-01

El run `28539600117` demostró contaminación entre clases: paginación intentó
borrar alumnos referenciados por cargos y outbox podía dejar un claim esperando
si una aserción ocurría antes de liberar el latch. Los fixtures ahora truncan
sus datos reclamables/dependientes antes del seed y todos los waits, futures y
executors concurrentes tienen cierre acotado. La combinación problemática pasó
11/11 tests y dos `clean verify` consecutivos pasaron 70/70, sin errores,
omitidos ni aumento de `timeout-minutes`.

## Gate de smoke canónico aislado - 2026-07-02

El smoke usa un proyecto Compose, red, volumen PostgreSQL y volumen de recibos
distintos por ejecución; PostgreSQL sólo se consulta con `docker compose exec
-T db`. Dos ejecuciones completas consecutivas pasaron 19 pasos y 0 fallos:

| Proyecto | Puertos PostgreSQL/backend/frontend | Duración | Resultado |
| --- | --- | --- | --- |
| `ledance-smoke-21692-e608c2c9` | `60745` / `60746` / `60747` | `00:01:51` | PASS; cleanup y verificación externa sin recursos |
| `ledance-smoke-20344-716ba129` | `61952` / `61953` / `61954` | `00:01:37` | PASS; cleanup y verificación externa sin recursos |

Ambas comenzaron con V1 vacía, crearon un único `ADMINISTRADOR`, apagaron el
bootstrap antes del reinicio y recorrieron por API alumno, inscripción,
matrícula, cargo, pago parcial/total, retries, caja, egreso, stock y reversiones.
SQL quedó limitado a Flyway, hashes, relaciones no expuestas e invariantes. El
smoke demuestra creación y unicidad del outbox; no demuestra entrega SMTP
exactly-once y R31 continúa abierto.
