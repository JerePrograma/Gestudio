# GATE-2 y UX operativa — ejecución del 21 de julio de 2026

> Zona horaria: `America/Argentina/Buenos_Aires`  
> Base inicial: `db89c3e11056e95417cc093034c821bc3dfdd015`  
> SHA candidato validado: `52175e49b03a2fc7b4e1c729a0f8a4a7f1c30113`  
> PR funcional: `#21`  
> Merge funcional: `7d8872a59acb923fae664f806b01e459f372dc1c`  
> Resultado del corte histórico: correcciones técnicas integradas; el recorrido
> humano no se ejecutó ese día y fue cerrado el 2026-07-22 según el informe 23.

## 1. Alcance ejecutado

- reconciliación de `main`, PR, issues, commits y documentación;
- revisión estática de recorridos y superficies UX prioritarias;
- corrección mínima de dos defectos reproducibles;
- pruebas PostgreSQL y frontend;
- ejecución de backend, frontend, Scope All, Compose, imágenes, smoke y seed doble;
- documentación de causa raíz, recuperación, riesgos y backlog;
- integración mediante PR con protección contra movimiento de HEAD.

No se desplegó staging ni producción. No se activó el emisor Jere Platform. No se modificaron migraciones V1-V7, fórmulas financieras, infraestructura, recuperación ni observabilidad.

## 2. Reconciliación inicial

- repositorio: `JerePrograma/Gestudio`;
- rama operativa: `main`;
- HEAD inicial: `db89c3e11056e95417cc093034c821bc3dfdd015`;
- PR abiertos al iniciar: ninguno;
- issues abiertos en Gestudio al iniciar: ninguno;
- PR `#20`: fusionado mediante `7dc07d649a468934f3c099a92e5d32747cf64347`;
- receptor multipágina Jere Platform: integrado mediante PR `#60`;
- `jere-platform#59`: cerrado;
- `jere-platform#51`: abierto;
- transporte desplegado Gestudio → Jere Platform: no demostrado.

Contradicciones corregidas:

- observabilidad ya no figura como PR pendiente;
- `jere-platform#59` ya no figura como bloqueo abierto;
- emisor/receptor en código no se presentan como transporte operativo.

## 3. Defectos reproducidos

### UX-20260721-001 — ID técnico visible en Pagos

- archivo: `frontend/src/funcionalidades/pagos/PagosPagina.tsx`;
- observado: columna `ID`, valor `pago.id` y etiqueta de acciones basada en ese ID;
- esperado: fecha, monto, estado y referencia humana;
- roles afectados: principalmente `CAJA` y `SUPERADMIN`;
- severidad: P2.

### UX-20260721-002 — búsqueda de alumnos incompleta

- archivo: `backend/src/main/java/gestudio/repositorios/AlumnoRepositorio.java`;
- observado: sólo coincidía `nombre apellido`;
- esperado: nombre, apellido, ambos órdenes, documento y parciales;
- roles afectados: los cinco roles operativos;
- severidad: P1 para recorrido humano.

## 4. Correcciones

### Pagos

- se retiró el ID técnico de la tabla visible;
- el botón de acciones se nombra con fecha y monto;
- el ID permanece en memoria y llamadas API para trazabilidad;
- se actualizó la ayuda de búsqueda por alumno.

### Alumnos

La consulta JPQL ahora busca, únicamente entre alumnos activos, por:

- nombre;
- apellido;
- nombre y apellido;
- apellido y nombre;
- documento;
- coincidencias parciales case-insensitive.

No se cambió el endpoint, la paginación ni el modelo de datos.

## 5. Pruebas agregadas

### PostgreSQL

`CanonicalPaginationPostgreSqlTest` cubre:

- nombre;
- apellido;
- ambos órdenes;
- documento completo;
- documento parcial;
- fragmento de nombre/apellido;
- exclusión de alumno inactivo;
- preservación de paginación y seguridad existentes.

### Frontend

`PagosPagina.test.tsx` verifica:

- búsqueda y selección sin ingresar ID interno;
- ausencia de cabecera `ID`;
- ausencia de celda con el ID del pago;
- monto ARS visible;
- acción con nombre accesible basado en fecha y monto.

## 6. Primer ciclo CI fallido

SHA: `7cb6c97d2cb8163539e600e5e93fdf4c088fd221`.

