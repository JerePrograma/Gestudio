# ADR-0009: control plane SUPERADMIN separado del acceso tenant

- Estado: `ACCEPTED`
- Estado de implementación: `IMPLEMENTED_NOT_RUN`
- Fecha: 2026-08-12
- Alcance: identidad, sesiones, autorización, persistencia y operación del control plane de Gestudio
- Relación: extiende `adr-0008-shared-schema-multitenancy.md`; no sustituye sus invariantes de aislamiento tenant
- Documentos relacionados: [threat model del control plane](threat-model-platform-control-plane.md) y [runbook operativo](../operations/platform-control-plane-runbook.md)

## Contexto

Gestudio ya opera como monolito modular sobre PostgreSQL con esquema compartido,
`tenant_id`, contexto explícito y Row Level Security forzado. La identidad
`usuarios` es global, mientras que la autorización funcional se deriva de
`tenant_memberships`, roles y permisos del tenant activo.

El control plane existente distingue conceptualmente la capacidad global en
`platform_admins`, pero la sesión actual sigue exigiendo un tenant y una
membership. Además, `usuarios.rol_id` continúa siendo obligatorio y referencia
un rol tenant-owned. Por eso una identidad de plataforma no puede existir ni
autenticarse sin quedar ligada artificialmente a una academia.

El mismo datasource de aplicación posee hoy DML tanto sobre datos tenant como
sobre tablas del control plane. Esa configuración conserva RLS para el dominio,
pero no constituye una frontera suficiente ante una credencial runtime
comprometida. El aprovisionamiento tampoco tiene todavía un contrato de replay,
concurrencia y auditoría que permita administrarlo como una operación crítica.

Esta decisión define la separación mínima necesaria sin convertir Gestudio en
microservicios, sin crear una base por tenant y sin permitir que el control
plane se transforme en un bypass para leer datos funcionales.

La aceptación de este ADR no afirma que la implementación, las migraciones ni
los gates estén completos. Esos resultados requieren evidencia ejecutada sobre
el SHA que los contenga.

## Decisión

### 1. Se preserva el monolito modular, el esquema compartido y RLS

Gestudio continúa siendo un único artefacto Spring Boot y una única base
PostgreSQL compartida. Las capacidades de plataforma forman un módulo y una
frontera de seguridad dentro del monolito; no un servicio distribuido.

Las tablas tenant-owned mantienen:

1. `tenant_id NOT NULL`;
2. claves, unicidades y relaciones tenant-aware;
3. `TenantContext` obligatorio;
4. RLS `ENABLE` y `FORCE` para roles runtime sin ownership ni `BYPASSRLS`;
5. ausencia de acceso cross-tenant implícito, incluso para un administrador de
   plataforma.

Las consultas de metadata del control plane no abren `TenantContext`. Una
operación dirigida a un tenant lo abre sólo después de autorizar la identidad
de plataforma y únicamente durante la transacción que necesita tocar recursos
tenant-owned.

### 2. La identidad es global y puede ser exclusivamente de plataforma

`usuarios` permanece como identidad global. Una identidad válida puede tener:

- una o más memberships tenant;
- capacidad de plataforma;
- ambas;
- temporalmente ninguna, por ejemplo durante activación o recuperación.

`usuarios.rol_id` pasa a ser nullable y queda declarado como compatibilidad
legacy, no como fuente de autorización. `usuario_roles` también queda legacy y
deja de recibir escrituras desde los flujos productivos nuevos. La autorización
tenant continúa en `tenant_membership_roles`; la autorización de plataforma en
`platform_admins`.

No se crea un tenant técnico, ficticio ni oculto para alojar identidades de
plataforma. Tampoco se usa `tenant_id = NULL` como permiso especial.

### 3. Las sesiones tienen scope explícito y no son intercambiables

Cada access token y cada refresh session declara exactamente un scope:

- `TENANT`: requiere `tenant_id`, `membership_id`, versión de seguridad del
  tenant y versión de seguridad de la membership;
- `PLATFORM`: requiere identidad global activa, capacidad de plataforma activa
  y versión de seguridad de esa capacidad; prohíbe tenant y membership.

El claim de scope, el tipo de token y la audiencia forman parte de la
verificación criptográfica y semántica. Un token `TENANT` nunca satisface una
ruta `/api/platform/**`, aunque su membership tenga un rol llamado
`SUPERADMIN`. Un token `PLATFORM` nunca satisface rutas funcionales tenant.

