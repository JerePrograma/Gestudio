# ADR-0008: multitenancy interno con esquema compartido y defensa en profundidad

- Estado: `ACCEPTED`
- Fecha: 2026-07-30
- Alcance: instancia Gestudio, no identidad externa de Jere Platform
- Documento rector: `multitenancy-governance-and-health.md`

## Contexto

Gestudio es un monolito Spring Boot con PostgreSQL, Flyway, JPA y consultas
JDBC puntuales. El esquema publicado V1-V7 representa una academia por
deployment. El `tenantId` de la exportación Jere Platform es una etiqueta del
receptor externo configurada globalmente y no una frontera interna.

La implementación debe aislar academia, finanzas, archivos, sesiones, jobs y
caches sin duplicar el modelo ni convertir el monolito en servicios
distribuidos.

## Decisión

Se adopta una base compartida, un esquema compartido y un discriminator
`tenant_id` estable para cada agregado tenant-owned. La defensa es acumulativa:

1. sesión y refresh ligados a una membership activa;
2. `TenantContext` establecido y limpiado por request o job;
3. autorización efectiva derivada de roles de la membership;
4. repositories y servicios ejecutados con contexto obligatorio;
5. claves foráneas compuestas e índices con prefijo tenant;
6. PostgreSQL RLS forzado para la conexión de aplicación;
7. pruebas negativas con dos tenants y scanner de consultas globales.

El tenant se identifica internamente por UUID. Un código humano estable se usa
para operación y seed, no como clave foránea. El lifecycle es `ACTIVE`,
`SUSPENDED`, `ARCHIVED`; no existe borrado físico ordinario.

`usuarios` conserva la identidad global. La autorización de negocio vive en
`tenant_memberships` y sus roles. Los permisos son catálogo global; los roles
son tenant-owned porque el sistema permite administrarlos. Las relaciones
legacy `usuarios.rol_id` y `usuario_roles` se conservan sólo durante la ventana
de compatibilidad y dejan de ser la autoridad de requests tenant-bound.

La administración cross-tenant no se obtiene por portar `SUPERADMIN`: requiere
una capacidad global separada, endpoint separado y evento de auditoría. Al
entrar a un tenant, incluso un administrador de plataforma queda sujeto a una
membership explícita y a RLS.

## Resolución y sesiones

El backend autentica primero la identidad global, carga memberships activas y
valida el tenant elegido. Con una sola membership selecciona automáticamente;
con varias devuelve una respuesta de selección sin emitir credenciales. La
selección se reenvía al login y nunca se acepta como autoridad independiente.

Access token y refresh session conservan `tenant_id`, versión de seguridad del
tenant y versión de seguridad de la membership. Cada request sensible vuelve a
validar tenant y membership. Suspender tenant o membership invalida el acceso y
el refresh sin esperar la expiración. Cambiar tenant rota la familia refresh,
cancela requests del frontend y limpia caches tenant-owned.

## Persistencia y RLS

Las tablas tenant-owned reciben `tenant_id NOT NULL` después de crear el tenant
inicial y completar el backfill. Toda relación entre filas tenant-owned se
protege con una clave candidata `(tenant_id, id)` y FK compuesta. Las
unicidades de negocio se vuelven locales al tenant.

RLS usa `current_setting('app.current_tenant_id', true)` y políticas
`USING`/`WITH CHECK`. La conexión de aplicación usa un rol sin `BYPASSRLS` y
sin propiedad de tablas; el rol Flyway/operativo conserva privilegios de
migración. La ausencia de setting en la conexión de aplicación falla cerrado.
El código limpia el setting al devolver la conexión al pool.

Testcontainers crea ambos roles y ejecuta las pruebas de aislamiento con el
rol de aplicación. Las pruebas que sólo validan migraciones usan el rol de
migración, pero no acreditan aislamiento.

Backups se realizan con el rol operativo y contienen todos los tenants. Un
restore se certifica reconciliando tenants, memberships, constraints, filas y
namespaces de archivos. No existe bypass RLS desde endpoints normales. Los
jobs enumeran tenants activos con una operación de control plane explícita y
procesan uno por transacción/contexto.

## Alternativas evaluadas

### Base por tenant

