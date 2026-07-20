# Auditoría técnica de GATE-1B — liquidación financiera

> Estado: **`STATIC_REVIEW_COMPLETE / IMPLEMENTATION_PENDING`**  
> Fecha: **2026-07-20**  
> Baseline funcional auditado: `3f314ba8cc61a71bfa434a46593cd02336ec16e5`  
> Rama operativa: `main`  
> Ejecución de tests durante esta auditoría: **no disponible**

[Etapa 1B](./04_ETAPA_1B_LIQUIDACION_FINANCIERA.md) · [Decisiones](./10_DECISIONES_Y_BLOQUEOS.md) · [Estado maestro](./12_ESTADO_ACTUAL_Y_BACKLOG.md) · [Bitácora](./13_BITACORA_CONTINUIDAD.md)

## 1. Objetivo de la auditoría

Delimitar el cambio mínimo para que mensualidades y matrículas:

- resuelvan tarifa y condición por fecha efectiva;
- no lean precios legacy;
- creen cargo y snapshot en una sola transacción;
- conserven idempotencia;
- mantengan recargos tardíos como cargos separados;
- eviten una migración innecesaria.

Esta auditoría no implementa código productivo porque no se dispone en este
entorno de una copia ejecutable del repositorio, Docker ni las suites. En un
dominio financiero, publicar cambios no ejecutados sería una degradación del
gate, no progreso.

## 2. Flujo actual real

### 2.1 Alta de inscripción

`InscripcionServicio.crearInscripcion(...)`:

1. bloquea al alumno activo;
2. valida disciplina activa y duplicidad;
3. resuelve bonificación legacy;
4. persiste en `Inscripcion`:
   - `bonificacion`;
   - `costoParticular`;
5. genera la mensualidad del mes vigente;
6. genera o recupera la matrícula del año vigente.

Los tres pasos están dentro de la transacción exterior de alta. Una excepción
en mensualidad o matrícula debe revertir la inscripción, pero esto debe quedar
probado explícitamente después del cambio.

### 2.2 Mensualidad

`MensualidadServicio.generarNueva(...)`:

- selecciona bonificación desde el request o desde `Inscripcion.bonificacion`;
- conserva una regla de recargo en la mensualidad;
- calcula base desde:
  - `Inscripcion.costoParticular`, o
  - `Disciplina.valorCuota`;
- calcula descuento con la entidad `Bonificacion` mutable;
- crea cargo mediante `CargoServicio.crearParaMensualidad(...)`;
- no invoca `LiquidacionCargoServicio`.

Defecto: la existencia de `disciplina_tarifas` e
`inscripcion_condiciones_economicas` no afecta el cargo mensual.

### 2.3 Matrícula

`MatriculaServicio`:

- agrupa o consulta inscripciones activas del alumno;
- lee `Disciplina.matricula`;
- elige el máximo;
- crea cargo con vencimiento 31 de enero;
- no registra tarifa, condición ni disciplina ganadora en snapshot.

Defecto: una tarifa futura o histórica no gobierna la matrícula del año.

### 2.4 Recargos

`RecargoServicio.aplicarRecargosAutomaticos()`:

- busca cargos de mensualidad vencidos;
- lee la regla asociada a la mensualidad;
- calcula porcentaje + valor fijo sobre el importe original;
- crea un cargo separado de tipo `RECARGO`;
- usa una idempotency key por cargo origen y regla.

Conclusión: el `recargoId` de la mensualidad no representa un recargo incluido
en el cargo inicial. Es una regla para un cargo tardío separado. GATE-1B no debe
sumarlo al importe inicial ni llenar con él las columnas de recargo del snapshot
sin una decisión funcional nueva.

## 3. Componentes reutilizables

### 3.1 Tarifas

`TarifaDisciplinaRepositorio` ya expone:

`findFirstByDisciplinaIdAndVigenteDesdeLessThanEqualOrderByVigenteDesdeDesc`.

`TarifaDisciplinaServicio.vigente(...)`:

- resuelve correctamente la última tarifa `<= fecha`;
- falla si no existe historia.

Es compatible con `DEC-PRICING-001`.

### 3.2 Condiciones

`CondicionEconomicaRepositorio` expone la misma resolución como `Optional`.

`CondicionEconomicaServicio.vigente(...)` actualmente lanza
`CondicionHistoricaNoDefinidaException` cuando no encuentra una fila.