Las refresh sessions tenant existentes conservan su tabla, columnas no nulas y
RLS. Las refresh sessions de plataforma se persisten en una tabla global
separada, con hash de token, familia, rotación, detección de reuse, expiración,
revocación y versiones de identidad/capacidad. También usan cookie, path y
audiencia separados. Esta separación evita debilitar la policy tenant o
interpretar un tenant ausente como bypass.

Durante una ventana de compatibilidad acotada, un token legacy sin claim de
scope sólo puede interpretarse como `TENANT` si contiene y revalida todos los
bindings tenant actuales. Nunca se infiere `PLATFORM`. La ventana termina con
una invalidación explícita documentada.

### 4. `PLATFORM_SUPERADMIN` es una autoridad global explícita

La autoridad `PLATFORM_SUPERADMIN` está respaldada exclusivamente por una fila
activa en `platform_admins`; no por un nombre de rol tenant. `platform_admins`
incorpora una versión de seguridad que se incrementa ante revocación,
reactivación o cambios de credenciales fuertes. La autorización se revalida en
cada request sensible y en cada refresh.

El rol tenant `ADMINISTRADOR` administra su academia dentro de las capacidades
funcionales concedidas. Los tenants nuevos reciben `ADMINISTRADOR` como rol
administrativo inicial. El nombre legacy tenant `SUPERADMIN` puede conservarse
durante la compatibilidad o normalizarse de forma forward-only, pero nunca
concede `PLATFORM_SUPERADMIN` ni crea una fila en `platform_admins`.

Conceder o revocar capacidad de plataforma es una operación global separada,
auditada y con step-up. Crear un tenant, una identidad o una membership tampoco
concede capacidad de plataforma como efecto lateral.

### 5. El control plane usa una frontera PostgreSQL dedicada

El DML global del control plane se retira del rol grupo `gestudio_app`. Se crea
un rol/datasource dedicado de plataforma con estas propiedades:

- `LOGIN` mediante una credencial externa distinta y miembro de un rol grupo
  de plataforma;
- `NOSUPERUSER`, `NOBYPASSRLS`, sin ownership, `CREATEDB` ni `CREATEROLE`;
- DML mínimo sobre control plane y sesiones de plataforma;
- lectura mínima de identidad y catálogo de permisos;
- DML sólo sobre las tablas tenant-owned necesarias para aprovisionar roles,
  ejecutado con target `TenantContext` y sujeto a RLS;
- ningún grant general de lectura sobre alumnos, finanzas, archivos, reportes u
  otra información funcional tenant.

El datasource de plataforma tiene su propio transaction manager. Una operación
de provisioning usa exclusivamente ese datasource para mantener una sola
transacción PostgreSQL; no mezcla dos datasources ni depende de XA.

`gestudio_app` conserva únicamente las lecturas globales mínimas necesarias
para autenticar una identidad y resolver sus propias memberships. Si la
administración tenant necesita modificar memberships, lo hace mediante una
operación estrecha limitada al tenant actual; no mediante DML global abierto.

Flyway mantiene un tercer rol operativo separado. Ninguno de los dos roles
runtime ejecuta migraciones.

### 6. El provisioning es atómico, idempotente y seguro ante concurrencia

Crear un tenant es un único caso de uso transaccional que incluye:

1. reservar el código normalizado del tenant;
2. crear tenant y estado inicial;
3. materializar los roles base y su matriz de permisos dentro del tenant;
4. crear una identidad nueva o asociar una identidad global existente;
5. crear la membership inicial con rol tenant `ADMINISTRADOR`;
6. persistir resultado e idempotencia;
7. registrar auditoría de éxito o rechazo.

El request exige una idempotency key y un hash canónico del payload. Una unique
constraint por operación/key y un lock determinista serializan requests
concurrentes. Un replay con el mismo hash devuelve el mismo resultado; la misma
key con otro payload devuelve conflicto. La unique de código sigue siendo la
garantía final ante carreras entre keys distintas.

La transacción no envía email, genera archivos ni realiza otros efectos
externos. Esos efectos se disparan after-commit y también son idempotentes. Una
falla intermedia no puede dejar tenant sin roles, membership parcial ni
capacidad de plataforma accidental.

Las transiciones de lifecycle y las revocaciones bloquean la fila objetivo,
incrementan security versions y protegen al último `ADMINISTRADOR` tenant y al
último `PLATFORM_SUPERADMIN` recuperable según una política explícita.

### 7. V12 preserva upgrades y B12 define el fresh sin seed

V1-V11 permanecen inmutables.

`V12` es la migración forward para instalaciones existentes. Debe:

- agregar el scope y persistencia de sesión de plataforma;
- hacer nullable el vínculo legacy `usuarios.rol_id` sin perder asignaciones;
- incorporar versionado, MFA, step-up, idempotencia y auditoría de plataforma;
- persistir activaciones por hash y purpose, conservando las consumidas y
  permitiendo como máximo una activación vigente por identidad;