Ofrece una frontera física fuerte, pero multiplica pools, migraciones,
backups, restores y observabilidad. El tamaño y operación actual de Gestudio no
justifican esa complejidad. Se reconsiderará sólo si aparecen requisitos
regulatorios o de escala que exijan separación física.

### Esquema por tenant

Evita parte de la mezcla de filas, pero multiplica objetos y Flyway, complica
queries operativas y no resuelve sesiones, jobs, archivos ni caches. Tampoco
elimina el riesgo de seleccionar el esquema equivocado.

### Sólo filtro Hibernate o Specifications

Se rechaza como frontera: no cubre JDBC, native queries, jobs, bulk SQL ni
errores de repositorio. Puede complementar la ergonomía, pero no sustituye
constraints ni RLS.

### Sólo repositorios explícitos

Se rechaza por depender de disciplina humana y por dejar heredados globales de
`JpaRepository`. Las APIs explícitas son útiles, pero la base debe bloquear el
escape aunque una consulta omita el predicado.

### RLS como única defensa

Se rechaza: RLS no valida memberships, permisos, lifecycle, frontend, archivos
ni payloads asíncronos. También puede ser bypassed por un rol mal configurado.

## Migración y compatibilidad

La evolución es forward-only a partir de V8:

- V8 crea control plane, tenant inicial y memberships derivadas del RBAC actual;
- V9 agrega discriminator, backfill, claves compuestas e índices;
- V10 instala grants, políticas RLS, control de mapping Jere y health estructural;
- V11 completa la cobertura de índices para claves foráneas.

El artefacto anterior puede iniciar sólo durante la etapa compatible anterior
a la activación RLS. Después de volver obligatoria la resolución tenant, el
rollback soportado es restaurar el artefacto multitenant anterior o restaurar
un backup completo en una ventana controlada; no se promete compatibilidad con
una imagen single-tenant que no establece contexto.

## Consecuencias

- Una academia nueva se aprovisiona como tenant y memberships, no como nuevo
  deployment.
- Todas las operaciones tenant-owned requieren contexto, incluidas tareas y
  descargas.
- Las consultas operativas cross-tenant quedan en componentes y credenciales
  separados.
- El costo principal es ampliar claves/FKs y probar cada familia; se acepta por
  preservar integridad incluso ante defectos de aplicación.
- El mapping Jere guarda por snapshot el tenant interno y los identificadores
  externos efectivos; un cambio futuro no reinterpreta historia.

## Operación y evidencia requerida para cerrar

Gestudio requiere Java 21. El datasource de runtime debe autenticarse con un
rol `LOGIN` miembro de `gestudio_app`, sin ownership, `SUPERUSER` ni
`BYPASSRLS`; Flyway usa un usuario propietario separado. El script
`scripts/db/10-create-application-role.sh` aprovisiona esos roles sólo al crear
un volumen PostgreSQL nuevo. Una base existente requiere aprovisionamiento
explícito antes de iniciar la imagen multitenant; nunca debe reutilizar el
usuario migrador como datasource de la aplicación.

La demo estable `Gestudio-Demo-Stable` permanece deliberadamente en V7. No se
ejecutan V8-V11 sobre su base ni sus volúmenes; las migraciones se prueban sólo
en PostgreSQL aislado.

Desde `backend/`, los gates soportados son:

```powershell
.\mvnw.cmd -v
.\mvnw.cmd '-Dtest=ApplicationRoleAuthenticationPostgreSqlTest,PostgreSqlSchemaValidationTest' test
.\mvnw.cmd clean verify
```

`PostgreSqlSchemaValidationTest` cubre tanto V1 a la última migración como el
upgrade materializado en V7. Los dos primeros tests requieren un daemon Docker
para Testcontainers. Desde `frontend/`, el contrato es `npm ci`, `npm test`,
`npm run lint` y `npm run build`; el build requiere una
`VITE_API_BASE_URL` HTTPS explícita.

Esta decisión sólo queda certificada cuando esos gates prueban base limpia,
upgrade V7, RLS con rol no propietario, aislamiento entre dos tenants,
sesiones, jobs, recibos, Jere Platform y frontend sobre el mismo SHA publicado.
La aceptación del ADR no cambia por sí sola el health estructural.
