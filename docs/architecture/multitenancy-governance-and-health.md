# Gobierno, estado y health del multitenancy

> **Documento normativo vivo**  
> Estado técnico local: `EXECUTED_PASS`
> Rama de referencia: `main`  
> Última revisión estructural: 2026-08-04
> Repositorio: `JerePrograma/Gestudio`

## 1. Propósito

Este documento es la fuente de verdad operativa para diseñar, implementar, verificar y mantener el multitenancy de Gestudio.

Debe cumplir simultáneamente estas funciones:

- describir el estado real, sin confundir integración externa con aislamiento multitenant;
- fijar invariantes de seguridad y datos;
- registrar decisiones, riesgos, deuda y bloqueos;
- ordenar el desarrollo por fases verificables;
- impedir que una implementación parcial sea declarada completa;
- definir health checks, métricas, pruebas y gates de release;
- servir como contrato de trabajo para Codex y futuros mantenedores;
- autoactualizarse en cada cambio que afecte tenancy.

Una modificación de código relacionada con tenants que no actualice este documento se considera incompleta.

## 2. Veredicto actual

La implementación shared-schema está integrada localmente: control plane,
memberships, contexto, claims ligados a tenant/membership, backfill, claves
compuestas, RLS forzado, jobs, archivos, integración Jere y selector frontend.
La identidad inicial consulta sólo `usuarios`; roles y permisos se cargan
después de abrir el tenant. Runtime y Flyway usan roles PostgreSQL separados.

El cierre técnico local está en `EXECUTED_PASS`: PostgreSQL 15 real validó
V1-V11, V7-V11, Hibernate, RLS con rol runtime no propietario y reutilización
de conexión; `clean verify` pasó 282 tests y el frontend pasó 166 tests, lint y
build. Esto no equivale todavía a la certificación absoluta de la sección 18:
backup/restore multitenant y publicación siguen separados. La demo estable
sigue en V7 y quedó fuera de estas pruebas.

El `tenantId` histórico de `integraciones/jereplatform` continúa siendo una
identidad externa. La autoridad interna es el UUID de `Tenant` resuelto desde
una membership; ambos identificadores se conservan separados.

## 3. Baseline histórica auditada en `main`

SHA observado al crear este documento:

`ec5cee0773baa2b8c50f2b5c6768e424e08c7efe`

La siguiente tabla describe el baseline anterior a V8, no el código actual:

| Área | Estado observado | Conclusión |
|---|---|---|
| Visión del producto | Una academia por deployment | Monoacademia explícita |
| Integración Jere Platform | `organizationId` y `tenantId` por variables de entorno | Mapping externo, no tenant interno |
| `SourceTenantMapping` | Lee configuración global y falla cerrado | No existe resolución por sesión/request |
| Exportación de estudiantes | Persiste tenant externo en snapshots | Aislamiento limitado al artefacto de integración |
| Modelo persistente general | Sin evidencia de discriminator tenant global | No existe aislamiento de dominio |
| Seguridad | RBAC funcional global | No hay autorización tenant-scoped |
| Frontend | Sin selector/contexto de organización | No existe UX multitenant |
| Operación | Backups, jobs y métricas globales | No existe segregación operativa por tenant |

### 3.1 Archivos que no deben interpretarse incorrectamente

- `backend/src/main/java/gestudio/integraciones/jereplatform/application/SourceTenantMapping.java`
- `backend/src/main/java/gestudio/integraciones/jereplatform/application/StudentSourceExportService.java`
- `backend/src/main/java/gestudio/integraciones/jereplatform/application/StudentSourceExport.java`
- `backend/src/main/java/gestudio/integraciones/jereplatform/infrastructure/StudentSourceExportProperties.java`
- `backend/src/main/resources/db/migration/V7__jere_platform_student_source_exports.sql`
- `docs/integrations/jere-platform-student-export-v1.md`

Estos componentes sólo implementan identificación del tenant receptor en una integración externa.

## 4. Definición de terminado

El multitenancy sólo podrá marcarse `IMPLEMENTED_AND_CERTIFIED` cuando se demuestre todo lo siguiente:

1. Toda entidad tenant-owned posee tenant explícito e inmutable.
2. Toda lectura, escritura, búsqueda, conteo, reporte y exportación queda acotada al tenant efectivo.
3. Ningún identificador proporcionado por el cliente puede cambiar el tenant efectivo.
4. La pertenencia usuario-tenant y los permisos se validan en backend.
5. JWT, refresh, logout y revocación mantienen coherencia tenant-aware.
6. Los constraints e índices impiden colisiones y referencias cruzadas.
7. Los jobs y procesos asíncronos restauran explícitamente su contexto tenant.
8. Auditoría, logs y métricas permiten atribución sin filtrar PII.
9. Backups y restores conservan aislamiento y ofrecen procedimientos probados.
10. Existen pruebas negativas sistemáticas de fuga entre al menos dos tenants.
11. Los datos actuales fueron migrados de manera reversible y verificada a un tenant inicial.
12. Frontend y API no permiten operar con un tenant no autorizado.
13. Todos los gates de este documento pasan sobre el SHA publicado en `origin/main`.

## 5. Modelo objetivo obligatorio

### 5.1 Estrategia inicial

La estrategia recomendada para el monolito actual es:

`shared database + shared schema + tenant_id discriminator`

Razones:

- minimiza cambios operativos respecto de la arquitectura existente;
- conserva Flyway, JPA y PostgreSQL actuales;
- permite una migración incremental;
- evita multiplicar bases, conexiones y despliegues;
- puede reforzarse con PostgreSQL Row Level Security.

No introducir schema-per-tenant ni database-per-tenant sin ADR y evidencia que justifique el costo operacional.

### 5.2 Entidades de control mínimas

Deben existir equivalentes coherentes con el dominio real:

- `Tenant` o `Organization`;
- `TenantMembership` para usuario, tenant, estado y rol(es);
- configuración tenant-owned sólo cuando sea realmente variable;
- estado de lifecycle: `ACTIVE`, `SUSPENDED`, `ARCHIVED` como mínimo.

No inventar nombres definitivos antes de inspeccionar las convenciones existentes.

### 5.3 Resolución de tenant

El tenant efectivo debe provenir exclusivamente de identidad autenticada y pertenencia validada.

Flujo requerido:

1. autenticar usuario;
2. determinar memberships activas;
3. seleccionar tenant autorizado mediante mecanismo explícito;
4. emitir o renovar credencial ligada al tenant seleccionado;
5. validar membership y estado del tenant en cada request sensible;
6. establecer `TenantContext` antes de acceder a datos;
7. limpiar el contexto siempre al finalizar request o tarea.

Headers como `X-Tenant-Id` pueden transportar una selección, pero nunca son autoridad suficiente. Deben cotejarse contra la identidad autenticada.

### 5.4 Defensa en profundidad

La protección mínima debe combinar:

- autorización de aplicación;
- filtros obligatorios en persistencia;
- constraints y claves compuestas;
- pruebas de aislamiento;
- preferentemente PostgreSQL RLS para tablas tenant-owned críticas.

Hibernate filters o interceptores por sí solos no son una frontera suficiente: una consulta nativa, un job o un repositorio nuevo podrían omitirlos.

## 6. Clasificación obligatoria de datos

Antes de migrar, cada tabla y agregado debe clasificarse:

| Clase | Significado | Tratamiento |
|---|---|---|
| `GLOBAL` | Catálogo realmente compartido | Sin `tenant_id`, acceso explícito |
| `TENANT_OWNED` | Pertenece a una academia | `tenant_id NOT NULL` y aislamiento completo |
| `TENANT_SCOPED_REFERENCE` | Referencia compartida con configuración por tenant | Tabla puente tenant-aware |
| `SECURITY_GLOBAL` | Identidad global | Membership separada y autorización tenant-aware |
| `OPERATIONAL` | Jobs, outbox, auditoría, archivos | Tenant obligatorio cuando deriva de negocio |
| `INTEGRATION_MAPPING` | Mapeo hacia sistemas externos | Un mapping por tenant interno y receptor |

Debe existir un inventario exhaustivo de tablas, entidades, repositorios, endpoints, jobs, archivos y métricas antes de la primera migración destructiva.

### 6.1 Inventario local previo a V8

Inventario cerrado sobre `main` en `1d8ad314abdb3efa0ab9704395c2505b98087672`.
Se relevaron 43 tablas de negocio/operación, 35 entidades JPA, 35
`JpaRepository`, 45 `@Query` (8 nativas), siete componentes JDBC, seis tareas
planificadas y un flujo `@Async`. Todos los repositorios tenant-owned heredaban
`findAll`, `findById`, `deleteById`, `count` y `existsById` sin una frontera de
tenant. No existían `TenantContext`, membership, discriminator interno, RLS ni
pruebas de dos tenants.

Leyenda de consumidores: `A` académico (`/api/alumnos`, disciplinas,
inscripciones y asistencias); `E` economía (`/api/cargos`, pagos, crédito,
caja, egresos y reportes); `O` operación (`/api/stocks`, ventas,
notificaciones y recibos); `S` seguridad (`/api/login`, usuarios, roles y
permisos); `J` exportación `/api/integraciones/jere-platform/student-source`.
`JPA` indica el repositorio homónimo; `SQL` un store/servicio JDBC explícito.

