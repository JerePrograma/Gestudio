# GATE-2 y UX operativa — reconciliación y ejecución

> Fecha: 21 de julio de 2026  
> Zona horaria: `America/Argentina/Buenos_Aires`  
> Rama de trabajo: `agent/gate-2-ux-operativa`  
> Base exacta: `db89c3e11056e95417cc093034c821bc3dfdd015`  
> Estado al iniciar: **GATE-2 pendiente; demo comercial, staging y producción NO-GO**

## 1. Objetivo

Reconciliar el estado real de GitHub, revisar recorridos humanos y UX operativa, corregir únicamente defectos reproducibles y mantener una separación estricta entre validación técnica automatizada y aprobación humana de la demo.

## 2. Reconciliación inicial

### Git y GitHub

- repositorio verificado: `JerePrograma/Gestudio`;
- rama por defecto y operativa: `main`;
- HEAD verificado de `main`: `db89c3e11056e95417cc093034c821bc3dfdd015`;
- PR abiertos: ninguno;
- issues abiertos en Gestudio: ninguno;
- PR `#20`: fusionado mediante `7dc07d649a468934f3c099a92e5d32747cf64347`;
- último SHA funcional integral documentado: `ab830475dbd7c1d48deca7d50c1696c309679a88`;
- commits posteriores a ese SHA: observabilidad fusionada y consolidación documental hasta `db89c3e...`.

### Contradicciones documentales confirmadas

1. `docs/project-status-and-handoff.md` todavía presenta observabilidad como pendiente en PR `#20` y ordena fusionarlo como siguiente paso.
2. Ese mismo archivo afirma que `jere-platform#59` sigue bloqueando el receptor, aunque el receptor multipágina fue integrado mediante `jere-platform#60` y el issue `#59` fue cerrado.
3. `docs/codex/gestudio-release-hardening/12_ESTADO_ACTUAL_Y_BACKLOG.md` conserva el receptor multipágina como bloqueo externo y mantiene `EXT-JP-059` abierto.

Git y GitHub prevalecen; esas referencias fueron corregidas sin afirmar transporte desplegado.

## 3. Estado técnico inicial

La evidencia documental vigente declara:

- backend: 171 pruebas en el último gate integrado;
- frontend: 142 pruebas;
- lint y build: PASS;
- Scope All: PASS;
- smoke V1-V7: PASS en gates integrados;
- seed doble: PASS;
- backup/restore: 9 PASS;
- rollback: 8 PASS;
- observabilidad: 8 PASS.

Esta ejecución no considera esos conteos una revalidación del HEAD actual hasta obtener nuevos workflows verdes sobre el SHA de la rama y, después, sobre el merge de `main`.

## 4. Hallazgos reproducibles antes de modificar funcionalidad

### UX-20260721-001 — ID técnico visible en Pagos

- rol afectado: `CAJA`, `SUPERADMIN` y cualquier rol con lectura de pagos;
- archivo: `frontend/src/funcionalidades/pagos/PagosPagina.tsx`;
- reproducción estática: la tabla renderiza una columna `ID` con `pago.id` y etiqueta acciones como `Acciones del pago {id}`;
- esperado: referencias humanas; el ID interno sólo debe usarse para llamadas y diagnóstico;
- observado: el identificador técnico es la primera columna comercial;
- severidad: P2;
- corrección: se retiró la columna visible y la acción se identifica por fecha y monto;
- regresión: la prueba frontend verifica que no existan cabecera/celda de ID y que el botón tenga nombre accesible humano.

### UX-20260721-002 — búsqueda de alumnos incompleta

- roles afectados: `SECRETARIA`, `CAJA`, `ADMINISTRADOR`, `DIRECCION`, `SUPERADMIN`;
- archivo: `backend/src/main/java/gestudio/repositorios/AlumnoRepositorio.java`;
- reproducción estática: `buscarPorNombreCompleto` sólo evalúa `LOWER(CONCAT(nombre, ' ', apellido))`;
- esperado: nombre, apellido, `nombre apellido`, `apellido nombre`, documento y coincidencias parciales razonables;
- observado: documento y orden invertido no están contemplados;
- severidad: P1 para recorrido humano, porque impide localizar alumnos con criterios expresamente requeridos;
- corrección: consulta JPQL ampliada sin cambiar contrato HTTP ni paginación;
- regresión: prueba PostgreSQL para nombre, apellido, ambos órdenes, documento, fragmentos y exclusión de inactivos.

## 5. Limitaciones de esta ejecución

El entorno de agente no dispone de Docker, PowerShell ni conectividad Git directa. Por ello:

- no puede levantar una demo interactiva local ni realizar una inspección visual humana con navegador;
- sí puede modificar el repositorio mediante GitHub, abrir PR, usar workflows versionados como evidencia técnica y mantener GATE-2 humano en pendiente;
- no se declarará PASS de demo humana, demo comercial, staging ni producción por análisis estático o suites automatizadas.

## 6. Cambios publicados

Rama: `agent/gate-2-ux-operativa`.

| Commit | Alcance |
|---|---|
| `7d26640a4f52cd9f66fd4a1ffb6f8193f8173865` | reconciliación inicial antes de funcionalidad |
| `337ca4ca1f9f972e5f9abc11e1dc0711f4f9d918` | búsqueda humana de alumnos |
| `b5228ec82d42dbaccbffc20713f9af8f076c0ccf` | regresión PostgreSQL inicial |
| `b5d76213613f01711ff65d5e0706ea0f21ece6d5` | referencias humanas en Pagos |
| `36ff313b5e085259d2984b570f1587501816ad7b` | regresión frontend de Pagos |
| `a880b511017b78086fc84448880a670ecc5f667a` | handoff reconciliado |
| `7cb6c97d2cb8163539e600e5e93fdf4c088fd221` | estado/backlog unificado |
| `f6773bd2774544e7457b139872c9fd7bd05f9386` | corrección del setup transaccional de prueba |

PR draft: `#21`, `fix(gate-2): mejora búsqueda humana y referencias de pagos`.

## 7. Primer ciclo de CI y causa raíz

SHA evaluado: `7cb6c97d2cb8163539e600e5e93fdf4c088fd221`.

- `CI Gestudio` run `29833979602`: FAIL en `Verify backend`;
- `GATE-1B validation` run `29833979921`:
  - `Environment evidence`: PASS;
  - `Scope Frontend`: PASS;
  - `Scope Backend`: FAIL;
  - `Scope All`: FAIL como consecuencia del backend;
  - smoke y demo seed: omitidos por dependencia fallida.

Resultado backend: **172 pruebas ejecutadas, 171 PASS y 1 ERROR**.

### Causa raíz

La prueba nueva llamaba nuevamente a `TRUNCATE ... RESTART IDENTITY` dentro del mismo contexto `@Transactional` después de que el `@BeforeEach` había persistido y mantenía administrados 205 alumnos. PostgreSQL reinició el identificador en `1`, pero Hibernate todavía asociaba otro objeto con `Alumno#1`, produciendo:

`NonUniqueObjectException: A different object with the same identifier value was already associated with the session`.

No fue un fallo de la consulta productiva ni una regresión de búsqueda. Fue aislamiento defectuoso de la prueba.

### Corrección

Se eliminó el segundo `TRUNCATE` del método de prueba. Los alumnos sintéticos específicos se agregan después del seed general con nuevos IDs, conservando el contexto y permitiendo demostrar que el alumno inactivo queda excluido.

## 8. Estado de recorridos humanos

| Rol | Estado | Evidencia disponible |
|---|---|---|
| SUPERADMIN | PENDIENTE | sin recorrido visual completo |
| DIRECCION | PENDIENTE | sin verificación visual de menú y URL directa |
| ADMINISTRADOR | PENDIENTE | sin recorrido funcional completo |
| SECRETARIA | PENDIENTE | búsqueda corregida técnicamente; flujo alumno-inscripción-asistencia pendiente |
| CAJA | PENDIENTE | Pagos corregido técnicamente; cobro-recibo-caja-stock pendiente |

Ningún rol se marca PASS por respuesta de API o suite automatizada.

## 9. Recuperación y riesgo residual

- no se modificaron migraciones V1-V7;
- no se modificaron fórmulas financieras;
- no se modificaron infraestructura, backup, rollback u observabilidad;
- rollback de código: revertir el PR `#21`;
- datos: sin cambios de esquema ni migración;
- riesgo residual principal: la amplitud y rendimiento de la búsqueda deben permanecer verdes en PostgreSQL real y luego validarse humanamente con datos sintéticos;
- el ID interno se conserva en API y operaciones, pero deja de ser referencia comercial visible en Pagos.

## 10. Criterio pendiente para integración

1. obtener backend, frontend y Scope All verdes sobre el mismo SHA final;
2. ejecutar smoke y seed cuando las dependencias de workflow lo habiliten;
3. verificar hilos y reviews;
4. mantener PR draft mientras exista cualquier check rojo o pendiente;
5. fusionar con `expected_head_sha` sólo después de evidencia verde;
6. verificar el nuevo HEAD de `main`;
7. mantener GATE-2 humano y demo comercial en NO-GO hasta recorridos visuales completos.