- crear roles/grants/policies mínimos para el datasource de plataforma;
- reemplazar health y funciones que hoy exigen el tenant inicial o una
  membership por usuario;
- conservar tenants, usuarios, memberships, roles, datos e historia reales;
- no borrar, renombrar ni reasignar `academia-inicial`, incluso si parece vacía:
  un upgrade no puede demostrar de forma suficiente que nunca fue adoptada;
- fallar con diagnóstico ante invariantes inconsistentes, sin usar la
  migración para reconciliar decisiones de negocio ambiguas.

`B12` es la baseline para bases nuevas. Debe representar directamente el
esquema final de V12 y terminar con:

- cero tenants de negocio;
- cero usuarios;
- cero memberships;
- cero platform admins;
- cero datos demo o financieros;
- catálogo técnico global permitido, pero ningún rol tenant hasta provisioning.

Las pruebas comparan estructura, constraints, policies, grants y estado final
entre `V1 -> V12`, upgrade soportado `V11 -> V12` y `B12 fresh`. Una baseline no
se acepta por aplicar: debe ser equivalente al esquema upgradeado, salvo las
diferencias de datos explícitamente esperadas.

### 8. El bootstrap inicial es externo, one-shot y revocable

El primer `PLATFORM_SUPERADMIN` se crea mediante un comando operativo externo y
explícito, no mediante una migración Flyway ni durante el arranque ordinario. El
comando levanta un job one-shot aislado que habilita exclusivamente para ese
proceso un `ApplicationRunner` condicionado por configuración. El servicio
normal conserva el bootstrap deshabilitado.

El comando:

- está deshabilitado por defecto y fuera del flujo normal de deploy;
- recibe secretos por un canal externo seguro, sin valores por defecto;
- reclama una ejecución one-shot de forma transaccional e idempotente;
- crea identidad global y capacidad de plataforma, sin tenant, rol tenant ni
  membership;
- aprovisiona y verifica TOTP, genera los recovery codes y vincula el claim en
  la misma transacción de plataforma que crea la identidad y su capacidad; un
  fallo al persistir el artefacto one-shot de recovery revierte la operación;
- no imprime contraseña, seed MFA, recovery codes ni tokens;
- registra actor operativo, correlación y resultado sin secretos.