| Tabla / agregado | Entidad / acceso | Consumidores | Clase | Tenant requerido | Constraint actual relevante | Objetivo y migración | Prueba requerida |
|---|---|---|---|---|---|---|---|
| `usuarios` | `Usuario` / `UsuarioRepositorio` | S, A/E actor | `SECURITY_GLOBAL` | No en identidad | usuario normalizado global, rol legacy | identidad global; memberships V8; actor conserva FK simple | login multi-tenant, revocación |
| `permisos` | `Permiso` / JPA | S | `GLOBAL` | No | código único | catálogo inmutable compartido | catálogo igual entre tenants |
| `roles` | `Rol` / `RolRepositorio` | S | `TENANT_OWNED` | Sí | código único global | V9 `tenant_id`; unique `(tenant_id,codigo)`; RLS | rol de A invisible en B |
| `rol_permisos` | colección `Rol.permisos` | S | `TENANT_OWNED` | Por rol | PK rol/permiso | tenant por rol + FK compuesta; RLS vía rol | asignación cruzada bloqueada |
| `usuario_roles` | colección legacy | S | `SECURITY_GLOBAL` | No, compatibilidad | PK usuario/rol | backfill a membership roles; no autoridad runtime | legacy no concede acceso |
| `refresh_sessions` | `RefreshSession` / JPA | S | `OPERATIONAL` | Sí | hash único; usuario FK | V8 tenant+membership+versiones; RLS | refresh A/B, replay, suspensión |
| `bootstrap_ejecuciones` | `BootstrapService` / SQL | S | `OPERATIONAL` | No | singleton de bootstrap | control plane explícito; sin acceso de dominio | bootstrap idempotente |
| `auditoria_eventos` | `AuditService` / JDBC | todas | `OPERATIONAL` | Cuando deriva de tenant | append-only, idempotency global | tenant nullable sólo para identidad/control plane; índice tenant | auditoría A/B y admin explícito |
| `alumnos` | `Alumno` / JPA | A, J, cumpleaños | `TENANT_OWNED` | Sí | documento único global | backfill V9; unique tenant/documento; FK compuestas; RLS | mismo documento A/B, CRUD/lista |
| `salones` | `Salon` / JPA | A | `TENANT_OWNED` | Sí | sin unique funcional | tenant+id; RLS | mismo nombre A/B |
| `profesores` | `Profesor` / JPA | A, reportes | `TENANT_OWNED` | Sí | email sin scope | tenant+id; índices tenant; RLS | búsqueda y reporte A/B |
| `observaciones_profesores` | `ObservacionProfesor` / JPA | A, reportes | `TENANT_OWNED` | Sí | FK profesor simple | FK `(tenant_id,profesor_id)`; RLS | FK cruzada y reporte |
| `bonificaciones` | `Bonificacion` / JPA | A/E | `TENANT_OWNED` | Sí | nombre global implícito | unique/index tenant cuando aplica; RLS | catálogo A/B |
| `recargos` | `Recargo` / JPA | E, job recargos | `TENANT_OWNED` | Sí | sin scope | tenant+id; RLS | job separado A/B |
| `metodo_pagos` | `MetodoPago` / JPA | E | `TENANT_OWNED` | Sí | nombre global | unique `(tenant_id,nombre)`; RLS | método homónimo A/B |
| `sub_conceptos` | `SubConcepto` / JPA | E | `TENANT_OWNED` | Sí | descripción global implícita | tenant+id; índices tenant; RLS | búsqueda A/B |
| `conceptos` | `Concepto` / JPA | E | `TENANT_OWNED` | Sí | FK sub-concepto simple | FKs compuestas; RLS | referencia cruzada bloqueada |
| `stocks` | `Stock` / JPA | O, reportes | `TENANT_OWNED` | Sí | código de barras único global | unique `(tenant_id,codigo_barras)`; RLS | stock/código A/B |
| `disciplinas` | `Disciplina` / JPA | A/E | `TENANT_OWNED` | Sí | FKs salón/profesor simples | FKs compuestas; índices tenant; RLS | referencias y listado A/B |
| `disciplina_horarios` | `DisciplinaHorario` / JPA | A | `TENANT_OWNED` | Sí | FK disciplina simple | FK compuesta; RLS | horario ajeno bloqueado |
| `inscripciones` | `Inscripcion` / JPA | A/E, jobs | `TENANT_OWNED` | Sí | unique activa alumno/disciplina | unique y FKs con tenant; RLS | alta cruzada, pagina/conteo |
| `mensualidades` | `Mensualidad` / JPA | E, jobs/reportes | `TENANT_OWNED` | Sí | FKs simples | FKs compuestas; índices tenant; RLS | liquidación/reporte A/B |
| `matriculas` | `Matricula` / JPA | A/E, job anual | `TENANT_OWNED` | Sí | alumno/fecha sin scope | FKs/índices tenant; RLS | job y CRUD A/B |
| `asistencias_mensuales` | `AsistenciaMensual` / JPA | A, job mensual | `TENANT_OWNED` | Sí | disciplina/año/mes | unique/FK con tenant; RLS | job y listado A/B |
| `asistencias_alumno_mensual` | `AsistenciaAlumnoMensual` / JPA | A | `TENANT_OWNED` | Sí | FKs asistencia/inscripción | FKs compuestas; RLS | relación cruzada bloqueada |
| `asistencias_diarias` | `AsistenciaDiaria` / JPA | A, reportes | `TENANT_OWNED` | Sí | FK mensual simple | FK compuesta; RLS | escritura/reporte A/B |
| `ventas_stock` | `VentaStock` / JPA | O/E | `TENANT_OWNED` | Sí | FKs alumno/stock/usuario | FKs de negocio compuestas; RLS | venta cruzada, caja/stock |
| `cargos` | `Cargo` / JPA | E, jobs/reportes | `TENANT_OWNED` | Sí | FKs simples e idempotencia global | FKs/uniques tenant; RLS | pago/reporte/job A/B |
| `pagos` | `Pago` / JPA | E, recibos | `TENANT_OWNED` | Sí | FKs alumno/método/usuario | FKs negocio compuestas; RLS | pago ajeno 404; overpay intacto |
| `aplicaciones_pago` | `AplicacionPago` / JPA | E | `TENANT_OWNED` | Sí | FKs pago/cargo simples | FKs compuestas; RLS | pago-cargo cruzado bloqueado |
| `egresos` | `Egreso` / JPA | E | `TENANT_OWNED` | Sí | método/usuario simples | FKs e índices tenant; RLS | anulación/lista A/B |
| `movimientos_caja` | `MovimientoCaja` / JPA | E, reportes | `TENANT_OWNED` | Sí | pago/egreso/método simples | FKs compuestas; RLS | caja y sumas separadas |
| `movimientos_credito` | `MovimientoCredito` / JPA | E | `TENANT_OWNED` | Sí | alumno/pago/cargo simples | FKs compuestas; RLS | crédito cruzado bloqueado |
| `movimientos_stock` | `MovimientoStock` / JPA | O | `TENANT_OWNED` | Sí | stock/venta simples | FKs compuestas; RLS | reversión A/B |
| `recibos` | `Recibo` / JPA + filesystem | E/O | `OPERATIONAL` | Sí | pago único global | tenant+FK compuesta; path namespaced; RLS | descarga/reimpresión/IDOR |
| `recibos_pendientes` | `ReciboPendiente` / native JPA | worker recibos | `OPERATIONAL` | Sí | pago único; SKIP LOCKED global | tenant en outbox; claim por tenant; RLS | retry/claim A/B |
| `notificaciones` | `Notificacion` / native JPA | O, cumpleaños | `OPERATIONAL` | Sí | dedup global | dedup y RLS por tenant | job/dedup A/B |
| `disciplina_tarifas` | `TarifaDisciplina` / JPA | E | `TENANT_OWNED` | Sí | vigencia por disciplina | FKs/ventanas tenant; RLS | tarifa vigente A/B |
| `inscripcion_condiciones_economicas` | `CondicionEconomicaInscripcion` / JPA | E | `TENANT_OWNED` | Sí | vigencia por inscripción | FKs/ventanas tenant; RLS | condición A/B |
| `cargo_liquidaciones` | `LiquidacionCargoServicio` / JDBC | E, reportes | `TENANT_OWNED` | Sí | FKs simples | FKs compuestas; RLS | cálculo/reporte A/B |
| `cargo_eventos` | `CargoEventoServicio` / JDBC | E, auditoría | `OPERATIONAL` | Sí | append-only; idempotencia global | tenant; idempotencia tenant; RLS | evento/replay A/B |
| `jere_platform_student_export_snapshots` | `StudentSourceExportStore` / JDBC | J | `INTEGRATION_MAPPING` | Sí | mapping externo inmutable | internal tenant + FK mapping; unique tenant/checkpoint; RLS | snapshot histórico A/B |
| `jere_platform_student_export_pages` | `StudentSourceExportStore` / JDBC | J | `OPERATIONAL` | Sí | FK snapshot, página única | tenant+FK compuesta; RLS | páginas/firma A/B |