- `CI Gestudio` run `29833979602`: FAIL en backend;
- `GATE-1B validation` run `29833979921`:
  - frontend: PASS;
  - backend: FAIL;
  - Scope All: FAIL derivado;
  - smoke y seed: omitidos.

Resultado backend: 172 ejecutadas, 171 PASS y 1 ERROR.

### Causa raíz

La prueba nueva ejecutaba un segundo `TRUNCATE ... RESTART IDENTITY` dentro del mismo contexto `@Transactional` después del seed de `@BeforeEach`. Hibernate todavía administraba `Alumno#1`; PostgreSQL reutilizó el identificador `1` y produjo `NonUniqueObjectException`.

No falló la consulta productiva. Falló el aislamiento de la prueba.

### Corrección de CI

Commit `f6773bd2774544e7457b139872c9fd7bd05f9386`:

- se eliminó el segundo truncate;
- los casos específicos se agregan después del seed general;
- se conserva la prueba de exclusión de inactivos.

## 7. Evidencia final verde

SHA exacto: `52175e49b03a2fc7b4e1c729a0f8a4a7f1c30113`.

### `GATE-1B validation` — run `29834533348`

| Job | Resultado |
|---|---|
| Environment evidence | PASS |
| Scope Backend | **172/172 PASS** |
| Scope Frontend | **142/142 PASS** |
| lint | PASS |
| build frontend | PASS |
| Scope All | PASS |
| Smoke local | PASS |
| Demo seed doble | PASS |

### `CI Gestudio` — run `29834533617`

| Job | Resultado |
|---|---|
| Validate backend/frontend | PASS |
| Compose local | PASS |
| Compose productivo | PASS |
| Backend image | PASS |
| Frontend image | PASS |
| Smoke aislado | PASS |

Hilos de review pendientes: ninguno.

## 8. Git e integración

Rama funcional: `agent/gate-2-ux-operativa`.

Commits principales:

- `7d26640a...`: reconciliación inicial;
- `337ca4ca...`: búsqueda humana;
- `b5228ec8...`: prueba PostgreSQL;
- `b5d76213...`: Pagos sin ID visible;
- `36ff313b...`: prueba frontend;
- `a880b511...`: handoff reconciliado;
- `7cb6c97d...`: estado unificado;
- `f6773bd2...`: corrección del test;
- `52175e49...`: bitácora de fallos y causa raíz.

PR `#21`:

- abierto como draft;
- mantenido draft durante checks pendientes/rojos;
- marcado ready sólo con ambos workflows verdes;
- fusionado con `expected_head_sha=52175e49...`;
- merge: `7d8872a59acb923fae664f806b01e459f372dc1c`.

## 9. Seguimiento de recorridos humanos

| Rol | Estado | Motivo |
|---|---|---|
| SUPERADMIN | PASS 2026-07-22 | navegador, reporte con datos, usuarios y roles |
| DIRECCION | PASS 2026-07-22 | menú, URL directa y denegación de roles |
| ADMINISTRADOR | PASS 2026-07-22 | recorrido funcional y denegación de roles |
| SECRETARIA | PASS 2026-07-22 | alumnos, inscripción, asistencia, pagos, caja y reporte |
| CAJA | PASS 2026-07-22 | pagos, caja, stock, lectura y denegaciones académicas |

El PASS posterior proviene de navegador headed real; no se infiere desde API,
análisis estático o suites.

## 10. Recuperación

- no hay migraciones ni cambios de datos;
- revert funcional: revertir merge `7d8872a59...`;
- backup/restore no es necesario para esta entrega;
- siguen vigentes los runbooks canónicos;
- V1-V7 permanecen intactas.

## 11. Límites registrados

- IDs técnicos pueden persistir en módulos ajenos al guion;
- el recorrido cubrió teclado/foco básico y 390/escritorio, no una auditoría WCAG completa;
- búsqueda ampliada puede requerir índices con volúmenes mayores;
- staging no existe;
- producción no está autorizada;
- transporte Jere Platform no está desplegado.

## 12. Veredicto

| Superficie | Veredicto |
|---|---|
| Desarrollo local | GO |
| Validación técnica | GO |
| Demo automatizada | GO |
| Demo humana | GO / PASS 2026-07-22 |
| Demo comercial | NO-GO |
| Staging | NO-GO / NO PROVISTO |
| Producción | NO-GO / NO AUTORIZADA |
