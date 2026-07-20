# Etapa 1B — Liquidación financiera por vigencia

> Estado actual: **`READY_TO_START`**  
> Fecha de reconciliación: **2026-07-20**  
> Rama operativa: `main`  
> HEAD base revisado: `3f314ba8cc61a71bfa434a46593cd02336ec16e5`

El bloqueo anterior por merge RBAC está cerrado: GATE-1 forma parte de `main`.
Esta etapa puede comenzar. No está implementada ni validada todavía.

Referencias:

- [estado actual y backlog](./12_ESTADO_ACTUAL_Y_BACKLOG.md);
- [baseline financiero](./01_BASELINE_Y_HALLAZGOS.md#hallazgos-p0-financieros);
- [plan de pruebas](./08_PLAN_DE_PRUEBAS.md);
- [DEC-PRICING-001](./10_DECISIONES_Y_BLOQUEOS.md#dec-pricing-001--contrato-de-liquidación-por-vigencia);
- [bitácora de continuidad](./13_BITACORA_CONTINUIDAD.md).

## Objetivo

Eliminar la doble fuente de precios. Una fecha efectiva debe resolver una única
tarifa y una única condición económica. Mensualidad o matrícula debe crear el
cargo y su `cargo_liquidaciones` auditable dentro de la misma transacción, con
`BigDecimal`, escala explícita, fórmula versionada e idempotencia.

## Contrato aprobado

| Tema | Decisión vigente |
|---|---|
| Fecha efectiva mensual | Primer día del `YearMonth` |
| Fecha efectiva matrícula | 1 de enero del año |
| Ausencia de tarifa | Rechazar; sin fallback legacy ni importe cero silencioso |
| Prioridad de precio | `costoParticular` de condición efectiva no nulo; si no, tarifa efectiva |
| Bonificación | Sólo snapshots de la condición efectiva |
| Resolución histórica | Última fila con `vigenteDesde <= fecha` |
| Campos legacy | Compatibilidad física; fuera del cálculo y edición operativa |
| Fórmula inicial | `formula_version = 1` |
| Matrícula multidisciplina | Máximo importe efectivo entre disciplinas activas |
| Redondeo | Escala 2, `HALF_UP` donde exista operación porcentual |
| Idempotencia | Reintentos no duplican origen, cargo ni snapshot |

## Fuera de alcance

- reescribir V1-V6;
- usar el seed demo como migración;
- rediseñar pagos, crédito, caja o recibos salvo integración mínima;
- borrar cargos o snapshots históricos;
- agregar un motor configurable sin necesidad actual;
- normalizar automáticamente datos legacy ambiguos;
- crear una migración si no cambia el esquema;
- iniciar staging o producción.

## Mapa del cálculo actual

| Flujo | Estado actual | Defecto |
|---|---|---|
| Mensualidad | Usa `Inscripcion.costoParticular` o `Disciplina.valorCuota`; bonificación legacy | Ignora vigencias y snapshots |
| Matrícula | Usa máximo de `Disciplina.matricula` | Ignora tarifa histórica y origen ganador |
| Tarifa | Resuelve última `vigenteDesde <= fecha` | Correcto pero sin caller financiero |
| Condición | Resuelve última `vigenteDesde <= fecha` y snapshots | Correcto pero sin caller financiero |
| Snapshot | `LiquidacionCargoServicio.registrar(...)` inserta `cargo_liquidaciones` | No está conectado a mensualidades/matrículas |
| Cargo | `CargoServicio` es idempotente por origen | Debe participar en una transacción con snapshot |
| UI | Conserva precio legacy e historiales efectivos | Presenta dos fuentes de verdad |

## Orden obligatorio

### `E1B-001` — Caracterizar el cálculo vigente

Estado: `READY`.

Objetivo:

- crear casos ejecutables antes de reemplazar comportamiento;
- registrar fecha, tarifa, condición, base, descuento, total, origen y fórmula;
- demostrar explícitamente qué falla hoy.

Casos mínimos:

1. tarifa anterior, exacta y futura;
2. condición anterior, exacta y futura;
3. costo particular nulo y no nulo;
4. bonificación porcentual;
5. bonificación fija;
6. combinación de porcentaje y fijo;
7. descuento mayor a la base;
8. ausencia de tarifa;
9. ausencia de condición;
10. mensualidad pasada, actual y futura;
11. matrícula con cero, una y varias disciplinas;
12. reintento secuencial y concurrente.

Aceptación:

- tests de caracterización compilables;
- defectos actuales señalados sin adaptar expectativas para ocultarlos;
- tabla de casos registrada en bitácora;
- ninguna modificación productiva antes de entender los fallos.

### `E1B-002` — Resolución única de liquidación

Estado: `PENDING`.

Crear o adaptar un único punto de composición que reciba:

- inscripción;
- disciplina;
- fecha efectiva;
- tipo de origen;
- actor opcional.

Debe devolver un resultado inmutable con:

- tarifa usada;
- condición usada;
- origen del precio;
- importe base;
- descuento porcentual;
- descuento importe;
- importe final;
- versión de fórmula;
- observación trazable.

Reglas:

- cero lecturas de `Disciplina.valorCuota`, `Disciplina.matricula` e
  `Inscripcion.costoParticular` para cálculo nuevo;
- ausencia de tarifa aborta;
- la condición es opcional: si no existe, tarifa sin descuento;
- si existe condición, sus snapshots son autoridad;
- importe final no puede ser negativo;
- escala 2 en todos los importes persistidos.

### `E1B-003` — Integrar mensualidades

Estado: `PENDING`.

Cambios esperados:

- fecha efectiva = primer día del período;
- creación manual y scheduler comparten la misma ruta;
- cargo y snapshot se crean dentro de la misma transacción;
- reintento devuelve el resultado existente;
- una tarifa futura no cambia un período anterior;
- ausencia de historia falla antes de persistir un origen incompleto.

### `E1B-004` — Integrar matrículas

Estado: `PENDING`.

Cambios esperados:

- fecha efectiva = 1 de enero del año;
- calcular la tarifa efectiva de cada disciplina activa;
- elegir el mayor importe final conforme al contrato aprobado;
- registrar qué disciplina, tarifa y condición originaron el cargo;
- creación API y scheduler comparten implementación;
- reintento no duplica matrícula, cargo ni snapshot.

### `E1B-005` — Atomicidad de cargo y snapshot

Estado: `PENDING`.

Aceptación:

- un fallo de snapshot revierte el cargo;
- un fallo de cargo no deja snapshot;
- `cargo_id` conserva una única liquidación;
- cambiar tarifa o condición después no altera el snapshot;
- actor, IDs, base, descuento, total y fórmula quedan trazados.

### `E1B-006` — Retirar doble fuente legacy

Estado: `PENDING`.

Aceptación:

- cero lecturas financieras legacy;
- formularios no permiten editar valores que ya no gobiernan el cálculo;
- DTOs conservan compatibilidad sólo cuando sea necesario;
- no se eliminan columnas sin migración y reconciliación;
- datos ambiguos se reportan y bloquean.

### `E1B-007` — Regresión financiera

Estado: `PENDING`.

Debe cubrir:

- límites de vigencia;
- huecos históricos;
- snapshots;
- exactitud monetaria;
- mensualidad manual/scheduler;
- matrícula manual/scheduler;
- concurrencia;
- rollback transaccional;
- PostgreSQL real;
- base limpia y upgrade si aparece una migración.

## Diseño mínimo recomendado

No crear un framework de pricing. La solución mínima defendible es:

1. un resultado inmutable de liquidación;
2. un servicio único que consulte tarifa y condición efectivas;
3. mensualidad y matrícula como orquestadores;
4. `CargoServicio` para persistir el cargo idempotente;
5. `LiquidacionCargoServicio` para snapshot dentro de la transacción exterior;
6. tests PostgreSQL para resolución, atomicidad e idempotencia.

## Riesgos

### Bloqueantes

- cambiar importes sin caracterización;
- mantener fallback legacy;
- crear cargos sin snapshot;
- elegir matrícula multidisciplina sin dejar origen trazado.

### Altos

- que scheduler y API diverjan;
- que un retry reutilice el origen pero duplique snapshot;
- que una condición futura se aplique retroactivamente;
- que el UI siga editando la fuente legacy.

### Medios

- redondeo inconsistente;
- datos legacy sin historia suficiente;
- mensajes técnicos poco accionables;
- tests unitarios verdes sin PostgreSQL.

## Rollback lógico

- antes de una migración: revertir código conservando compatibilidad;
- después de una migración: corregir forward-only;
- no borrar cargos ni liquidaciones;
- ante datos ambiguos: bloquear y reportar;
- restaurar desde backup sólo en operación controlada;
- un fallo transaccional debe revertir cargo y snapshot juntos.

## Validación

Comandos mínimos:

```powershell
Push-Location backend
.\mvnw.cmd -Dtest=TarifaDisciplinaPostgreSqlTest,CondicionEconomicaPostgreSqlTest,CargoLiquidacionMigrationPostgreSqlTest,SchedulerIdempotencyPostgreSqlTest test
Pop-Location

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
```

Si cambia el esquema:

- verificar la siguiente versión libre;
- probar PostgreSQL vacío;
- probar upgrade desde V6;
- ejecutar reconciliación;
- conservar V1-V6 byte-identical.

## GATE-1B

- [ ] Caracterización ejecutable completa.
- [ ] Tarifa futura no afecta período anterior.
- [ ] Tarifa exacta afecta el período correspondiente.
- [ ] Condición efectiva aplica sólo desde su vigencia.
- [ ] Ausencia de tarifa falla sin fallback oculto.
- [ ] Cargo conserva snapshot aunque cambie configuración.
- [ ] Cargo y snapshot son atómicos.
- [ ] Reintentos no duplican origen, cargo ni snapshot.
- [ ] Mensualidad y matrícula no leen precios legacy.
- [ ] UI no ofrece dos fuentes de verdad.
- [ ] Exactitud monetaria e idempotencia pasan en PostgreSQL.
- [ ] Base limpia/upgrade pasan si hubo migración.
- [ ] Backend, Frontend y All quedan verdes o clasificados.
- [ ] Bitácora, estado maestro y checklist quedan actualizados.

Al cerrar GATE-1B, actualizar `main` directamente conforme a la preferencia
operativa vigente y recién después cerrar GATE-2.

<!-- GATE1B-IMPLEMENTADO-2026-07-20 -->
## Estado de ejecución — 20 de julio de 2026

| ID | Estado | Resultado |
|---|---|---|
| E1B-001 | COMPLETADO | caracterización PostgreSQL de vigencias, descuentos, errores, reintentos y cambios de tarifa |
| E1B-002 | COMPLETADO | `ResultadoLiquidacion` inmutable y `LiquidacionPorVigenciaServicio` único |
| E1B-003 | COMPLETADO | condición opcional sin alterar `vigente(...)` estricto |
| E1B-004 | COMPLETADO | mensualidad por fecha efectiva y sin fuentes legacy |
| E1B-005 | COMPLETADO | cargo + snapshot atómicos; inconsistencias fail-closed |
| E1B-006 | COMPLETADO | matrícula multidisciplina por mayor importe final; empate por menor inscripción |
| E1B-007 | COMPLETADO | alta de inscripción revierte agregado completo si falta tarifa |
| E1B-008 | COMPLETADO | API rechaza valores legacy no nulos; `recargoId` conserva semántica tardía |
| E1B-009 | COMPLETADO | UI retira edición legacy y dirige a tarifas/condiciones |
| E1B-010 | COMPLETADO | 149 backend, 142 frontend, Scope All, smoke y seed PASS |

Resultado: **GATE-1B cerrado técnicamente**. No se modificaron V1-V6, no se creó V7 y no se desplegó.