Objetos adicionales: `v_cuotas_seguimiento` es una proyección tenant-owned y se
recreará con joins por tenant y `security_invoker`; los triggers append-only de
auditoría y cargos permanecen globales en definición, pero protegen filas con
tenant. Flyway schema history es `GLOBAL` operacional y no pertenece al
dominio. Los PDFs/recibos en filesystem son `OPERATIONAL`; pasan de nombre
global por pago a namespace `<tenant-id>/recibos/` y toda lectura valida
tenant+permiso. No se encontró cache backend de negocio; el `QueryClient`
frontend global sí requiere cancelación y borrado al cambiar sesión/tenant.

### 6.2 Inventario de consultas, endpoints y procesos

- Persistencia: 45 `@Query`, incluidas ocho nativas, más JDBC en auditoría,
  liquidaciones/eventos y Jere Platform. Todas las consultas de dominio quedan
  cubiertas por RLS; las nativas además forman parte del scanner con allowlist
  explícita de control plane.
- API: los controllers bajo `/api/**` consumen agregados tenant-owned salvo
  health, login inicial y endpoints globales de plataforma documentados. La
  frontera backend resuelve membership antes de ejecutar controller.
- Jobs: cumpleaños, matrícula anual, mensualidades, asistencias, recargos y el
  worker de recibos eran globales; cada ejecución deberá enumerar tenants
  activos, establecer contexto con `try/finally` y abrir una transacción por
  tenant.
- Async: email recibía una entidad en otro thread; transportará snapshot
  inmutable con tenant y reconstruirá contexto.
- Archivos: `ReciboStorageService` usaba `recibo_<pagoId>.pdf`; se reutiliza
  `ReciboPathResolver` y se agrega namespace técnico tenant.
- Frontend: access/profile viven en memoria y refresh en cookie HttpOnly, pero
  el `QueryClient` era global y no se limpiaba en login/logout. La shell deberá
  mostrar tenant, cancelar requests y vaciar caches al cambiarlo.
- Operación: backup/restore preservaba una única academia; las verificaciones
  se amplían a tenants, memberships, constraints y namespaces. El rollback a
  imagen single-tenant deja de ser compatible cuando RLS se vuelve obligatorio.

ADR aceptado: [`adr-0008-shared-schema-multitenancy.md`](adr-0008-shared-schema-multitenancy.md).

## 7. Invariantes no negociables

### 7.1 Datos

