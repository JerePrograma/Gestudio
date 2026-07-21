# Estado actual y backlog unificado

> Fecha de corte: 21 de julio de 2026  
> Zona horaria: `America/Argentina/Buenos_Aires`  
> Rama operativa: `main`  
> Merge funcional GATE-2: `7d8872a59acb923fae664f806b01e459f372dc1c`  
> Estado global: **NO-GO para demo humana, demo comercial, staging y producción**

Git y GitHub son la autoridad. La evidencia detallada de esta iteración está en `21_GATE_2_UX_OPERATIVA_2026-07-21.md`.

## 1. Resumen ejecutivo

Integrado y técnicamente validado:

- seguridad y RBAC fail-closed con 32 permisos;
- roles `SUPERADMIN`, `DIRECCION`, `ADMINISTRADOR`, `SECRETARIA` y `CAJA`;
- `PROFESOR` inactivo y no asignable;
- finanzas por vigencia, snapshots atómicos e idempotencia;
- Flyway V1-V7 forward-only e inmutables;
- demo automatizada y seed idempotente;
- backup, restore aislado y rollback forward-compatible;
- observabilidad source-owned integrada mediante PR `#20`;
- emisor `GESTUDIO_STUDENT` apagado por defecto;
- receptor multipágina de Jere Platform integrado mediante PR `#60`;
- búsqueda de alumnos por nombre, apellido, ambos órdenes, documento y coincidencias parciales;
- eliminación del ID técnico como referencia comercial visible en la tabla de Pagos.

Continúan abiertos:

- recorridos humanos completos de los cinco roles;
- revisión UX exhaustiva de todos los módulos;
- accesibilidad y responsive con evidencia visual;
- transporte desplegado Gestudio → Jere Platform;
- monitoreo, dashboards, alertas y retención externos;
- políticas reales de backup, artefactos y secretos;
- staging y producción.

## 2. Estado de gates

| Gate o capacidad | Estado | Evidencia |
|---|---|---|
| GATE-0 — baseline | CERRADO | scripts, Docker, CI y documentación |
| GATE-1 — seguridad/RBAC | CERRADO | 401/403/409 y matriz fail-closed |
| GATE-1B — liquidación por vigencia | CERRADO TÉCNICAMENTE | PostgreSQL real y snapshot atómico |
| Flyway V1-V7 | CERRADO | smoke, seed, restore y rollback |
| Demo automatizada | PASS | smoke y seed doble sobre SHA candidato |
| Correcciones técnicas GATE-2 | INTEGRADAS | PR `#21`, merge `7d8872a59...` |
| Demo humana por rol | PENDIENTE | no existe evidencia visual completa |
| GATE-2 humano/UX exhaustivo | ABIERTO | recorridos, accesibilidad y móvil pendientes |
| Integración source Jere Platform | INTEGRADA | emisor y receptor presentes, emisor apagado |
| Transporte Jere Platform | NO DEMOSTRADO | sin despliegue ni smoke end-to-end |
| Backup/restore/rollback | PASS TÉCNICO | drills permanentes |
| Observabilidad source-owned | PASS TÉCNICO | health, métricas, request ID y logs |
| Monitoreo externo | BLOCKED | ambiente y responsables no provistos |
| Staging | NO-GO | ambiente inexistente |
| Producción | NO-GO | no autorizada |

## 3. Reconciliación GitHub

Estado inicial verificado:

- `main`: `db89c3e11056e95417cc093034c821bc3dfdd015`;
- PR abiertos: ninguno;
- issues abiertos en Gestudio: ninguno;
- PR `#20`: fusionado;
- `jere-platform#59`: cerrado;
- receptor Jere Platform: integrado mediante PR `#60`;
- coordinador `jere-platform#51`: abierto.

Trabajo integrado:

- PR `#21`: `fix(gate-2): mejora búsqueda humana y referencias de pagos`;
- SHA candidato exacto: `52175e49b03a2fc7b4e1c729a0f8a4a7f1c30113`;
- merge protegido contra movimiento de HEAD: `7d8872a59acb923fae664f806b01e459f372dc1c`;
- hilos de review pendientes: ninguno.

## 4. Defectos encontrados y corregidos

### UX-20260721-001 — ID técnico visible en Pagos

- observado: la primera columna mostraba `pago.id` y las acciones se identificaban por ese ID;
- esperado: referencias comprensibles para Caja y operación comercial;
- corrección: se retiró la columna y el nombre accesible usa fecha y monto;
- trazabilidad: el ID se conserva internamente para API y operaciones;
- prueba: ausencia de cabecera/celda ID y presencia del nombre accesible humano;
- estado: **INTEGRADO**.

### UX-20260721-002 — búsqueda de alumnos incompleta

- observado: sólo coincidía `nombre apellido`;
- esperado: nombre, apellido, ambos órdenes, documento y parciales;
- corrección: JPQL ampliado manteniendo contrato HTTP, alumnos activos y paginación;
- prueba: PostgreSQL real con todas las variantes y exclusión del alumno inactivo;
- estado: **INTEGRADO**.

### CI-20260721-001 — colisión de identidad en prueba nueva