El contrato aprobado establece que la condición es opcional. Por tanto, la
resolución financiera no debe usar ese método como si la ausencia fuera error.
Alternativas válidas:

1. agregar `vigenteOpcional(...)` al servicio;
2. usar el repositorio desde el nuevo componedor si se mantiene una frontera
   clara;
3. adaptar `vigente(...)` sólo si no rompe consumidores existentes.

Recomendación: agregar un método opcional y conservar el método estricto para
los consumidores que realmente exijan historia.

### 3.3 Cargo

`CargoServicio.crearParaMensualidad(...)` y
`crearParaMatricula(...)`:

- usan locks de idempotencia;
- recuperan el cargo existente por origen;
- normalizan importe a escala 2;
- impiden importes negativos.

Deben reutilizarse. No crear otro repositorio o motor de cargo.

### 3.4 Snapshot

`LiquidacionCargoServicio.registrar(...)` ya inserta:

- cargo;
- período;
- tarifa;
- condición;
- origen;
- base;
- descuento;
- importe final;
- versión de fórmula;
- observación;
- actor opcional.

Actualmente no tiene consumidores productivos.

## 4. Capacidad del esquema V4

`cargo_liquidaciones` ya dispone de:

- `cargo_id` como PK;
- FK a tarifa;
- FK a condición;
- `origen_precio` restringido;
- importes y porcentajes;
- `formula_version`;
- observaciones;
- actor y timestamp.

Orígenes permitidos relevantes:

- `TARIFA_HISTORICA`;
- `COSTO_PARTICULAR`.

La PK evita más de un snapshot por cargo. Las FK permiten reconstruir:

- disciplina desde la tarifa elegida;
- inscripción y disciplina desde la condición elegida.

### Veredicto de esquema

**No aparece una necesidad material de V7 para GATE-1B.**

El origen ganador de una matrícula multidisciplina puede quedar determinado por
la tarifa y, cuando corresponda, la condición seleccionada. Una observación
puede registrar la política de máximo efectivo y los IDs evaluados sin crear
una nueva columna.

Crear una migración sólo se justificaría si durante la implementación se prueba
que falta una restricción o dato imprescindible. V1-V6 no se modifican.

## 5. Resultado de liquidación recomendado

Crear un resultado inmutable, por ejemplo `ResultadoLiquidacion`, con:

- `LocalDate fechaEfectiva`;
- `TarifaDisciplina tarifa`;
- `CondicionEconomicaInscripcion condicion` nullable;
- `OrigenPrecio origenPrecio` o código validado;
- `BigDecimal importeBase` escala 2;
- `BigDecimal descuentoPorcentaje` escala 4;
- `BigDecimal descuentoImporte` escala 2;
- `BigDecimal importeFinal` escala 2;
- `int formulaVersion` igual a 1;
- `String observaciones`.

No introducir una jerarquía extensa ni un motor de reglas configurable.

## 6. Fórmula exacta

### 6.1 Base

```text
si condición efectiva existe y costoParticular != null:
    base = costoParticular
    origen = COSTO_PARTICULAR
si no:
    base = tarifa efectiva del tipo solicitado
    origen = TARIFA_HISTORICA
```

Para mensualidad, el valor de tarifa es `valorCuota`.

Para matrícula, el valor de tarifa es `matricula`.

### 6.2 Descuento

```text
porcentaje = condición ausente ? 0 : snapshot porcentaje
fijo       = condición ausente ? 0 : snapshot valor fijo
porcentajeImporte = base * porcentaje / 100, escala 2 HALF_UP
descuentoImporte  = porcentajeImporte + fijo, escala 2 HALF_UP
final              = base - descuentoImporte, escala 2 HALF_UP
```

Reglas:

- si `final < 0`, abortar;
- no leer la entidad `Bonificacion` actual;
- no combinar condición efectiva con `Inscripcion.bonificacion`;
- no aplicar recargo tardío en esta fórmula;
- todos los valores persistidos deben respetar la escala del esquema.

## 7. Fecha efectiva

| Origen | Fecha efectiva |
|---|---|
| Mensualidad | `YearMonth.of(anio, mes).atDay(1)` |
| Matrícula | `LocalDate.of(anio, 1, 1)` |

No usar:

- fecha de ejecución;
- fecha de vencimiento;
- fecha de alta de la inscripción;
- `LocalDate.now(clock)` para elegir precio.

`Clock` permanece para fecha de emisión/generación y scheduler, no para resolver
la historia del período solicitado.

## 8. Política de matrícula multidisciplina