- Ninguna fila tenant-owned puede existir sin tenant.
- Una relación entre dos filas tenant-owned debe pertenecer al mismo tenant.
- Los índices únicos funcionales deben incluir `tenant_id` cuando la unicidad sea local.
- No se aceptan consultas globales implícitas.
- Las operaciones administrativas cross-tenant deben ser separadas, auditadas y denegadas por defecto.

### 7.2 Seguridad

- No confiar en IDs de tenant enviados por frontend.
- No aceptar cambio de tenant sin revalidar membership.
- Un `SUPERADMIN` no debe saltar aislamiento accidentalmente; el acceso cross-tenant debe ser una capacidad explícita.
- Refresh tokens y sesiones deben quedar ligados al tenant o forzar reselección segura.
- Toda denegación cross-tenant debe responder sin revelar existencia del recurso.

### 7.3 Procesos asíncronos

- `@Async`, schedulers, outbox y reintentos no heredan contexto thread-local de forma implícita.
- Cada mensaje o trabajo debe almacenar `tenant_id` y reconstruir contexto validado.
- No debe existir un job global que mezcle resultados de distintos tenants sin diseño explícito.

### 7.4 Archivos y recibos

- Rutas, claves de storage y metadatos deben incorporar tenant de forma segura.
- Un path recibido nunca puede permitir traversal o acceso a otro tenant.
- Reimpresión, descarga, generación y cleanup deben verificar tenant.

### 7.5 Integraciones

- El mapping actual de Jere Platform deberá evolucionar de configuración global a mapping por tenant interno.
- Snapshots históricos deben conservar tenant interno y tenant externo usados al crearse.
- No modificar V7; agregar una migración posterior.

## 8. Backlog de implementación controlado

### Fase 0 — Auditoría e inventario

Estado: `EXECUTED_PASS`

Entregables:

- mapa de entidades y tablas;
- mapa de repositorios y consultas nativas;
- mapa de endpoints;
- mapa de jobs, eventos, outbox, PDFs y archivos;
- clasificación `GLOBAL`/`TENANT_OWNED`;
- threat model de fugas;
- ADR de estrategia;
- plan de migración y rollback.

Gate: no se modifica el esquema hasta aprobar el inventario.

Evidencia: secciones 6.1/6.2, ADR-0008 y bitácora local del 2026-07-30.

### Fase 1 — Control plane de tenant

Estado: `EXECUTED_PASS`

Entregables:

- entidad y repositorio de tenant;
- lifecycle;
- tenant inicial para datos existentes;
- membership usuario-tenant;
- servicios de resolución y autorización;
- auditoría de selección y cambios.

### Fase 2 — Identidad, sesión y API

Estado: `EXECUTED_PASS`

Entregables:

- selección segura de tenant;
- claims o sesión tenant-bound;
- refresh/logout coherentes;
- `TenantContext` con cleanup garantizado;
- respuestas 401/403/404 sin enumeración;
- contratos API documentados.

### Fase 3 — Migración de datos y persistencia

Estado: `EXECUTED_PASS`

Entregables:

- migraciones Flyway append-only;
- backfill al tenant inicial;
- FKs compuestas o guards equivalentes;
- índices y unicidad tenant-aware;
- repositorios y queries acotados;
- RLS en tablas críticas si se adopta;
- verificación de integridad post-migración.

### Fase 4 — Servicios funcionales

Estado: `EXECUTED_PASS`

Cobertura obligatoria:

- alumnos y responsables;
- profesores;
- disciplinas, salones y horarios;
- inscripciones y asistencia;
- tarifas, cargos y liquidaciones;
- pagos, aplicaciones, crédito y recibos;
- caja, stock, ventas y movimientos;
- notificaciones y cumpleaños;
- reportes y exportaciones;
- usuarios, roles y permisos.

### Fase 5 — Jobs, archivos e integraciones

Estado: `EXECUTED_PASS`

Entregables:

- schedulers tenant-aware;
- outbox tenant-aware;
- PDFs y storage segregados;
- email con `message_type` y tenant técnico sin PII;
- mapping Jere Platform por tenant;
- replay y retries sin contaminación cruzada.

### Fase 6 — Frontend

Estado: `EXECUTED_PASS`

Entregables:

- selector sólo para memberships autorizadas;
- tenant activo visible;
- invalidación de caches al cambiar;
- rutas, queries y estados tenant-aware;
- manejo de tenant suspendido o membership revocada;
- tests de navegación y ausencia de datos residuales.

### Fase 7 — Operación y certificación

Estado: `IMPLEMENTED_UNVERIFIED`

Entregables:

- métricas y logs tenant-safe;
- health de resolución y configuración;
- backup/restore verificado;
- rollback de aplicación y migración compatible;
- seed con dos tenants;
- smoke de aislamiento;
- documentación y runbook;
- certificación post-push.

## 9. Matriz de cobertura

Actualizar esta tabla en cada intervención.