Después del commit, el comando verifica el estado persistido y copia los
recovery codes desde el job a un archivo local con ACL restringida. Ese copiado
es una fase operativa posterior: si falla, no se repite el bootstrap; se usa el
modo de recuperación del mismo job documentado en el
[runbook operativo](../operations/platform-control-plane-runbook.md#recuperación-del-job-de-bootstrap).

La capacidad se revoca desactivando `platform_admins`, incrementando su versión
de seguridad y revocando todas sus familias refresh. La cuenta bootstrap no es
una excepción permanente a MFA ni a auditoría.

### 9. MFA y step-up son controles obligatorios

Toda sesión de plataforma requiere MFA real. Se admite TOTP o WebAuthn mediante
una implementación mantenida y testeada; una confirmación UI, un header o una
contraseña repetida sin segundo factor no cuentan como MFA.

Estas operaciones exigen además step-up reciente y de un solo propósito:

- crear, suspender, archivar o reactivar un tenant;
- conceder o revocar `PLATFORM_SUPERADMIN`;
- cambiar MFA o recuperar una identidad privilegiada;
- crear o reemplazar al administrador inicial de un tenant;
- ejecutar acciones masivas o exportaciones futuras de plataforma.

Los desafíos expiran, no son reutilizables y quedan ligados a usuario, sesión,
acción y target. Los secretos MFA se cifran en reposo; recovery codes se
almacenan hasheados, se muestran una sola vez y se consumen de forma atómica.
Nunca se registran en logs ni auditoría.

### 10. La auditoría de plataforma es consultable y correlacionada

Cada acción y rechazo de plataforma registra, como mínimo:

- `actor_usuario_id` y snapshot seguro;
- `actor_type` (`PLATFORM`, `TENANT`, `SYSTEM` o `BOOTSTRAP`);
- scope de sesión y método MFA/step-up sin material secreto;
- acción y tipo/id de target;
- tenant objetivo cuando aplica;
- timestamp UTC;
- correlation ID canónico del request o job;
- idempotency key cuando aplica;
- resultado explícito;
- metadata de origen permitida y minimizada.

El filtro HTTP produce un UUID de correlación canónico, lo devuelve al cliente
y lo propaga hasta `AuditService`. Un identificador externo no UUID puede
conservarse como metadata validada, pero no sustituye el ID interno.

Los eventos siguen siendo append-only. El API de consulta usa el datasource de
plataforma, paginación, filtros acotados y permiso `PLATFORM_SUPERADMIN`; no
expone secretos, payloads completos ni datos funcionales tenant. La lectura de
auditoría global se resuelve con grants/policies explícitos, nunca interpretando
`tenant_id NULL` como bypass RLS.

## Invariantes obligatorios

1. Una identidad platform-only puede autenticarse con cero tenants y cero
   memberships.
2. Un tenant puede existir y operar sin ningún platform admin asociado como
   membership.
3. `PLATFORM_SUPERADMIN` no implica membership ni lectura de datos de negocio.
4. `ADMINISTRADOR` o el legacy tenant `SUPERADMIN` nunca implican capacidad de
   plataforma.
5. Token, refresh cookie y sesión de un scope son inválidos en el otro scope.
6. Una request `PLATFORM` sin operación tenant dirigida no establece
   `TenantContext`.
7. Una operación dirigida sólo establece el target autorizado durante su
   transacción y sigue sujeta a RLS.
8. Ningún runtime es owner, superuser ni `BYPASSRLS`.
9. `gestudio_app` no posee DML global de plataforma.
10. Provisioning repetido o concurrente produce un solo agregado coherente.
11. Suspensión, revocación y cambios de seguridad invalidan access y refresh sin
    esperar su expiración natural.
12. Un fresh B12 no deja tenants, identidades, memberships, credenciales ni
    datos de ejemplo.
13. V12 no borra ni reasigna datos existentes ambiguos.
14. Toda acción privilegiada produce auditoría de éxito o rechazo con la misma
    correlación del request.
15. MFA, recovery codes, contraseñas, tokens y credenciales DB nunca se loguean
    ni se copian a auditoría.

## Compatibilidad y rollout

El rollout se realiza en fases verificables:

1. publicar V12/B12 y validar equivalencia fresh/upgrade antes de activar el
   nuevo código;
2. aprovisionar el rol y la credencial de plataforma fuera de Git y verificar
   sus atributos/grants con consultas de catálogo;
3. desplegar doble validación de scope manteniendo los tokens existentes como
   `TENANT` durante la ventana acotada;
4. dejar de escribir `usuarios.rol_id` y `usuario_roles` en flujos nuevos, sin
   eliminar todavía las columnas ni relaciones legacy;
5. migrar filas existentes de `platform_admins` conservando su estado y exigir
   enrolamiento MFA antes de emitir una sesión `PLATFORM`;
6. habilitar login, refresh, API y UI de plataforma;
7. mantener el runner condicional aislado dentro del job externo one-shot y el
   bootstrap deshabilitado en todo arranque ordinario;
8. revocar los grants globales de `gestudio_app` sólo después de que todos los
   paths productivos usen la frontera correcta;
9. invalidar tokens legacy al cerrar la ventana y retirar código transitorio;
10. certificar backup/restore, observabilidad, auditoría y rollback sobre el SHA
    definitivo.

La membresía y los tokens tenant existentes siguen funcionando durante la
compatibilidad si satisfacen las validaciones actuales. La transición no cambia
montos, pagos, recibos ni otra historia funcional. La eliminación definitiva de
los campos legacy requiere un ADR o una migración posterior después de probar
que no tienen lectores ni writers productivos.

El rollback de código conserva V12 porque Flyway es forward-only. Se vuelve al
último artefacto compatible con V12 o se restaura un backup completo; no se
ejecuta un down migration ni se reescriben V1-V11.

## Alternativas evaluadas y rechazadas

### Usar un tenant de plataforma ficticio

Se rechaza porque mezcla identidad global con datos tenant, obliga memberships
artificiales y convierte el tenant seleccionado en una autoridad accidental.

### Tratar `tenant_id NULL` como acceso global

Se rechaza porque crea un bypass difícil de auditar y permite que errores de
contexto se conviertan en privilegio. La ausencia de contexto tenant sigue
fallando cerrado.

### Promover el rol tenant `SUPERADMIN`

Se rechaza porque un nombre local no constituye autoridad global. También
permitiría que administradores de academia escalen al control plane.

### Usar el mismo token y refresh con claims opcionales

Se rechaza porque aumenta la confusión de deputy, facilita sustitución entre
audiencias y obligaría a relajar las invariantes no nulas/RLS de sesiones
tenant.

### Mantener DML global en `gestudio_app` y confiar sólo en servicios Java

Se rechaza frente al threat model de credencial runtime comprometida, native
query defectuosa o endpoint mal autorizado. La separación de datasource es una
frontera real y justifica la credencial adicional.

### Dar `BYPASSRLS` al datasource de plataforma

Se rechaza. El control plane administra metadata y abre un tenant objetivo de
forma estrecha; no necesita lectura irrestricta del dominio.

### Reescribir V1-V11 o borrar el tenant inicial durante un upgrade

Se rechaza por romper checksums y por riesgo de pérdida en deployments que ya
adoptaron ese tenant. Ni siquiera un tenant aparentemente vacío prueba que no
sea una identidad operativa reservada o utilizada fuera de las tablas
inspeccionadas. V12 preserva todas las filas; B12 es el único camino que
resuelve el fresh sin semilla.

### Crear el primer administrador mediante seed o arranque normal

Se rechaza porque introduce credenciales y efectos productivos en migraciones o
deploys repetibles. El bootstrap es una ceremonia operativa explícita.

### Sustituir MFA por TTL corto o allowlist de red

Se rechaza porque ninguno prueba posesión de un segundo factor. Esos controles
pueden complementar MFA, no reemplazarlo.

### Separar el control plane en microservicio o base independiente

Se rechaza por complejidad operativa y transaccional no justificada. La frontera
de módulo, security chain, datasource y rol PostgreSQL dedicado es suficiente
para el alcance actual y puede extraerse en el futuro si aparece una necesidad
regulatoria o de escala demostrable.

## Riesgos y mitigaciones

- **Drift entre V12 y B12:** comparación automatizada de catálogo, constraints,
  grants, policies y estado fresh en PostgreSQL real.
- **Transacción partida por dos datasources:** provisioning usa sólo el
  datasource de plataforma dentro de una transacción; no se incorpora XA.
- **Confusión de token/cookie:** audiencia, scope, path, nombre de cookie y
  verificadores separados, con pruebas de sustitución negativas.
- **Escalada por grants:** auditoría de ACL, owners y atributos de roles en CI,
  restore y readiness; ningún wildcard futuro se acepta sin revisión.
- **Bloqueo del último administrador:** locks, conteo dentro de transacción,
  recovery runbook probado y alertas.
- **Pérdida de acceso por MFA:** recovery codes one-shot, revocación auditada y
  ceremonia break-glass fuera del flujo ordinario.
- **PII o secretos en auditoría:** allowlist de campos, snapshots mínimos,
  validación recursiva y tests negativos.
- **Adopción real de la semilla histórica:** V12 preserva siempre el tenant y
  toda fila histórica; la ausencia de seed se demuestra exclusivamente sobre
  una base vacía construida con B12.
- **Identidad compartida entre tenants:** credenciales y estado global sólo se
  modifican desde flujos de identidad autorizados; un administrador tenant
  administra su membership, no la contraseña global.
- **Lectura accidental de dominio desde plataforma:** ausencia de grants,
  security chain separada, falta de `TenantContext` por defecto y pruebas RLS
  negativas con dos tenants.

## Evidencia requerida para considerar implementada la decisión

Como mínimo deben pasar sobre el mismo SHA definitivo:

- migración `V11 -> V12`, `V1 -> V12` y baseline B12 fresh;
- reconciliación que pruebe cero seeds en fresh y preservación de upgrade;
- catálogo PostgreSQL de roles, owners, grants, RLS y ausencia de
  `SUPERUSER`/`BYPASSRLS`;
- autenticación, refresh, rotación, reuse y revocación para ambos scopes;
- matriz completa que niegue token tenant en plataforma y token plataforma en
  dominio;
- platform-only login sin membership y login tenant sin capacidad plataforma;
- provisioning concurrente, replay igual y conflicto por payload distinto;
- suspensión/reactivación, último administrador y revocación inmediata;
- MFA, step-up, recovery y pruebas negativas;
- auditoría consultable, correlación end-to-end y ausencia de secretos;
- aislamiento de native queries, jobs, archivos y reportes con dos tenants;
- backup/restore con ACLs y smoke posterior;
- backend `clean verify`, frontend lint/test/build y Quality Fortress completa.

Hasta que esa evidencia exista, este ADR se mantiene `ACCEPTED` pero su estado
de implementación continúa `PLANNED` o, durante el desarrollo,
`IMPLEMENTED_NOT_RUN`.

El detalle de amenazas, controles y evidencia pendiente se mantiene en el
[threat model](threat-model-platform-control-plane.md); la ceremonia de acceso,
bootstrap, recuperación e incidentes se mantiene en el
[runbook del control plane](../operations/platform-control-plane-runbook.md).