Para cada inscripción activa del alumno:

1. obtener tarifa efectiva de su disciplina al 1 de enero;
2. obtener condición efectiva opcional de esa inscripción;
3. liquidar la matrícula individual;
4. elegir el mayor `importeFinal`;
5. persistir en el snapshot la tarifa y condición del resultado ganador.

Desempate recomendado:

- menor ID de inscripción o disciplina para determinismo;
- registrar el criterio en observaciones;
- no depender del orden de la colección JPA.

Caso sin inscripciones activas:

- rechazar la generación; no emitir matrícula cero silenciosa.

Caso con una disciplina sin tarifa:

- conforme al contrato estricto, abortar el proceso del alumno; no ignorar la
  disciplina faltante para elegir otra más barata o más cara.

## 9. Compatibilidad de API

### 9.1 `bonificacionId` de mensualidad

El request manual acepta `bonificacionId`, pero la nueva autoridad será la
condición económica efectiva.

No puede seguir alterando el importe sin violar el contrato. Opciones:

- rechazar un valor no nulo con mensaje deprecado;
- retirarlo del contrato frontend/backend en un cambio coordinado;
- conservarlo sólo para compatibilidad de deserialización, sin cálculo.

Recomendación: durante GATE-1B, rechazarlo explícitamente si llega informado y
actualizar consumidores. Ignorarlo silenciosamente ocultaría una pérdida de
intención.

### 9.2 `recargoId` de mensualidad

Puede conservarse porque selecciona la regla de recargo tardío. Debe aclararse
en DTO/UI que no modifica el importe inicial.

### 9.3 Actor

Los controladores actuales no pasan `Usuario` a mensualidad o matrícula.
`calculada_por_usuario_id` admite null y el scheduler no tiene actor humano.

No bloquear GATE-1B por esto. Una mejora posterior puede inyectar el principal
en operaciones manuales, conservando null para jobs.

## 10. Atomicidad e idempotencia

### Riesgo principal

El patrón actual crea el origen, llama a `CargoServicio` y retornaría sin
snapshot. El nuevo flujo debe:

1. resolver liquidación antes de persistir;
2. crear origen;
3. crear o recuperar cargo;
4. registrar snapshot sólo si no existe;
5. terminar dentro de la misma transacción.

### Reintento

Si origen y cargo ya existen:

- devolverlos;
- verificar que existe snapshot;
- no recalcular con configuración nueva;
- si falta snapshot, tratarlo como inconsistencia, no crear uno usando precios
  actuales sin reconciliación.

Esto evita que un retry posterior a un cambio de tarifa altere historia.

### Concurrencia

Probar dos ejecuciones simultáneas para:

- misma inscripción/período;
- mismo alumno/año;
- creación desde alta de inscripción y scheduler cuando corresponda.

La expectativa es una fila de origen, un cargo y un snapshot.

## 11. Archivos productivos afectados

### Backend obligatorio

- `backend/src/main/java/gestudio/servicios/mensualidad/MensualidadServicio.java`
- `backend/src/main/java/gestudio/servicios/matricula/MatriculaServicio.java`
- `backend/src/main/java/gestudio/servicios/inscripcion/InscripcionServicio.java`
- `backend/src/main/java/gestudio/tarifas/application/TarifaDisciplinaServicio.java`
- `backend/src/main/java/gestudio/tarifas/application/CondicionEconomicaServicio.java`
- `backend/src/main/java/gestudio/cuotas/application/LiquidacionCargoServicio.java`
- un nuevo resultado/componedor bajo `gestudio.cuotas.application` o paquete
  financiero existente;
- DTO/controlador mensual sólo para resolver compatibilidad de bonificación.

### Backend que debe reutilizarse, no reescribirse

- `CargoServicio`;
- `CargoRepositorio`;
- `IdempotencyLockService`;
- repositorios de tarifa y condición;
- entidades y tabla `cargo_liquidaciones`.

### Frontend obligatorio

- `frontend/src/funcionalidades/inscripciones/InscripcionesFormulario.tsx`
- `frontend/src/validaciones/inscripcionEsquema.tsx`
- DTOs en `frontend/src/types/types.ts`;
- formularios de disciplina que editan `valorCuota` y `matricula`;
- pantallas canónicas de tarifas y condiciones;
- cualquier formulario manual de mensualidad que exponga bonificación/recargo.

Objetivo UI:

- alta/edición de inscripción no modifica precio o bonificación legacy;
- disciplina no presenta los campos legacy como fuente operativa;
- tarifas y condiciones son la única superficie financiera efectiva;
- la regla de recargo tardío queda diferenciada del precio inicial.

## 12. Tests mínimos nuevos o modificados

### Caracterización

Crear una suite PostgreSQL específica, recomendada:

`LiquidacionPorVigenciaPostgreSqlTest`.

Debe cubrir:

- tarifa anterior/exacta/futura;
- condición ausente/anterior/exacta/futura;
- costo particular;
- porcentaje, fijo y combinación;
- descuento superior a base;
- escala y redondeo;
- snapshot exacto.

### Mensualidad

Crear o ampliar tests para:

- manual y scheduler;
- período pasado/actual/futuro;
- retry posterior a cambio de tarifa;
- rollback si falla snapshot;
- ausencia de tarifa;
- rechazo de bonificación ad hoc.

### Matrícula

Cubrir:

- cero, una y varias disciplinas;
- máximo por importe final, no por base;
- desempate determinista;
- una disciplina sin tarifa;
- retry y concurrencia;
- snapshot del origen ganador.

### Suites existentes a adaptar

- `TarifaDisciplinaPostgreSqlTest`;
- `CondicionEconomicaPostgreSqlTest`;
- `CargoLiquidacionMigrationPostgreSqlTest`;
- `SchedulerIdempotencyPostgreSqlTest`;
- tests de alta de inscripción;
- tests frontend de inscripciones y disciplinas.

`SchedulerIdempotencyPostgreSqlTest` hoy crea sólo precios legacy. Después del
cambio debe insertar tarifas/condiciones efectivas para no pasar por accidente.

## 13. Orden de implementación recomendado

1. agregar tests de caracterización;
2. crear resultado y componedor puro;
3. resolver condición opcional;
4. integrar mensualidad;
5. probar snapshot e idempotencia;
6. integrar matrícula;
7. probar máximo y determinismo;
8. adaptar alta de inscripción;
9. retirar DTO/UI legacy;
10. ejecutar suites focalizadas;
11. ejecutar Backend, Frontend y All;
12. registrar evidencia y cerrar GATE-1B.

## 14. Riesgos concretos

### Bloqueantes

- recalcular snapshot existente con configuración actual;
- permitir bonificación ad hoc paralela;
- emitir matrícula cero sin inscripciones;
- omitir una disciplina sin tarifa;
- persistir cargo sin snapshot.

### Altos

- usar `CondicionEconomicaServicio.vigente()` y convertir ausencia opcional en
  fallo;
- elegir máximo por base en vez de total descontado;
- desempate no determinista;
- scheduler y API con fórmulas distintas;
- quitar recargo tardío por confundirlo con precio inicial.

### Medios

- actor null en operaciones manuales;
- mensajes sin disciplina/fecha;
- observaciones insuficientes;
- UI legacy visible durante transición.

## 15. Veredicto

El cambio es acotado pero crítico. El esquema, los repositorios y la
idempotencia de cargos ya ofrecen la base necesaria. El trabajo real está en la
orquestación y en retirar las fuentes legacy.

**Veredicto provisional:** implementar sin V7, comenzar por caracterización y no
publicar cambios financieros hasta ejecutar PostgreSQL, backend, frontend y el
gate integrado.

<!-- GATE1B-AUDITORIA-CORREGIDA-2026-07-20 -->
## Correcciones demostradas por implementación y pruebas

- la auditoría confirmó correctamente que `cargo_liquidaciones` era suficiente; no se necesitó V7;
- `CondicionEconomicaServicio.vigente(...)` conserva su contrato estricto y se agregó `vigenteOpcional(...)`;
- mensualidad y matrícula comparten una única composición financiera;
- los snapshots se crean dentro de la misma transacción que origen y cargo;
- un cargo existente sin snapshot no se reconstruye tardíamente;
- un fallo inducido de snapshot revierte cargo y origen;
- un fallo inducido de cargo no deja snapshot;
- el reintento no toma una tarifa creada después del cargo original;
- matrícula compara importes finales y desempata por menor ID de inscripción;
- `Disciplina.valorCuota`, `Disciplina.matricula`, `Inscripcion.costoParticular` y `Inscripcion.bonificacion` dejaron de ser fuentes financieras;
- `bonificacionId`/`costoParticular` legacy se rechazan explícitamente en API y se retiraron de UI;
- V1-V6 permanecen byte-identical dentro del alcance del PR.