| Capacidad | Estado | Evidencia | Riesgo pendiente |
|---|---|---|---|
| Modelo de tenant | `EXECUTED_PASS` | V8, paquete `gestudio.tenancy`, PostgreSQL y `clean verify` | Sin riesgo técnico abierto en el gate local |
| Membership | `EXECUTED_PASS` | V8, servicios, login multitenant y rol runtime real | Sin riesgo técnico abierto en el gate local |
| Resolución por request | `EXECUTED_PASS` | `SecurityFilter` revalida tenant/membership/versiones | Sin riesgo técnico abierto en el gate local |
| Contexto backend | `EXECUTED_PASS` | Mismo `pg_backend_pid` reutilizado sin fuga | Sin riesgo técnico abierto en el gate local |
| Esquema tenant-aware | `EXECUTED_PASS` | V1-V11 limpio y V7-V11 incremental | Sin riesgo técnico abierto en el gate local |
| Constraints cross-tenant | `EXECUTED_PASS` | FKs compuestas, checks e índices verificados | Sin riesgo técnico abierto en el gate local |
| RLS | `EXECUTED_PASS` | `FORCE RLS`, policies, grants y rol no owner reales | Sin riesgo técnico abierto en el gate local |
| Autenticación tenant-bound | `EXECUTED_PASS` | login, selección, refresh, filtro y revocación reales | Sin riesgo técnico abierto en el gate local |
| Frontend tenant-aware | `EXECUTED_PASS` | selector, cambio de scope, 166 tests, lint y build | Revalidar si cambia el contrato |
| Jobs tenant-aware | `EXECUTED_PASS` | `TenantExecutionService`, callers y suite completa | Sin riesgo técnico abierto en el gate local |
| Archivos tenant-aware | `EXECUTED_PASS` | namespace, migrador y pruebas filesystem/PostgreSQL | Backup/restore multitenant separado |
| Jere Platform por tenant | `EXECUTED_PASS` | mapping, export y upgrade V7 probados | Sin riesgo técnico abierto en el gate local |
| Auditoría tenant-aware | `EXECUTED_PASS` | auditoría global/tenant bajo rol runtime y suite completa | Sin riesgo técnico abierto en el gate local |
| Métricas tenant-safe | `EXECUTED_PASS` | health estructural GREEN y pruebas | Observación en despliegue real pendiente |
| Pruebas de aislamiento | `EXECUTED_PASS` | Testcontainers PostgreSQL 15 con dos tenants | Sin riesgo técnico abierto en el gate local |
| Migración de datos | `EXECUTED_PASS` | V1-V11 y estado V7 representativo hasta V11 | Reconciliación productiva depende de datos reales |
| Backup/restore tenant-aware | `ABSENT` | El gate heredado no certifica namespaces multitenant | Alto |
| Runbook | `DESIGNED` | Este documento y ADR-0008 | Certificación post-push pendiente |

Estados permitidos:

- `ABSENT`
- `DESIGNED`
- `IMPLEMENTED_UNVERIFIED`
- `EXECUTED_PASS`
- `BLOCKED`
- `NOT_APPLICABLE`
- `PARTIAL_EXTERNAL_ONLY`

No usar `DONE` ni porcentajes subjetivos.

## 10. Health model

### 10.1 Health estructural

`MULTITENANCY_STRUCTURAL_HEALTH`:

- `RED`: falta cualquier frontera esencial de identidad, datos o autorización;
- `AMBER`: fronteras implementadas, pero faltan pruebas o migración completa;
- `GREEN`: todos los gates pasan sobre el SHA publicado.

Estado actual: `AMBER`.

Motivo: el health estructural de base devuelve `GREEN` y el gate técnico local
pasó, pero la definición absoluta exige además backup/restore multitenant y SHA
publicado. `AMBER` evita confundir cierre técnico local con certificación
operacional completa.

### 10.2 Indicadores operativos futuros

No agregar tenants como tags de alta cardinalidad sin evaluación.

Métricas mínimas equivalentes:

- `gestudio_tenant_resolution_total{result}`
- `gestudio_tenant_access_denied_total{reason}`
- `gestudio_tenant_context_missing_total{operation}`
- `gestudio_tenant_cross_scope_blocked_total{resource_type}`
- `gestudio_tenant_job_total{job_type,result}`
- `gestudio_tenant_migration_health{check}`

No etiquetar con emails, nombres, documentos, IDs de alumnos, pagos ni subjects.

### 10.3 Health endpoints

- Liveness no debe depender de una consulta compleja de tenants.
- Readiness debe fallar si la configuración exige multitenancy y no puede garantizar contexto o esquema compatible.
- Debe existir un indicador separado de integridad multitenant, sin exponer IDs sensibles.

## 11. Pruebas obligatorias

### 11.1 Regla base

Toda prueba de funcionalidad tenant-owned debe usar al menos:

- tenant A;
- tenant B;
- usuario miembro de A;
- usuario miembro de B;
- usuario con memberships múltiples cuando aplique;
- recurso con el mismo ID funcional o nombre en ambos tenants cuando sea legal.

### 11.2 Casos negativos mínimos

- leer por ID un recurso del otro tenant;
- actualizarlo;
- eliminarlo;
- enumerarlo en listados, búsquedas y reportes;
- referenciarlo desde una entidad propia;
- descargar su PDF o archivo;
- obtenerlo por endpoint administrativo;
- procesarlo desde scheduler/outbox;
- inferir su existencia por diferencias de error o timing;
- reutilizar refresh token después de revocar membership;
- cambiar header/claim/request para suplantar tenant;
- contaminar caches al cambiar tenant en frontend.

### 11.3 Persistencia real

Las pruebas de aislamiento, constraints, locks, RLS, migración y outbox deben ejecutarse contra PostgreSQL real mediante la infraestructura de tests existente. H2 o mocks no acreditan estas propiedades.

