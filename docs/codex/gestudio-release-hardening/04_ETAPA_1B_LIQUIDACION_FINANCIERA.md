# Etapa 1B — Liquidación financiera por vigencia

Estado actual: `PENDING` / `NO AUTORIZADA`. No hay tarea E1B activa. La única tarea global `IN_PROGRESS` es `E1-001`. Esta etapa comienza sólo cuando [GATE-1](./03_ETAPA_1_SEGURIDAD_RBAC.md) esté cerrado y el usuario autorice expresamente continuar.

Referencias: [baseline financiero](./01_BASELINE_Y_HALLAZGOS.md#hallazgos-p0-financieros), [plan de pruebas](./08_PLAN_DE_PRUEBAS.md), [DEC-PRICING-001](./10_DECISIONES_Y_BLOQUEOS.md#dec-pricing-001--contrato-de-liquidación-por-vigencia) y [bitácora](./09_BITACORA_IMPLEMENTACION.md).

## Objetivo

Eliminar la doble fuente de precios. Una fecha efectiva debe resolver una única tarifa y una única condición económica; mensualidad o matrícula debe crear el cargo y su `cargo_liquidaciones` auditable en la misma transacción, con `BigDecimal`, escala/redondeo explícitos e idempotencia.

## Fuera de alcance

- No iniciar antes de GATE-1 ni continuar a Etapa 2.
- No reescribir V1-V5 ni usar el seed demo como migración.
- No rediseñar pagos, crédito, caja o recibos salvo el contrato mínimo necesario para consumir el cargo correcto.
- No borrar cargos ni snapshots históricos.
- No agregar una abstracción paralela si `TarifaDisciplinaServicio`, `CondicionEconomicaServicio` y `LiquidacionCargoServicio` cubren el límite real.
- No decidir importes, prioridad o fechas por conveniencia técnica: requieren `DEC-PRICING-001`.

## Dependencias

1. GATE-1 cerrado: catálogo RBAC determinístico, permisos de tarifas/condiciones y semántica 401/403/409.
2. Autorización explícita del usuario para Etapa 1B.
3. `DEC-PRICING-001` confirmada antes de cambiar cálculo.
4. Cadena Flyway efectiva verificada después de Etapa 1. V1-V5 quedan inmutables; V6 se reserva para RBAC. Si 1B necesita esquema, usar la siguiente versión libre, previsiblemente V7, nunca asumirla sin inspección.
5. Docker Engine disponible para PostgreSQL/Testcontainers.

## Mapa del cálculo actual

| Flujo | Comportamiento actual | Evidencia | Problema |
|---|---|---|---|
| Mensualidad | base = `Inscripcion.costoParticular` o `Disciplina.valorCuota`; aplica `Bonificacion` legacy; vence día 10 | `backend/src/main/java/gestudio/servicios/mensualidad/MensualidadServicio.java` | no consulta tarifa/condición por `vigenteDesde` |
| Matrícula | máximo de `Disciplina.matricula` entre inscripciones activas; vence 31/01 | `backend/src/main/java/gestudio/servicios/matricula/MatriculaServicio.java` | no consulta tarifa histórica ni define disciplina/origen ganador |
| Tarifa | repositorio resuelve última `vigenteDesde <= fecha` y falla si falta | `TarifaDisciplinaRepositorio.java`, `TarifaDisciplinaServicio.java` | contrato correcto aún no conectado a cargos |
| Condición | repositorio resuelve última `vigenteDesde <= fecha`, con snapshots de bonificación | `CondicionEconomicaRepositorio.java`, `CondicionEconomicaServicio.java` | no conectada a mensualidad/matrícula |
| Snapshot | inserta una fila en `cargo_liquidaciones` | `backend/src/main/java/gestudio/cuotas/application/LiquidacionCargoServicio.java`, V4 | no tiene caller productivo |
| UI | edita precio legacy y también historiales efectivos | `InscripcionesFormulario.tsx`, `CondicionesEconomicasPagina.tsx`, `DisciplinasPagina.tsx`, `TarifasDisciplinaPagina.tsx` | presenta dos fuentes de verdad |

## Decisiones obligatorias antes de código

Todas forman un único contrato indivisible en `DEC-PRICING-001`:

| Tema | Opciones concretas | Recomendación pendiente de aprobación |
|---|---|---|
| Fecha mensual | primer día del período; fecha de generación; vencimiento | primer día de `YearMonth`, porque representa el período y no depende del día de ejecución |
| Fecha matrícula | 1 de enero del año; fecha de emisión; vencimiento | 1 de enero del año, consistente para todos los alumnos del período |
| Sin tarifa | fallback legacy; cargo cero; rechazar | rechazar la liquidación con error de tarifa histórica faltante; nunca cobrar silenciosamente legacy/cero |
| Prioridad | tarifa siempre; costo particular siempre; condición efectiva no nula y luego tarifa | condición efectiva con `costoParticular` no nulo; si es nulo, tarifa efectiva |
| Bonificación | entidad legacy mutable; snapshot de condición; combinación | usar sólo snapshots de la condición efectiva; no combinar dos bonificaciones |
| Historia | última fila `<= fecha`; rango explícito con fin; dato actual | última fila `<= fecha`, ya soportada por repositorios; una fila posterior cierra implícitamente la anterior |
| Campos legacy | borrar; seguir escribiendo/leyendo; compatibilidad sin lecturas financieras | dejar físicamente por compatibilidad, retirar del cálculo y de la edición operativa; eliminar sólo con migración posterior y reconciliación |
| Fórmula | sin versión; entero constante; motor configurable | entero constante inicial `1`, persistido en cada snapshot; cambiarlo sólo al cambiar semántica |
| Matrícula con varias disciplinas | máximo; suma; una por disciplina; política institucional | requiere confirmación explícita; el comportamiento actual es máximo y no prueba intención de negocio |

Hasta que estas decisiones se confirmen, `E1B-001` sigue `PENDING` y ninguna tarea de cálculo puede comenzar.

## Orden obligatorio de tareas

### `E1B-001` — Mapear cálculo y cerrar decisiones

- Estado: `PENDING`.
- Dependencias: GATE-1, autorización de Etapa 1B.
- Archivos: servicios/repositorios de mensualidad, matrícula, tarifas, condiciones; V3/V4; tests PostgreSQL; `10_DECISIONES_Y_BLOQUEOS.md`.
- Cambio esperado: caracterización ejecutable del comportamiento actual y aprobación de `DEC-PRICING-001`.
- Riesgo: cambiar importes históricos por una suposición.
- Aceptación: tabla de casos con fecha, tarifa, condición, base, descuento, total, origen y fórmula; política de matrícula explícita.
- Tests: primero tests de caracterización de mensualidad y matrícula; deben fallar sólo al expresar el defecto nuevo esperado.
- Evidencia de cierre: comando focalizado, conteos y decisión aprobada en bitácora.

### `E1B-002` — Resolver un único servicio de liquidación

- Estado: `PENDING`.
- Dependencias: `E1B-001`.
- Archivos esperados: `TarifaDisciplinaServicio.java`, `CondicionEconomicaServicio.java`, `LiquidacionCargoServicio.java` y un servicio concreto existente/nuevo sólo si no hay punto de composición reutilizable.
- Cambio esperado: una operación recibe inscripción/disciplina, fecha efectiva y tipo; devuelve importe y metadatos usando `BigDecimal` y la fórmula aprobada.
- Riesgo: crear un segundo motor o esconder fallback legacy.
- Aceptación: ningún consumidor recalcula; ausencia de historia produce el error acordado; prioridad y redondeo tienen una sola implementación.
- Tests: unitario de fórmula más PostgreSQL para resolución `<= fecha`.
- Evidencia: test focalizado verde y búsqueda que muestre una sola implementación de fórmula.

### `E1B-003` — Integrar mensualidades

- Estado: `PENDING`.
- Dependencias: `E1B-002`.
- Archivos: `MensualidadServicio.java`, tests nuevos o ampliados en `backend/src/test/java/gestudio/servicios/mensualidad/`.
- Cambio esperado: usar primer día del período u otra fecha aprobada y consumir el resultado único.
- Riesgo: scheduler/manual produzcan importes distintos o dupliquen cargos.
- Aceptación: creación manual y scheduler comparten ruta; tarifa futura no afecta período anterior; idempotencia conserva el primer resultado.
- Tests: límite día anterior/mismo día/posterior, período pasado/futuro, retry concurrente.
- Evidencia: tests focalizados y Testcontainers verdes.

### `E1B-004` — Integrar matrículas

- Estado: `PENDING`.
- Dependencias: `E1B-002`, política de matrícula aprobada.
- Archivos: `MatriculaServicio.java` y tests en `backend/src/test/java/gestudio/servicios/matricula/`.
- Cambio esperado: resolver fecha/tarifa conforme a decisión; creación API y scheduler usan la misma ruta.
- Riesgo: alumno con varias disciplinas cobra monto arbitrario.
- Aceptación: política multi-disciplina probada; tarifa futura respeta año efectivo; retry no crea otra matrícula/cargo.
- Tests: cero/una/varias disciplinas, hueco histórico, límites e idempotencia.
- Evidencia: tests focalizados y PostgreSQL verdes.

### `E1B-005` — Persistir snapshot en la misma transacción

- Estado: `PENDING`.
- Dependencias: `E1B-003`, `E1B-004`.
- Archivos: `LiquidacionCargoServicio.java`, servicios de cargo, V4 y tests `CargoLiquidacionMigrationPostgreSqlTest.java`/nuevos.
- Cambio esperado: cargo + liquidación son atómicos; snapshot guarda IDs, origen, base, descuento, total y `formula_version`.
- Riesgo: cargo sin snapshot o snapshot duplicado.
- Aceptación: rollback de cualquier insert deja cero filas; PK `cargo_id` impide duplicado; cambiar tarifa/condición después no altera snapshot.
- Tests: transacción fallida, retry, mutación posterior de configuración, lectura del snapshot exacto.
- Evidencia: SQL/asserts PostgreSQL y suite focalizada verdes.

### `E1B-006` — Retirar la doble UI/campos legacy del cálculo

- Estado: `PENDING`.
- Dependencias: `E1B-003` a `005`.
- Archivos: `Disciplina.java`, `Inscripcion.java`, DTOs, formularios/páginas de disciplinas e inscripciones y, sólo si hace falta, siguiente migración Flyway disponible.
- Cambio esperado: campos legacy no participan en cálculo ni ofrecen edición financiera contradictoria; historia permanece legible.
- Riesgo: romper payloads o descartar datos ambiguos.
- Aceptación: búsqueda de callers prueba cero lecturas financieras legacy; UI presenta una fuente; cualquier migración incluye precondiciones, reconciliación y SQL de verificación.
- Tests: contratos backend/frontend, base limpia y upgrade desde cadena previa si hay esquema.
- Evidencia: `rg` de lecturas legacy, tests y reconciliación.

### `E1B-007` — Matriz de regresión financiera

- Estado: `PENDING`.
- Dependencias: `E1B-001` a `006`.
- Archivos: tests de tarifas/condiciones/mensualidades/matrículas/liquidaciones y `08_PLAN_DE_PRUEBAS.md`.
- Cambio esperado: cobertura ejecutable de vigencias, huecos, límites, snapshots, exactitud monetaria e idempotencia.
- Riesgo: suite verde sin probar PostgreSQL ni concurrencia.
- Aceptación: valores exactos por `compareTo`/strings a escala 2; ninguna prueba H2 sustituye PostgreSQL.
- Tests: `TarifaDisciplinaPostgreSqlTest`, `CondicionEconomicaPostgreSqlTest`, `CargoLiquidacionMigrationPostgreSqlTest`, nuevos flujos integrados y suite backend completa.
- Evidencia: comandos, conteos y resultados en bitácora.

## Estrategia mínima de implementación

1. Caracterizar antes de reemplazar.
2. Reutilizar los repositorios efectivos y `LiquidacionCargoServicio`; no crear interfaces ceremoniales.
3. Hacer que mensualidad/matrícula llamen a una única operación transaccional.
4. Persistir el snapshot inmediatamente después de crear/flush del cargo dentro de la misma transacción.
5. Quitar lecturas/UI legacy sólo cuando ambos flujos estén cubiertos.
6. Si no cambia esquema, no crear migración. Si cambia, usar la siguiente versión libre posterior a V6 y probar base limpia + upgrade.

## Riesgo y rollback lógico

- No hay rollback destructivo de cargos ni liquidaciones.
- Antes de despliegue, revertir código conservando compatibilidad con V1-V5/V6 y snapshots ya creados.
- Después de aplicar una migración, corregir forward-only; no editar una versión aplicada.
- Ante datos legacy ambiguos, generar reporte y bloquear esa fila; no normalizar importes automáticamente.
- Un fallo transaccional debe revertir cargo y snapshot juntos.

## Validación

Durante tareas, ejecutar el test focalizado con `Push-Location backend; .\mvnw.cmd -Dtest=Clase test; Pop-Location`. Al gate:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
```

Si hay migración, además: Flyway en PostgreSQL limpio, upgrade desde el estado inmediatamente anterior y consultas de reconciliación. No usar `localhost:5432` para pruebas destructivas.

## GATE-1B

- [ ] Tarifa futura no afecta período anterior.
- [ ] Sí afecta el período correspondiente.
- [ ] Condición efectiva aplica sólo desde su vigencia.
- [ ] Ausencia de tarifa sigue la decisión aprobada, sin fallback oculto.
- [ ] Cargo conserva snapshot aunque cambie configuración.
- [ ] Cargo y snapshot son atómicos y no se duplican.
- [ ] Mensualidad y matrícula no leen precios legacy.
- [ ] UI no ofrece dos fuentes de verdad.
- [ ] Exactitud monetaria, límites e idempotencia pasan en PostgreSQL.
- [ ] Base limpia/upgrade pasan si hubo migración.
- [ ] Backend, Frontend y All están clasificados y documentos actualizados.

Al cerrar GATE-1B: detenerse y pedir exactamente autorización para Etapa 2. No iniciar UX operativa por cuenta propia.
