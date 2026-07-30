# Gobierno, estado y health del multitenancy

> **Documento normativo vivo**  
> Estado actual: `NOT_IMPLEMENTED`  
> Rama de referencia: `main`  
> Última revisión estructural: 2026-07-30  
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

Gestudio es actualmente **single-tenant por deployment**.

No existe todavía:

- entidad de negocio `Tenant`, `Organization`, `Academia` o equivalente;
- tenant activo asociado a la sesión autenticada;
- `TenantContext` request-scoped;
- tenant claim validado en JWT o sesión refresh;
- pertenencia usuario-tenant;
- permisos acotados por tenant;
- `tenant_id` en el modelo transaccional general;
- filtros obligatorios de tenant en repositorios;
- aislamiento por PostgreSQL Row Level Security;
- unicidad compuesta por tenant;
- selección o conmutación de academia en frontend;
- provisioning, suspensión, archivado o eliminación de tenants;
- migración de datos single-tenant a un tenant inicial;
- backup, restore, observabilidad y jobs con alcance tenant-aware;
- suite de pruebas de fuga cruzada entre tenants.

El `tenantId` presente en `integraciones/jereplatform` **no implementa multitenancy interno**. Es un mapping externo estático definido por configuración del deployment para etiquetar snapshots exportados a Jere Platform. No puede elegirse por request ni por usuario.

## 3. Evidencia auditada en `main`

SHA observado al crear este documento:

`ec5cee0773baa2b8c50f2b5c6768e424e08c7efe`

Evidencia confirmada:

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

Estado: `PENDING`

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

### Fase 1 — Control plane de tenant

Estado: `PENDING`

Entregables:

- entidad y repositorio de tenant;
- lifecycle;
- tenant inicial para datos existentes;
- membership usuario-tenant;
- servicios de resolución y autorización;
- auditoría de selección y cambios.

### Fase 2 — Identidad, sesión y API

Estado: `PENDING`

Entregables:

- selección segura de tenant;
- claims o sesión tenant-bound;
- refresh/logout coherentes;
- `TenantContext` con cleanup garantizado;
- respuestas 401/403/404 sin enumeración;
- contratos API documentados.

### Fase 3 — Migración de datos y persistencia

Estado: `PENDING`

Entregables:

- migraciones Flyway append-only;
- backfill al tenant inicial;
- FKs compuestas o guards equivalentes;
- índices y unicidad tenant-aware;
- repositorios y queries acotados;
- RLS en tablas críticas si se adopta;
- verificación de integridad post-migración.

### Fase 4 — Servicios funcionales

Estado: `PENDING`

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

Estado: `PENDING`

Entregables:

- schedulers tenant-aware;
- outbox tenant-aware;
- PDFs y storage segregados;
- email con `message_type` y tenant técnico sin PII;
- mapping Jere Platform por tenant;
- replay y retries sin contaminación cruzada.

### Fase 6 — Frontend

Estado: `PENDING`

Entregables:

- selector sólo para memberships autorizadas;
- tenant activo visible;
- invalidación de caches al cambiar;
- rutas, queries y estados tenant-aware;
- manejo de tenant suspendido o membership revocada;
- tests de navegación y ausencia de datos residuales.

### Fase 7 — Operación y certificación

Estado: `PENDING`

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
| Modelo de tenant | `ABSENT` | No existe entidad interna | Crítico |
| Membership | `ABSENT` | RBAC global | Crítico |
| Resolución por request | `ABSENT` | Mapping externo global | Crítico |
| Contexto backend | `ABSENT` | Sin `TenantContext` | Crítico |
| Esquema tenant-aware | `ABSENT` | Modelo monoacademia | Crítico |
| Constraints cross-tenant | `ABSENT` | Sin tenant interno | Crítico |
| RLS | `ABSENT` | Sin políticas | Alto |
| Autenticación tenant-bound | `ABSENT` | Sesión global | Crítico |
| Frontend tenant-aware | `ABSENT` | Sin selector | Alto |
| Jobs tenant-aware | `ABSENT` | Ejecución global | Crítico |
| Archivos tenant-aware | `ABSENT` | Storage global | Crítico |
| Jere Platform por tenant | `PARTIAL_EXTERNAL_ONLY` | Mapping por deployment | Alto |
| Auditoría tenant-aware | `ABSENT` | Metadata parcial en exportación | Alto |
| Métricas tenant-safe | `ABSENT` | Sin dimensión interna | Medio |
| Pruebas de aislamiento | `ABSENT` | Sin suite de dos tenants | Crítico |
| Migración de datos | `ABSENT` | Sin tenant inicial | Crítico |
| Backup/restore tenant-aware | `ABSENT` | Backup global | Alto |
| Runbook | `THIS_DOCUMENT_ONLY` | Contrato inicial | Alto |

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

Estado actual: `RED`.

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

Debe crearse un script equivalente a:

`scripts/ops/verify-multitenancy.ps1`

Debe ejecutar y registrar, sin secretos:

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
| MT-001 | Gestudio actual es single-tenant por deployment | `CONFIRMED` | Documentación y código remoto |
| MT-002 | El tenant externo de Jere Platform no acredita multitenancy interno | `CONFIRMED` | Mapping global por configuración |
| MT-003 | Estrategia inicial recomendada: shared schema + discriminator | `PROVISIONAL` | Menor cambio compatible con monolito |
| MT-004 | Defensa en profundidad; filtros JPA solos no bastan | `REQUIRED` | Riesgo de queries nativas/jobs |
| MT-005 | Migraciones publicadas no se editan | `REQUIRED` | Contrato Flyway existente |
| MT-006 | Debe existir tenant inicial para backfill | `REQUIRED` | Compatibilidad de datos actuales |
| MT-007 | Superadmin cross-tenant requiere capacidad explícita | `REQUIRED` | Evitar bypass accidental |

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

### 2026-07-30 — Auditoría remota inicial

- SHA base: `ec5cee0773baa2b8c50f2b5c6768e424e08c7efe`.
- Alcance: inspección estática remota mediante GitHub.
- Resultado: `MULTITENANCY_STRUCTURAL_HEALTH=RED`.
- Confirmado: una academia por deployment.
- Confirmado: tenant externo sólo en exportación Jere Platform.
- No ejecutado: build, tests, migraciones, Compose ni runtime local.
- Decisión: crear este contrato antes de cualquier implementación.

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