## 12. Gate reproducible requerido

No existe un wrapper específico y no se agrega uno mientras los comandos del
repositorio cubran el gate. Con Java 21, desde `backend/`:

```powershell
.\mvnw.cmd '-Dtest=ApplicationRoleAuthenticationPostgreSqlTest,PostgreSqlSchemaValidationTest' test
.\mvnw.cmd clean verify
```

Desde `frontend/`:

```powershell
npm ci
npm test
npm run lint
$env:VITE_API_BASE_URL = 'https://example.invalid/api'
npm run build
```

El gate debe ejecutar y registrar, sin secretos:

1. inventario actualizado;
2. migración desde base single-tenant;
3. base limpia;
4. integridad de FKs e índices;
5. aislamiento CRUD entre dos tenants;
6. autenticación y refresh tenant-aware;
7. jobs y outbox;
8. archivos y recibos;
9. reportes;
10. integración Jere Platform;
11. métricas y logs sanitizados;
12. Compose y perfiles aplicables;
13. ausencia de queries globales no autorizadas;
14. ausencia de secretos y artefactos versionados.

La evidencia debe guardarse fuera del repositorio.

## 13. Protocolo de autoactualización

Cada commit que toque alguno de estos elementos debe revisar este documento:

- entidades o migraciones;
- autenticación, JWT, refresh o seguridad;
- repositorios, specifications o queries nativas;
- jobs, `@Async`, outbox o eventos;
- storage, PDF, backup o restore;
- integración Jere Platform;
- frontend de sesión, caches o selección de organización;
- métricas, logs o auditoría;
- scripts de validación.

Actualización obligatoria:

1. cambiar la fecha y SHA auditado;
2. actualizar matriz de cobertura;
3. registrar archivos y símbolos modificados;
4. mover estados sólo con evidencia ejecutada;
5. agregar riesgos descubiertos;
6. registrar comandos, exit codes y resultados reales;
7. actualizar decisiones si cambió arquitectura;
8. mantener pendientes externos separados de faltantes internos.

No borrar historia útil. Las decisiones reemplazadas deben quedar en la bitácora con estado `SUPERSEDED`.

## 14. Registro de decisiones

| ID | Decisión | Estado | Motivo |
|---|---|---|---|
| MT-001 | El baseline anterior a V8 era single-tenant por deployment | `SUPERSEDED` | Inventario de la sección 6 y cierre técnico V8-V11 |
| MT-002 | El tenant externo de Jere Platform no acredita multitenancy interno | `CONFIRMED` | Mapping global por configuración |
| MT-003 | Estrategia: shared database + shared schema + discriminator + RLS | `ACCEPTED` | ADR-0008; preserva el monolito y cubre JDBC/jobs |
| MT-004 | Defensa en profundidad; filtros JPA solos no bastan | `REQUIRED` | Riesgo de queries nativas/jobs |
| MT-005 | Migraciones publicadas no se editan | `REQUIRED` | Contrato Flyway existente |
| MT-006 | Debe existir tenant inicial para backfill | `REQUIRED` | Compatibilidad de datos actuales |
| MT-007 | Superadmin cross-tenant requiere capacidad explícita | `REQUIRED` | Evitar bypass accidental |
| MT-008 | Roles tenant-owned; permisos globales; usuario global | `ACCEPTED` | La edición de roles es local y la identidad no se duplica |
| MT-009 | Rol DB de aplicación separado del rol Flyway/operativo | `ACCEPTED` | RLS no protege al dueño/superuser por defecto |
| MT-010 | Rollback single-tenant termina al activar RLS obligatorio | `ACCEPTED` | Una imagen vieja no establece contexto y debe fallar cerrado |

## 15. Registro de riesgos

| ID | Riesgo | Severidad | Control requerido | Estado |
|---|---|---:|---|---|
| MT-R001 | Fuga de datos por repositorio sin filtro | Crítica | Contexto + persistencia + tests + RLS | Abierto |
| MT-R002 | Referencias cruzadas por FK simple | Crítica | Constraint tenant-aware | Abierto |
| MT-R003 | Job ejecutado sin tenant | Crítica | Tenant en payload y reconstrucción | Abierto |
| MT-R004 | Sesión reutilizada en tenant no autorizado | Crítica | Membership revalidada y revocación | Abierto |
| MT-R005 | Cache frontend conserva datos al cambiar tenant | Alta | Invalidación total controlada | Abierto |
| MT-R006 | Archivos accesibles por path/ID de otro tenant | Crítica | Storage namespaced y autorización | Abierto |
| MT-R007 | Reporte o exportación mezcla tenants | Crítica | Scope obligatorio y pruebas | Abierto |
| MT-R008 | Backfill incompleto deja filas huérfanas | Crítica | Migración transaccional y checks | Abierto |
| MT-R009 | RLS rompe migraciones/jobs administrativos | Alta | Roles DB y runbook explícitos | Abierto |
| MT-R010 | `organizationId` Jere se confunde con tenant interno | Alta | Modelo y nombres separados | Abierto |

## 16. Bitácora de ejecución

### 2026-07-30 — Preflight, baseline e inventario local