- síntoma: `NonUniqueObjectException` para `Alumno#1`;
- causa: segundo `TRUNCATE ... RESTART IDENTITY` dentro de la misma sesión transaccional;
- impacto: 172 pruebas ejecutadas, 171 PASS y 1 ERROR en el primer ciclo;
- corrección: eliminar el segundo truncate y agregar datos específicos después del seed general;
- lógica productiva afectada: ninguna;
- estado: **CORREGIDO Y REVALIDADO**.

## 5. Evidencia final del SHA candidato

SHA: `52175e49b03a2fc7b4e1c729a0f8a4a7f1c30113`.

### `GATE-1B validation` run `29834533348`

- Environment evidence: PASS;
- Scope Backend: **172/172 PASS**;
- Scope Frontend: **142/142 PASS**;
- frontend lint: PASS;
- frontend build: PASS;
- Scope All: PASS;
- Smoke local V1-V7: PASS;
- Demo seed doble: PASS;
- recursos Docker residuales: control ejecutado.

### `CI Gestudio` run `29834533617`

- backend: PASS;
- frontend: PASS;
- Compose local: PASS;
- Compose productivo: PASS con secretos sintéticos de CI;
- imagen backend: PASS;
- imagen frontend: PASS;
- smoke aislado: PASS.

No se modificaron infraestructura, recuperación u observabilidad; por eso no correspondía repetir los drills específicos de backup/restore, rollback u observabilidad.

## 6. Recorridos humanos por rol

| Rol | Estado | Alcance pendiente |
|---|---|---|
| SUPERADMIN | PENDIENTE | gobierno, operación completa, denegaciones y vista móvil |
| DIRECCION | PENDIENTE | menú, reportes, finanzas y accesos directos prohibidos |
| ADMINISTRADOR | PENDIENTE | operación amplia sin gobierno de roles |
| SECRETARIA | PENDIENTE | alumno, inscripción, asistencia, estados y responsive |
| CAJA | PENDIENTE | cargos, pagos, recibos, caja, egresos, stock y reversión |

No se marca ningún rol PASS porque esta ejecución no dispuso de navegador operativo ni evidencia humana visual.

## 7. Matriz UX pendiente

| Área | Estado técnico | Validación humana pendiente |
|---|---|---|
| Login y RBAC | automatizado | mensajes, foco, teclado y móvil |
| Alumnos | búsqueda corregida | resultados, vacíos, errores y responsive |
| Inscripciones | sin cambio | recorrido completo |
| Tarifas/condiciones | sin regresión conocida | comprensión y navegación |
| Mensualidades/matrículas/cargos | fórmulas cerradas | explicación del origen y operación humana |
| Pagos/recibos | ID corregido | parciales, aplicaciones, anulación y descarga |
| Caja/egresos | automatizado parcialmente | referencias, confirmaciones y reversión |
| Stock/ventas | automatizado parcialmente | stock negativo, caja y movimientos |
| Asistencia | sin cambio | selección, marcado, guardado y estados |
| Reportes | permisos automatizados | utilidad y legibilidad |
| Accesibilidad | no cerrada | foco, orden, labels, contraste, modales y errores |
| Móvil | no cerrada | 360, 390, 768 y escritorio |

## 8. Recuperación

Los cambios integrados no alteran datos ni esquema:

- migraciones V1-V7 intactas;
- sin down migrations;
- sin cambios de fórmulas financieras;
- sin cambios de backup, restore, rollback u observabilidad;
- recuperación de código: revertir el merge `7d8872a59...`;
- recuperación de datos: no requerida para esta entrega.

## 9. Backlog priorizado

### P1 — demo humana y UX

1. ejecutar `SUPERADMIN` completo;
2. ejecutar `DIRECCION` y validar denegaciones directas;
3. ejecutar `ADMINISTRADOR`;
4. ejecutar `SECRETARIA` con alumno → inscripción → asistencia;
5. ejecutar `CAJA` con cargo → pago → recibo → caja → stock/reversión;
6. probar loading, vacío, error, éxito y doble envío;
7. probar teclado, foco, labels, modales y contraste;
8. probar 360, 390, 768 y escritorio;
9. registrar capturas o video y SHA exacto.

### P1 — operación externa

1. definir destino, cifrado, retención, RPO/RTO y responsables de backup;
2. definir registry, digest, firma, promoción y retención de imágenes;
3. definir secret manager y rotación;
4. proveer Prometheus, storage, dashboard, alertas y responsables;
5. proveer staging con dominio, TLS, CORS y cookies;
6. desplegar y probar transporte Gestudio → Jere Platform sólo con autorización.

## 10. Riesgos

- CI verde no demuestra usabilidad humana;
- pueden quedar IDs o referencias técnicas en módulos no recorridos visualmente;
- búsquedas amplias pueden necesitar índices si el volumen real crece;
- accesibilidad y responsive siguen sin evidencia exhaustiva;
- staging no existe;
- producción no está autorizada;
- integración Jere Platform sigue siendo source-only.

## 11. Veredictos

| Superficie | Veredicto |
|---|---|
| Desarrollo local | **GO** con requisitos y scripts versionados |
| Validación técnica | **GO** sobre el SHA integrado |
| Demo automatizada | **GO** |
| Demo humana | **NO-GO / PENDIENTE** |
| Demo comercial | **NO-GO** |
| Staging | **NO-GO / NO PROVISTO** |
| Producción | **NO-GO / NO AUTORIZADA** |
