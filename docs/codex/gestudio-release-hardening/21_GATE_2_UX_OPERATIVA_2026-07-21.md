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

Git y GitHub prevalecen; esas referencias deben actualizarse sin afirmar transporte desplegado.

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
- propuesta mínima: retirar la columna visible y construir el nombre accesible de acciones con fecha y monto;
- prueba requerida: asegurar que la tabla no expone la cabecera ni el valor del ID.

### UX-20260721-002 — búsqueda de alumnos incompleta

- roles afectados: `SECRETARIA`, `CAJA`, `ADMINISTRADOR`, `DIRECCION`, `SUPERADMIN`;
- archivo: `backend/src/main/java/gestudio/repositorios/AlumnoRepositorio.java`;
- reproducción estática: `buscarPorNombreCompleto` sólo evalúa `LOWER(CONCAT(nombre, ' ', apellido))`;
- esperado: nombre, apellido, `nombre apellido`, `apellido nombre`, documento y coincidencias parciales razonables;
- observado: documento y orden invertido no están contemplados;
- severidad: P1 para recorrido humano, porque impide localizar alumnos con criterios expresamente requeridos;
- propuesta mínima: ampliar la consulta JPQL sin cambiar el contrato HTTP ni la paginación;
- prueba requerida: PostgreSQL real para todas las variantes y exclusión de alumnos inactivos.

## 5. Limitaciones de esta ejecución

El entorno de agente no dispone de Docker, PowerShell ni conectividad Git directa. Por ello:

- no puede levantar una demo interactiva local ni realizar una inspección visual humana con navegador;
- sí puede modificar el repositorio mediante GitHub, abrir PR, usar workflows versionados como evidencia técnica y mantener GATE-2 humano en pendiente;
- no se declarará PASS de demo humana, demo comercial, staging ni producción por análisis estático o suites automatizadas.

## 6. Plan de ejecución

1. corregir primero documentación obsoleta;
2. aplicar cambios mínimos a los dos defectos reproducibles;
3. agregar pruebas frontend y PostgreSQL;
4. abrir PR draft;
5. revisar workflows, fallos y logs;
6. corregir únicamente regresiones vinculadas;
7. fusionar sólo con el mismo SHA verde y sin hilos pendientes;
8. actualizar esta bitácora con commits, PR, merge, resultados, riesgos y próximos pasos;
9. mantener recorridos humanos y GATE-2 como pendientes hasta contar con navegador y evidencia por rol.