- Repositorio: `JerePrograma/Gestudio`; rama `main`.
- SHA normativo confirmado y sincronizado: `1d8ad314abdb3efa0ab9704395c2505b98087672`.
- Árbol inicial/final de baseline: limpio; `HEAD == origin/main`.
- Comando: `pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate-local-full.ps1`.
- Resultado: `PASS`, exit code `0`, duración acumulada de gates
  `00:12:40.7477356`.
- Gates: setup `00:00:35.1252576`; validate-all `00:02:36.5458250`;
  smoke `00:01:46.4022922`; demo seed `00:03:15.7461975`; backup/restore
  `00:01:42.6688699`; rollback `00:02:12.2379429`; observabilidad
  `00:00:32.0213502`.
- Pruebas: backend 261 (0 fallos, 2 omitidas por symlink); contratos Node 9;
  frontend Vitest 149; smoke 20/20; backup 12/12; rollback 8/8;
  observabilidad 8/8.
- Warnings: host Node 24/npm 11 difiere de CI Node 22/npm 10; npm omitió
  scripts no permitidos de `esbuild`; sin vulnerabilidades npm.
- Evidencia externa a Git:
  `C:\Users\Jerem\AppData\Local\Temp\GestudioValidation\20260730-095320-1d8ad314abdb`.
- Auditoría: 43 tablas, 35 entidades, 35 repositorios, 45 consultas declaradas,
  8 nativas, 7 componentes JDBC, 6 schedulers y 1 flujo async; multitenancy
  interno confirmado ausente antes de esta implementación.
- Decisión: ADR-0008 aceptado; Fase 0 `EXECUTED_PASS`. Ninguna migración V1-V7
  fue modificada.

### 2026-07-30 — Auditoría remota inicial

- SHA base: `ec5cee0773baa2b8c50f2b5c6768e424e08c7efe`.
- Alcance: inspección estática remota mediante GitHub.
- Resultado: `MULTITENANCY_STRUCTURAL_HEALTH=RED`.
- Confirmado: una academia por deployment.
- Confirmado: tenant externo sólo en exportación Jere Platform.
- No ejecutado: build, tests, migraciones, Compose ni runtime local.
- Decisión: crear este contrato antes de cualquier implementación.

### 2026-08-04 — Validación PostgreSQL y cierre técnico local

- Base Git verificada: `main`, `HEAD == origin/main == 1d8ad314abdb3efa0ab9704395c2505b98087672`
  antes de publicar; una sola worktree, staging y conflictos vacíos.
- Docker Engine 29.3.1 disponible sin intervención de Codex; Testcontainers
  1.21.4 usó PostgreSQL 15.18 y puertos host aleatorios.
- Focalizados: 13 tests, 0 fallos, 0 errores y 0 skips; V1-V11, V7-V11,
  Hibernate, rol runtime, RLS y conexión reutilizada pasaron.
- Backend: `.\mvnw.cmd clean verify` PASS; 282 tests, 0 fallos, 0 errores,
  2 skips de symlink por limitación del host; JaCoCo y JAR completados.
- Frontend: `npm ci`, 166 tests, lint y build PASS con URL ficticia; lockfile
  sin cambios y sin dependencias nuevas.
- Demo estable V7: sólo lectura; ningún contenedor, volumen, puerto, archivo de
  estado o deployment fue modificado.
- Estado: cierre técnico local `EXECUTED_PASS`; certificación absoluta y
  publicación se registran por separado.

## 17. Formato obligatorio del informe de cada intervención

Codex debe cerrar cada trabajo con:

### Estado inicial

- repositorio;
- rama;
- HEAD y `origin/main`;
- árbol de trabajo;
- fase y estados de este documento.

### Auditoría

- archivos inspeccionados;
- tablas, entidades, repositorios, endpoints y jobs afectados;
- supuestos confirmados y descartados;
- riesgos encontrados.

### Implementación

- cambios realizados;
- migraciones;
- compatibilidad;
- decisiones técnicas;
- matriz de cobertura actualizada.

### Seguridad e aislamiento

- mecanismo de resolución;
- controles de lectura y escritura;
- constraints/RLS;
- casos cross-tenant ejecutados;
- ausencia de PII y secretos en logs.

### Validaciones

Para cada comando:

- comando exacto;
- commit;
- exit code;
- duración;
- cantidad de pruebas;
- resultado;
- warnings.

### Git

- archivos modificados;
- diff revisado;
- commit y mensaje;
- push a `origin/main`;
- `HEAD == origin/main`;
- árbol limpio.

### Estado final

- fases completadas;
- estados exactos de la matriz;
- health estructural;
- bloqueos reales;
- siguiente trabajo mínimo verificable.

## 18. Condición de cierre absoluta

No declarar multitenancy completo por tener una tabla de tenants, un filtro Hibernate, un claim JWT o un selector visual.

La única declaración final válida será:

`MULTITENANCY=IMPLEMENTED_AND_CERTIFIED`

acompañada por:

- migración probada desde datos actuales;
- dos tenants aislados en toda la superficie funcional;
- gate específico `EXECUTED_PASS`;
- suite completa `EXECUTED_PASS`;
- smoke, backup/restore, observabilidad y rollback `EXECUTED_PASS`;
- SHA publicado y certificado;
- matriz sin estados `ABSENT`, `IMPLEMENTED_UNVERIFIED` ni riesgos críticos abiertos.
