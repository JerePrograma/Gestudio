# GESTUDIO — FINALIZACIÓN PRODUCTIVA, BACKOFFICE SUPERADMIN Y QUALITY FORTRESS

> **Contrato operativo y autorreferencia para Codex**
>
> Este documento es el megaprompt maestro para llevar Gestudio desde su estado real actual hasta una release de producción verificablemente cerrada. No reemplaza la inspección del repositorio: la exige. Todos los SHA, cantidades de tests, versiones Flyway, workflows, nombres de recursos Docker y resultados históricos aquí mencionados deben tratarse como **contexto histórico no confiable** hasta ser revalidados sobre `main` y `origin/main`.

---

# 0. MISIÓN

Trabajá directamente sobre el repositorio real de **Gestudio**, en:

- rama local obligatoria: `main`;
- rama remota obligatoria: `origin/main`.

No crees ramas nuevas salvo orden expresa.

La misión es cerrar Gestudio como producto de producción mediante evidencia técnica reproducible, incorporando además:

1. un **control plane / backoffice visual de plataforma** para `SUPERADMIN`;
2. provisioning seguro de tenants, administradores, memberships, roles y permisos;
3. ciclo de vida de tenants;
4. auditoría íntegra de operaciones privilegiadas;
5. una estrategia de migraciones Flyway limpia para instalaciones nuevas;
6. producción **sin seed funcional**;
7. bootstrap explícito y seguro del primer `SUPERADMIN`;
8. reconstrucción clean-room desde una DB vacía;
9. compatibilidad de upgrade desde instalaciones históricas soportadas;
10. una **Quality Fortress** que haga depender la confianza de pruebas, restricciones, mutation testing, coverage, análisis automático y gates ejecutados, no de revisión manual del código generado.

La misión no termina cuando “compile”, “funcione”, “la pantalla esté hecha”, “el happy path pase” o “Codex considere correcto el código”.

La misión termina únicamente cuando una release concreta tenga evidencia suficiente para ser clasificada `PASS` en la matriz de Release Readiness de este documento.

---

# 1. PRINCIPIO DE CONFIANZA

Aplicá esta regla como contrato de ingeniería:

> **La revisión manual no es el gate primario de confianza.**
>
> Cada comportamiento crítico modificado o agregado debe quedar protegido por restricciones independientes y ejecutables que intenten demostrar que el código está equivocado.

Por tanto:

- no aceptes un cambio únicamente porque el código “parezca correcto”;
- no aceptes cobertura como sinónimo de calidad;
- no aceptes tests que sólo ejerciten happy paths;
- no aceptes Gherkin decorativo sin runner;
- no aceptes mutation testing decorativo sin threshold;
- no aceptes RLS “por inspección”;
- no aceptes una migración clean-room sin ejecutar PostgreSQL real;
- no aceptes idempotencia de deploy por lectura de scripts;
- no aceptes CI local como sustituto de GitHub Actions sobre el SHA publicado;
- no aceptes “seguridad” sin pruebas negativas y adversariales;
- no bajes thresholds, desactives reglas, ignores warnings relevantes ni marques `N/A` para obtener verde.

Si un gate falla, investigá la causa raíz. Corregí el defecto o justificá técnicamente por qué el gate es incorrecto. No silencies el síntoma.

---

# 2. CONTEXTO HISTÓRICO — NO ASUMIR COMO ESTADO ACTUAL

El historial aportado indica que Gestudio ya atravesó trabajo significativo sobre:

- multitenancy;
- PostgreSQL RLS;
- separación entre usuario migrador y usuario runtime;
- Flyway;
- backup/restore;
- ACLs y grants;
- CI;
- GitHub Actions;
- `deploy.cmd`;
- motor PowerShell;
- despliegue idempotente;
- persistencia de secretos;
- fingerprint de despliegue;
- `--dry-run`;
- `--verify-only`;
- exclusión mutua;
- ruta con espacios;
- Docker inaccesible;
- upgrade controlado;
- preservación de volúmenes;
- health checks;
- demo remota protegida;
- auditorías de seguridad;
- seed demo idempotente;
- observabilidad;
- rollback;
- pruebas PostgreSQL reales.

Un estado histórico terminó informando el SHA:

`53547baac50063de85fb694124241d9f58e256a1`

y seis workflows remotos en `success`.

**No asumas que ese SHA sigue siendo HEAD.**
**No asumas que esos workflows siguen siendo los actuales.**
**No asumas que Flyway sigue en V11.**
**No asumas que el árbol actual está limpio.**
**No asumas que los conteos históricos de tests siguen vigentes.**

Reconstruí la verdad actual antes de editar.

---

# 3. FLUJO GIT OBLIGATORIO

Antes de modificar código ejecutá o comprobá el equivalente a:

```powershell
git status
git fetch origin
git checkout main
git pull --ff-only origin main
```

Además verificá:

```powershell
git rev-parse --show-toplevel
git branch --show-current
git remote -v
git rev-parse HEAD
git rev-parse origin/main
git status --short --branch
```

Confirmá:

- que el repositorio corresponde realmente a Gestudio;
- que la rama actual es `main`;
- que `origin/main` existe;
- que el `pull --ff-only` pudo realizarse;
- que el árbol no contiene cambios ajenos a la tarea;
- que no existe divergencia inesperada;
- que no hay rebase/merge/cherry-pick en progreso.

## STOP CONDITION

Si existe cualquiera de estas condiciones:

- cambios locales previos;
- archivos sin trackear ajenos;
- conflictos;
- repo incorrecto;
- rama incorrecta que no pueda corregirse limpiamente;
- `origin` inesperado;
- divergencia no explicada;
- `git pull --ff-only` imposible;
- operación Git en progreso;
- HEAD local con continuidad dudosa;

**detenete y explicá exactamente el problema.**

No sobrescribas, descartes, stashees, mezcles ni limpies automáticamente trabajo previo.

## Prohibido salvo orden expresa

- crear otra rama;
- crear worktrees alternativos;
- `git reset --hard`;
- `git clean -fd`;
- `git push --force`;
- `git push --force-with-lease`;
- `git commit --amend`;
- reescribir historial;
- borrar cambios ajenos;
- eliminar secretos o archivos reales de entorno del usuario;
- publicar credenciales;
- introducir refactors amplios no relacionados;
- agregar dependencias sin necesidad técnica clara y justificada.

---

# 4. AUTORREFERENCIA VIVA

Este archivo debe mantenerse versionado como contrato de la intervención.

Al inicio completá una sección de estado vivo con evidencia real.

## Estado vivo

```text
REPOSITORY=C:\laburo\Gestudio
BRANCH=main
HEAD=53547baac50063de85fb694124241d9f58e256a1
ORIGIN_MAIN=53547baac50063de85fb694124241d9f58e256a1
DIVERGENCE=0 ahead / 0 behind en los refs locales; fetch final pendiente antes de publicación
WORKTREE=DIRTY_TASK_OWNED: implementación control-plane, V12/B12, frontend, operación, CI y documentación en curso; staging vacío
FLYWAY_CURRENT=V1-V11 publicados permanecen inmutables; V12 forward-only y B12 fresh están presentes en el worktree, pero B12 cambió después de la última ejecución PostgreSQL focal; fresh, validate, equivalence, upgrade y backup/restore están NOT_EXECUTED sobre los bytes actuales
DOCKER_CONTEXT=desktop-linux configurado; daemon Linux inaccesible por named pipe el 2026-08-13; BLOCKED_ENVIRONMENT para PostgreSQL/Testcontainers, E2E runtime y drills operativos; no se intentó iniciar ni mutar Docker
PROTECTED_DEMO=estado actual NOT_EXECUTED por Docker inaccesible; sólo existe un último snapshot histórico healthy de gestudio-remote-demo; no iniciar, detener, recrear, inspeccionar datos ni mutar
CURRENT_PHASE=Fases 9-14, estabilización y reconciliación. Backend, frontend, Nginx y B12 cambiaron después de BackendStatic, FrontendCoverage, FrontendDiffCoverage, FrontendStatic, frontend build y la ejecución PostgreSQL focal; esos resultados quedan como evidencia histórica invalidada y requieren rerun. SupplyChain terminó exit 1: npm audit total/productivo, SBOM backend/frontend y política inmutable de Actions PASS; Dependency-Check backend no produjo reporte por 503 de RetireJS y errores de ingestión NVD, por lo que SupplyChain=FAIL y no evidencia vulnerabilidades. Los contratos estáticos actuales de E2E, rollback, bootstrap y reset efímero pasaron sin contactar Docker
BLOCKER=BLOCKED_ENVIRONMENT: Docker daemon no disponible para gates PostgreSQL y operativos; Dependency-Check backend bloqueado por datos externos/RetireJS 503. Quedan además reruns internos obligatorios sobre el árbol estabilizado: backend/frontend build, tests, coverage, static, authorization y diff-check. RELEASE_READINESS no puede pasar hasta ejecutar los gates sobre el SHA definitivo publicado
LAST_GREEN_GATE=Subgates SupplyChain verdes sobre el árbol actual: npm audit total y productivo 0 vulnerabilidades; SBOM CycloneDX backend y frontend verificados; política GitHub Actions PASS. El scope agregado FAIL por Dependency-Check backend sin análisis
NEXT_EXACT_COMMAND=Push-Location backend; try { .\mvnw.cmd -B -ntp '-Dtest=*Test,!*PostgreSqlTest,!PostgreSqlIntegrationTest,!QualityFortressBddTest' clean test } finally { Pop-Location }
RELEASE_READINESS=PARTIAL
```

Actualizá esta sección:

- al cerrar cada fase;
- antes de cualquier compactación de contexto;
- después de cualquier fallo relevante;
- después de cada commit;
- después de cada push;
- cuando cambie el SHA candidato a release.

Nunca registres secretos, contraseñas, tokens ni connection strings sensibles.

---

# 5. INSPECCIÓN OBLIGATORIA ANTES DE DISEÑAR

No inventes rutas, clases, métodos, componentes, endpoints, roles, migraciones ni dependencias.

Primero inspeccioná el repositorio real.

Localizá como mínimo:

- backend;
- frontend;
- `pom.xml` / Maven wrapper;
- `package.json`;
- lockfile;
- Dockerfiles;
- Compose;
- Flyway;
- configuración Spring;
- seguridad/autenticación;
- JWT/sesiones/refresh;
- tenant context;
- entities;
- repositories;
- native queries;
- jobs;
- archivos;
- reportes;
- auditoría;
- health/readiness/liveness;
- observabilidad;
- scripts de backup/restore;
- `deploy.cmd`;
- scripts PowerShell;
- tests de idempotencia;
- tests multitenant;
- workflows GitHub;
- documentación arquitectónica;
- documentación de despliegue;
- seed/demo fixtures;
- scripts de bootstrap;
- pruebas E2E si existen;
- scanners;
- configuración de coverage;
- configuración de mutation testing si existe.

Determiná los **comandos reales** definidos por el proyecto. No inventes `verify.cmd`, scripts o perfiles si no existen.

---

# 6. AUDITORÍA DE ARQUITECTURA MULTITENANT

Antes de agregar el backoffice, reconstruí el modelo actual.

Documentá con rutas y símbolos reales:

- entidad/tabla tenant;
- memberships;
- users/identities;
- roles;
- permissions;
- asociación user ↔ tenant;
- tenant resolution;
- tenant context;
- propagación de tenant en HTTP;
- propagación de tenant en jobs;
- tenant en archivos/objetos;
- tenant en reportes;
- tenant en native queries;
- tenant en repositorios;
- RLS;
- policies;
- `FORCE ROW LEVEL SECURITY` si existe;
- grants;
- usuario migrador;
- usuario runtime;
- privilegios efectivos;
- uso de `SUPERUSER`;
- uso de `BYPASSRLS`;
- owner de tablas;
- rutas administrativas tenant;
- endpoints globales existentes.

Construí un inventario de tablas y clasificá cada una:

```text
TENANT_SCOPED
PLATFORM_SCOPED
REFERENCE
TECHNICAL
AUDIT
AUTH
UNKNOWN
```

Toda tabla `UNKNOWN` debe resolverse antes de declarar aislamiento certificado.

---

# 7. ARQUITECTURA DEL CONTROL PLANE

La nueva capa debe ser un **control plane de plataforma**, no un “admin de todos los tenants”.

Diferenciá explícitamente:

```text
PLATFORM SCOPE
TENANT SCOPE
```

## Platform scope

Debe existir un rol de aplicación equivalente a:

```text
PLATFORM_SUPERADMIN
```

Usá el nombre real que mejor encaje con las convenciones existentes. No renombres contratos preexistentes sin necesidad.

Autoridad esperada:

- crear tenant;
- consultar tenants;
- ver metadata operativa de tenants;
- activar;
- suspender/desactivar;
- reactivar;
- crear o asociar identidad administradora;
- crear membership;
- asignar roles tenant;
- revocar membership;
- administrar configuración del control plane;
- consultar auditoría del control plane;
- ejecutar operaciones de soporte estrictamente autorizadas.

## Tenant scope

Conservá los roles tenant existentes.

Un `TENANT_ADMIN` no puede heredar capacidades de plataforma.

## Regla estructural

El `PLATFORM_SUPERADMIN`:

- puede existir sin membership en tenant;
- no debe requerir un “tenant especial” falso;
- no debe usar `tenant_id = NULL` como bypass genérico;
- no debe ser un `ADMIN` aplicado a todos los tenants;
- no debe recibir acceso automático a datos funcionales de todas las escuelas.

---

# 8. SUPERADMIN NO ES POSTGRESQL SUPERUSER

No conviertas el rol de aplicación `PLATFORM_SUPERADMIN` en:

- PostgreSQL `SUPERUSER`;
- rol con `BYPASSRLS`;
- owner universal que evita políticas sin control;
- usuario migrador;
- credencial de administración de infraestructura.

El runtime debe seguir siendo:

```text
NOSUPERUSER
NOBYPASSRLS
```

Si la arquitectura requiere un runtime adicional para control plane, debe:

- tener mínimo privilegio;
- acceder sólo a tablas y operaciones necesarias;
- no leer por defecto alumnos, pagos, profesores, clases u otros datos tenant-scoped;
- estar protegido por grants y policies explícitas;
- quedar probado en PostgreSQL real.

Preferí reutilizar el runtime existente si la separación lógica y RLS permiten hacerlo sin abrir un bypass global.

No introduzcas otra credencial DB si no aporta una frontera real de seguridad.

---

# 9. BACKOFFICE VISUAL OBLIGATORIO

Implementá una capa visual coherente con el frontend existente.

No inventes un segundo framework ni una aplicación paralela salvo que el repositorio ya tenga separación equivalente.

El backoffice debe permitir al menos:

## Tenants

- listar;
- buscar;
- filtrar;
- crear;
- ver detalle;
- editar sólo campos permitidos;
- activar;
- suspender/desactivar;
- reactivar;
- mostrar estado;
- mostrar fecha de creación;
- mostrar metadata operativa útil;
- impedir acciones inconsistentes.

Ejemplo de caso real:

```text
Nombre visible: Escuela Danza Marcos Paz
```

No hardcodees ese tenant.

## Administradores del tenant

Desde el tenant, el SUPERADMIN debe poder:

- crear una identidad nueva o asociar una existente;
- asignarla al tenant;
- crear membership;
- asignar roles;
- revocar roles;
- revocar membership;
- visualizar estado;
- manejar invitación/activación si esa arquitectura ya existe.

## UX mínima

Toda pantalla debe contemplar:

- loading;
- empty;
- error;
- retry donde corresponda;
- validación cliente;
- validación servidor;
- confirmación de operaciones críticas;
- mensajes sin filtrar secretos;
- errores de concurrencia;
- estados suspendidos;
- navegación por teclado;
- foco visible;
- labels;
- feedback accesible.

No confíes en esconder botones como control de seguridad.

---

# 10. API / SERVICIOS DEL CONTROL PLANE

Después de inspeccionar patrones existentes, implementá el cambio mínimo.

Los endpoints reales deben seguir convenciones actuales.

No asumas rutas como `/api/platform/**` si no encajan con el proyecto, pero mantené una frontera explícita y auditable.

Para cada operación privilegiada:

- autenticación obligatoria;
- autorización server-side;
- validación de DTO;
- lista explícita de campos mutables;
- protección contra mass assignment;
- reglas de dominio;
- transacción;
- idempotencia donde aplique;
- constraint DB;
- manejo de concurrencia;
- auditoría;
- código HTTP consistente;
- error seguro;
- correlation/request ID.

Revisá todos los consumidores de cualquier contrato modificado.

---

# 11. PROVISIONING TRANSACCIONAL DE TENANT

El flujo de alta debe ser determinista y transaccional.

Objetivo funcional mínimo:

```text
SUPERADMIN
  -> crea tenant
  -> crea/reutiliza identidad administradora
  -> crea membership
  -> asigna roles tenant
  -> audita
  -> devuelve estado consistente
```

No dejes un tenant “a medio crear”.

Si falla una etapa crítica:

- rollback de la transacción;
- no duplicar;
- no dejar membership huérfana;
- no dejar asignaciones parciales;
- no crear credenciales demo;
- no registrar `success` en auditoría.

Cuando existan integraciones externas no transaccionales, diseñá compensación o estado explícito, siguiendo patrones existentes.

---

# 12. IDEMPOTENCIA Y CONCURRENCIA DEL PROVISIONING

La creación repetida o concurrente no debe producir:

- tenants duplicados;
- usuarios duplicados;
- memberships duplicadas;
- roles duplicados;
- invitaciones duplicadas;
- auditorías contradictorias.

Usá:

- constraints reales;
- claves naturales o identificadores deterministas cuando corresponda;
- unique indexes;
- locking/versionado optimista/pesimista según patrón real;
- transacciones;
- retries sólo donde sean seguros.

No “resuelvas” duplicación capturando excepciones genéricas.

Agregá pruebas de dos requests simultáneas y replay.

---

# 13. CICLO DE VIDA DEL TENANT

Definí estados usando el modelo real del dominio.

Como mínimo evaluá:

```text
ACTIVE
SUSPENDED / INACTIVE
```

No inventes estados si no aportan semántica real.

La suspensión debe tener comportamiento definido y probado:

- login;
- refresh token;
- requests existentes;
- jobs;
- webhooks;
- archivos;
- reportes;
- operaciones financieras;
- administración;
- reactivación.

Una suspensión no debe destruir datos.

Una desactivación no debe equivaler a `DELETE CASCADE` salvo requisito explícito y probado.

---

# 14. BOOTSTRAP DEL PRIMER SUPERADMIN

La producción fresh debe quedar sin tenant de demo y sin usuario funcional precargado.

El primer SUPERADMIN no debe ser seed.

Diseñá, luego de inspeccionar la seguridad existente, un mecanismo explícito one-time.

Puede ser, si encaja con la arquitectura:

- comando CLI;
- script administrativo protegido;
- endpoint temporal one-time no expuesto públicamente;
- flujo manual operacional documentado.

Requisitos:

- no hardcodear credenciales;
- no almacenar password default en Git;
- no imprimir secretos;
- exigir password fuerte o mecanismo de activación;
- registrar creación;
- ser idempotente;
- negarse a crear un segundo bootstrap cuando la plataforma ya está inicializada salvo modo explícito;
- producir exit code no cero ante error;
- quedar fuera del deploy ordinario;
- quedar documentado;
- quedar testeado.

Si existe MFA, exigí enrolamiento en el primer acceso o durante bootstrap.

Si no existe MFA y el modelo actual permite agregarlo sin romper arquitectura, priorizalo para `PLATFORM_SUPERADMIN`.

---

# 15. MFA / STEP-UP / REAUTENTICACIÓN

Para acciones críticas del control plane, evaluá e implementá la protección compatible con el sistema real.

Acciones candidatas:

- crear SUPERADMIN;
- cambiar roles de plataforma;
- suspender tenant;
- reactivar tenant;
- revocar último administrador;
- cambiar email/identidad sensible;
- resetear MFA;
- ejecutar soporte cross-tenant;
- eliminar o anonimizar datos.

Preferencias:

- MFA obligatorio para SUPERADMIN;
- step-up o reautenticación para acciones críticas;
- sesión con expiración razonable;
- revocación de sesiones tras cambios de seguridad;
- auditoría de éxito y rechazo;
- recuperación de MFA protegida.

No agregues un sistema de auth paralelo si el actual puede extenderse.

---

# 16. THREAT MODEL DEL BACKOFFICE

Creá o actualizá documentación de threat model.

Cubrir como mínimo:

```text
tenant -> platform privilege escalation
cross-tenant IDOR
tenant context injection
header manipulation
JWT claim manipulation
mass assignment
CSRF
XSS
stored XSS in tenant names / user names
session theft
refresh token abuse
MFA bypass
MFA recovery abuse
role escalation
duplicate provisioning
replay
race conditions
audit tampering
log injection
credential leakage
seed credential leakage
migration privilege abuse
backup leakage
supply-chain compromise
misconfigured CORS
open redirect
enumeration of users/tenants
authorization bypass by direct DB access
```

Para cada amenaza indicá:

- asset;
- actor;
- attack path;
- impacto;
- control preventivo;
- control detective;
- test automatizado;
- riesgo residual.

No declares “mitigado” sin evidencia.

---

# 17. MATRIZ DE AUTORIZACIÓN

Construí una matriz ejecutable.

Para toda operación de plataforma:

```text
anonymous               -> DENY
usuario autenticado     -> DENY
tenant user Alpha       -> DENY
tenant admin Alpha      -> DENY
tenant admin Beta       -> DENY
platform role incorrecto-> DENY
PLATFORM_SUPERADMIN     -> ALLOW según permiso
```

Para recursos tenant-scoped:

```text
Alpha -> recurso Alpha          -> ALLOW según permiso
Alpha -> recurso Beta           -> DENY
Beta  -> recurso Alpha          -> DENY
ID manipulado                   -> DENY
tenant header manipulado        -> DENY
claim manipulado                -> DENY
membership revocada             -> DENY
tenant suspendido               -> DENY según política
```

Ejecutá la matriz:

- a nivel HTTP;
- a nivel service cuando sea relevante;
- a nivel PostgreSQL cuando RLS sea la barrera final.

No confíes únicamente en filtros Hibernate.

---

# 18. AUDITORÍA DEL CONTROL PLANE

Toda acción privilegiada debe registrar un evento auditable.

Mínimo:

```text
actor
actor_type
action
target_type
target_id
tenant_id cuando corresponda
timestamp UTC
request/correlation id
result
source metadata segura
```

No incluir:

- password;
- token;
- JWT completo;
- secret;
- headers de autorización;
- contenido sensible innecesario.

La auditoría debe ser:

- append-oriented;
- difícil de alterar desde el flujo normal;
- consultable por SUPERADMIN;
- tenant-aware cuando corresponda;
- testeada contra manipulación;
- correlacionable con logs.

Si existe infraestructura de auditoría, reutilizala.

---

# 19. MIGRACIONES — OBJETIVO PRODUCTIVO

El objetivo correcto no es “borrar el historial porque se ve feo”.

El objetivo es:

> Una instalación nueva, partiendo de una DB realmente vacía, debe poder ejecutar Flyway una sola vez y terminar en el esquema productivo actual, sin seed funcional, con constraints, indexes, grants, roles técnicos, RLS, policies, funciones y reference data imprescindible.

Y en paralelo:

> Una instalación histórica soportada debe poder actualizarse sin perder datos, grants, ACLs, RLS ni integridad.

---

# 20. NO EDITAR MIGRACIONES HISTÓRICAS A CIEGAS

Primero determiná:

- qué migraciones existen;
- cuáles fueron publicadas;
- si existen ambientes que pudieron aplicarlas;
- si sus checksums deben seguir siendo válidos;
- qué estrategia soporta la versión real de Flyway.

Por defecto:

- no edites `V1..VN` ya publicadas;
- no renombres;
- no reordenes;
- no cambies checksum;
- no uses `repair` automáticamente;
- no borres `flyway_schema_history`.

Si se demuestra documentalmente que ninguna instalación real depende del historial, una reconstrucción greenfield podría ser válida, pero esa decisión debe quedar explícita, probada y documentada.

---

# 21. BASELINE / SQUASH PARA INSTALACIONES NUEVAS

Si el stack real lo soporta y existen instalaciones históricas que preservar, preferí una estrategia compatible con **Flyway Baseline Migration** equivalente a:

```text
B<N>__gestudio_production_baseline.sql
```

donde `<N>` es la versión real verificada.

No inventes `N`.

La instalación histórica conserva:

```text
V1 -> V2 -> ... -> VN -> V(N+1)...
```

La instalación nueva debe poder converger por baseline según el comportamiento real de la versión Flyway usada.

Antes de implementar, comprobá documentación/versión instalada.

No actives `baselineOnMigrate` de forma insegura para “hacerlo funcionar”.

---

# 22. EQUIVALENCIA DE MIGRACIONES

Creá un gate automatizado que compare:

## DB A

Construida desde la cadena histórica soportada.

## DB B

Construida desde la estrategia fresh/baseline.

Compará como mínimo:

- schemas;
- tablas;
- columnas;
- tipos;
- nullability;
- defaults;
- PK;
- FK;
- unique constraints;
- check constraints;
- indexes;
- sequences;
- views;
- triggers;
- functions;
- owners;
- grants;
- ACLs;
- RLS enabled;
- RLS forced;
- policies;
- policy expressions;
- roles técnicos relevantes;
- privilegios del runtime.

La equivalencia no debe depender de dumps textuales frágiles si puede compararse metadata normalizada.

Si existen diferencias intencionales, documentalas y probalas.

---

# 23. PRODUCCIÓN SIN SEED FUNCIONAL

Auditá todo SQL/Java/PowerShell/Compose que inserte datos.

Clasificá cada inserción:

```text
REFERENCE_REQUIRED
BOOTSTRAP
DEMO
TEST_FIXTURE
MIGRATION_BACKFILL
OBSOLETE
```

Producción fresh debe tener:

```text
tenants de negocio        = 0
usuarios funcionales      = 0
memberships               = 0
alumnos                    = 0
profesores                 = 0
clases                     = 0
pagos                      = 0
escuelas demo              = 0
credenciales demo          = 0
```

Puede existir `REFERENCE_REQUIRED` si el código lo necesita estructuralmente, por ejemplo catálogo interno de permisos.

No confundas reference data con demo seed.

El deploy productivo jamás debe ejecutar demo seed.

Los fixtures demo/test deben estar aislados del path de producción.

---

# 24. RESET DE SCHEMA — SÓLO ENTORNOS EFÍMEROS

El usuario quiere poder demostrar una reconstrucción limpia con un `drop schema` en una sola ejecución.

Implementá o reutilizá una herramienta destructiva **separada de `deploy.cmd`**.

Responsabilidad:

```text
reset isolated DB
-> drop/recreate permitido
-> Flyway migrate
-> validate
-> runtime verification
```

Requisitos fail-closed:

- sólo dev/test/ephemeral;
- target explícito;
- nombre/labels verificables;
- confirmación fuerte o flag explícito;
- rechazo de production;
- rechazo de staging sensible;
- rechazo de `gestudio-remote-demo` si existe;
- rechazo de DB no reconocida;
- no usar credenciales productivas;
- exit codes claros;
- logs sanitizados.

**Nunca agregues un botón destructivo al deploy productivo.**

`deploy.cmd` debe seguir siendo no destructivo.

---

# 25. CLEAN-ROOM DATABASE GATE

Automatizá:

```text
empty PostgreSQL
-> migrate fresh
-> validate
-> start backend with runtime user
-> verify grants
-> verify NOSUPERUSER
-> verify NOBYPASSRLS
-> verify RLS
-> verify no seed
-> verify health
```

Debe ejecutarse con PostgreSQL real.

No uses H2 u otra DB como sustituto de RLS/ACL/constraints de PostgreSQL.

La DB del gate debe ser aislada y desechable.

---

# 26. HISTORICAL UPGRADE GATE

Elegí la versión histórica soportada real tras inspección.

El gate debe:

1. desplegar versión base;
2. insertar datos representativos;
3. verificar consistencia;
4. conservar volumen;
5. crear backup si corresponde;
6. actualizar a HEAD;
7. aplicar sólo migraciones pendientes;
8. conservar datos;
9. conservar ACLs;
10. conservar grants;
11. verificar RLS;
12. arrancar con runtime;
13. verificar comportamiento funcional;
14. ejecutar HEAD otra vez;
15. demostrar que no reaplica migraciones ni duplica datos.

No uses la demo protegida.

---

# 27. PRESERVAR DEPLOY EXISTENTE

Si siguen existiendo:

```text
deploy.cmd
scripts/deploy/**
docker-compose*
scripts de backup/restore
```

preservá su contrato probado.

No reimplementes todo.

No dupliques:

- backup;
- restore;
- health;
- Docker detection;
- espera de servicios;
- configuración de puertos;
- secret generation;
- state file;
- fingerprint;
- locks;
- cleanup;
- validation PostgreSQL.

El backoffice, las nuevas migraciones y el bootstrap deben integrarse sin degradar la idempotencia.

---

# 28. IDEMPOTENCIA DEL DEPLOY

Si el contrato histórico sigue vigente, conservá:

- mismo proyecto Compose;
- mismos volúmenes;
- mismos secretos;
- misma configuración efectiva;
- mismo Flyway state;
- mismo bootstrap estructural;
- sin backups innecesarios;
- sin reconstrucción innecesaria;
- sin recreación innecesaria;
- sin datos duplicados;
- sin modificación de Git;
- sin tocar proyectos ajenos.

La segunda ejecución sin cambios debe ser observable como no-op o convergencia mínima segura.

`--verify-only` debe ser inmutable.

No declares idempotencia sin ejecutar el gate real.

---

# 29. DEMO PROTEGIDA

Si existe un proyecto equivalente a:

```text
gestudio-remote-demo
```

tratálo como recurso protegido.

Antes de gates Docker:

- capturá IDs;
- volúmenes;
- redes;
- estado.

Después:

- confirmá invariancia;
- no reinicies;
- no recrees;
- no borres;
- no uses sus puertos;
- no uses sus secretos;
- no uses su DB;
- no uses nombres parciales para limpieza.

Si ya no existe, registrá `N/A` con evidencia.

---

# 30. QUALITY FORTRESS — CAPAS

La release debe sobrevivir, según aplique, a:

1. unit tests;
2. integration tests;
3. PostgreSQL real;
4. Gherkin/BDD;
5. authorization matrix;
6. RLS adversarial;
7. contract/API tests;
8. browser E2E;
9. accessibility;
10. coverage;
11. mutation testing;
12. property-based/fuzz tests donde aporten;
13. static analysis;
14. lint;
15. type checks;
16. duplication/complexity checks;
17. dependency audit;
18. SAST;
19. secret scanning;
20. supply-chain controls;
21. migration equivalence;
22. fresh DB;
23. historical upgrade;
24. backup/restore;
25. rollback;
26. deploy idempotency;
27. performance;
28. resilience;
29. observability;
30. remote GitHub Actions.

No agregues herramientas duplicadas si el repo ya tiene equivalentes.

---

# 31. GHERKIN / BDD EJECUTABLE

Agregá Gherkin sólo donde aporte trazabilidad de negocio.

No crees `.feature` sin runner.

Escenarios mínimos:

```gherkin
Feature: Provisionamiento de tenants desde backoffice

  Scenario: SUPERADMIN crea una escuela
    Given un SUPERADMIN autenticado y autorizado
    And no existe el tenant "Escuela Danza Marcos Paz"
    When crea "Escuela Danza Marcos Paz"
    Then existe exactamente un tenant activo
    And no se crean datos demo
    And se registra auditoría

  Scenario: Tenant admin intenta crear otra organización
    Given un administrador de Tenant Alpha
    When intenta crear Tenant Beta
    Then recibe acceso denegado
    And Tenant Beta no existe

  Scenario: SUPERADMIN crea administradora del tenant
    Given existe "Escuela Danza Marcos Paz"
    When crea o asocia una identidad administradora
    And asigna membership y rol tenant
    Then existe una única membership
    And la administradora puede autenticarse
    And sólo administra su tenant

  Scenario: Manipulación cross-tenant
    Given Admin Alpha y Tenant Beta
    When Admin Alpha usa un ID perteneciente a Beta
    Then la operación es denegada
    And no se filtra existencia ni datos de Beta

  Scenario: Tenant suspendido
    Given un tenant activo con usuarios
    When SUPERADMIN lo suspende
    Then el comportamiento de autenticación y acceso coincide con la política
    And los datos permanecen intactos

  Scenario: Provisioning concurrente
    Given dos requests equivalentes simultáneos
    When ambos intentan crear la misma asignación
    Then existe una única entidad final consistente
```

Adaptá wording y fixtures a la arquitectura real.

---

# 32. COVERAGE

Primero medí el baseline actual.

No inventes porcentajes históricos.

Objetivo de release, salvo justificación excepcional documentada:

## Backend

```text
global line coverage            >= 90%
global branch coverage          >= 85%
auth/tenant/platform line       >= 95%
auth/tenant/platform branch     >= 90%
nuevo código authorization branch >= 95%
```

## Frontend

```text
global line coverage             >= 85%
global branch coverage           >= 80%
backoffice services/guards line  >= 90%
```

Si el repo parte por debajo:

- no bajes el threshold para conseguir verde;
- registrá baseline real;
- exigí al menos `diff coverage >= 90%` inicialmente;
- cerrá deuda crítica antes de declarar producto final;
- no marques `PASS` global mientras el target acordado no esté cumplido.

La métrica debe fallar el build automáticamente.

---

# 33. MUTATION TESTING

Coverage no alcanza.

Implementá o reutilizá mutation testing.

Para Java, si el stack lo permite, evaluá PIT. Para frontend, reutilizá la herramienta existente o incorporá una compatible sólo si existe necesidad clara.

Objetivos de release orientativos:

```text
global mutation score     >= 80%
test strength             >= 85%
auth/platform/tenant      >= 90%
```

No excluyas indiscriminadamente paquetes críticos.

Prioridad:

- autorización;
- tenant isolation;
- provisioning;
- lifecycle;
- auth;
- refresh;
- MFA;
- role assignment;
- audit;
- migraciones Java-side si existe lógica;
- cálculos financieros sensibles.

Guardá reportes como artefactos CI cuando corresponda.

---

# 34. TESTS NEGATIVOS Y ADVERSARIALES

Toda funcionalidad crítica nueva debe incluir:

- inputs inválidos;
- nulls;
- límites;
- IDs inexistentes;
- IDs de otro tenant;
- permisos insuficientes;
- usuario suspendido;
- tenant suspendido;
- membership revocada;
- rol revocado;
- token expirado;
- refresh inválido;
- request replay;
- concurrencia;
- duplicación;
- campos extra;
- payload sobredimensionado razonable;
- XSS payload;
- SQL-like payload;
- errores DB;
- rollback;
- auditoría tras error.

No pruebes sólo 2xx.

---

# 35. E2E DEL BACKOFFICE

Usá el framework E2E real del repo; si no existe, elegí una opción mínima compatible y justificá la dependencia.

Flujo E2E mínimo:

1. crear entorno fresh;
2. bootstrap primer SUPERADMIN;
3. login SUPERADMIN;
4. MFA si aplica;
5. abrir backoffice;
6. crear `Escuela Danza Marcos Paz`;
7. crear/asociar administradora;
8. asignar rol;
9. cerrar sesión;
10. login como administradora;
11. comprobar que sólo ve su tenant;
12. intentar acceso a otro tenant;
13. comprobar rechazo;
14. volver como SUPERADMIN;
15. suspender tenant;
16. comprobar efecto;
17. reactivar;
18. comprobar recuperación;
19. revisar auditoría.

No uses datos productivos.

---

# 36. ACCESSIBILITY

El backoffice debe apuntar a WCAG 2.2 AA cuando sea aplicable.

Automatizá lo posible.

Además verificá manual/automatizadamente:

- teclado;
- orden de tab;
- foco visible;
- focus trap;
- labels;
- mensajes de error;
- `aria-*` correcto;
- contraste;
- no depender sólo del color;
- tablas navegables;
- modales;
- loaders;
- empty states;
- formularios;
- confirmaciones destructivas.

No declares WCAG completo sólo por pasar axe.

---

# 37. API CONTRACTS

Si existe OpenAPI/Swagger u otro contrato, actualizalo.

Verificá:

- schemas;
- status codes;
- auth;
- errors;
- enums;
- required fields;
- backward compatibility.

Si no existe contrato formal, no introduzcas uno enorme sólo por cumplir un checklist: evaluá costo/beneficio y documentá la decisión.

---

# 38. SECURITY BASELINE

Mapeá los cambios críticos contra una referencia verificable equivalente a OWASP ASVS.

No declares cumplimiento total sin checklist.

Como mínimo auditá:

- authentication;
- session management;
- authorization;
- input validation;
- output encoding;
- stored XSS;
- CSRF según arquitectura;
- CORS;
- file handling;
- logging;
- error handling;
- secrets;
- cryptography;
- API security;
- business logic;
- configuration.

---

# 39. SUPPLY CHAIN

Usá herramientas existentes o equivalentes para:

- dependency audit;
- SAST;
- secret scanning;
- vulnerable actions;
- lockfile integrity;
- GitHub Actions permissions mínimas;
- pinning seguro cuando corresponda;
- SBOM;
- provenance/attestations si la infraestructura lo permite.

No agregues sistemas SaaS pagos o credenciales externas sin autorización.

No declares 0 vulnerabilidades si sólo corriste un subset.

---

# 40. SECRETS Y CONFIGURACIÓN

No modifiques secretos reales.

No imprimas valores.

No metas `.env` efectivo al repo.

Verificá:

- `.gitignore`;
- plantillas;
- secretos del deploy;
- secretos del bootstrap;
- logs;
- dumps;
- test fixtures;
- CI.

Los tests deben usar secretos sintéticos.

---

# 41. OBSERVABILIDAD DEL CONTROL PLANE

Integrá con infraestructura existente.

Registrar/métricas para:

- tenant created;
- tenant suspended;
- tenant reactivated;
- membership created;
- membership revoked;
- role changed;
- bootstrap superadmin;
- MFA events si aplica;
- auth failures;
- authorization denials;
- cross-tenant denials;
- provisioning failures.

No exponer:

- passwords;
- tokens;
- MFA secrets;
- PII innecesaria.

Usá correlation IDs existentes.

Definí alertas si la infraestructura real lo permite.

---

# 42. PERFORMANCE

No inventes un SLA arbitrario sin baseline.

Primero medí:

- login;
- listado de tenants;
- creación de tenant;
- asignación de admin;
- endpoints tenant críticos;
- queries cross-tenant prohibidas.

Definí un performance smoke reproducible.

Si existe herramienta de load test, reutilizala.

Si no existe, agregá la mínima viable sólo si aporta valor.

Al menos:

- concurrencia razonable;
- no N+1 obvio;
- índices correctos;
- locks sin serialización accidental;
- provisioning concurrente estable.

Para declarar cierre productivo, documentá capacidad probada y límites.

---

# 43. RESILIENCIA

Probá fallos razonables:

- PostgreSQL temporalmente no disponible;
- fallo durante provisioning;
- timeout;
- proceso reiniciado;
- deploy interrumpido;
- backup fallido;
- health degradado.

No agregues chaos engineering complejo sin necesidad.

La finalidad es demostrar estados consistentes y diagnósticos claros.

---

# 44. PRIVACIDAD Y CICLO DE DATOS

Auditá si Gestudio maneja PII y datos financieros.

Determiná requerimientos reales de:

- retención;
- export;
- delete/anonymize;
- backup retention;
- logs;
- auditoría;
- derecho de acceso;
- segregación.

Si depende de política legal/organizacional no definida, clasificá `PARTIAL` o `N/A` con razón, no inventes legislación.

---

# 45. BACKUP / RESTORE / DR

Preservá los gates existentes.

El cambio de baseline y control plane debe quedar incluido en backup/restore.

Verificá:

- tenants;
- platform identities;
- memberships;
- roles;
- audit;
- grants;
- ACLs;
- RLS;
- Flyway history;
- runtime startup.

Definí RPO/RTO sólo con evidencia.

Si PITR depende de infraestructura externa inexistente, registralo como limitación externa real.

---

# 46. ROLLBACK

No prometas rollback automático de migraciones destructivas si Flyway/arquitectura no lo soporta.

Documentá:

- rollback de aplicación;
- restore;
- forward fix;
- migraciones irreversibles;
- procedimiento operativo.

Probá el camino real disponible.

---

# 47. TEST FLAKINESS

Identificá tests flaky.

Prohibido:

- ocultar flakes con retries indiscriminados;
- ignorar fallos;
- `@Disabled` sin razón;
- sleeps arbitrarios.

Un gate release debe ser repetible.

Si un test falla intermitentemente:

- encontrar causa;
- estabilizar;
- registrar evidencia.

---

# 48. QUALITY GATE LOCAL

Descubrí los comandos canónicos del proyecto.

El gate final debe incluir, según aplique:

```text
format
lint
typecheck
unit
integration
PostgreSQL real
Gherkin
coverage
mutation
frontend tests
frontend build
backend clean verify
Compose validation
fresh DB
migration equivalence
historical upgrade
seed isolation
bootstrap superadmin
authorization matrix
RLS adversarial
E2E
accessibility
dependency audit
SAST
secret scan
backup/restore
rollback
deploy idempotency
verify-only
performance smoke
```

No inventes un script consolidado si ya existe uno adecuado.

Si falta un punto de entrada canónico y aporta valor real, podés crear uno permanente, documentado, que **orqueste** gates existentes sin duplicar su lógica.

---

# 49. GITHUB ACTIONS

Después de publicar el SHA candidato:

1. obtené el SHA;
2. enumerá todos los workflows disparados;
3. identificá los requeridos;
4. esperá su terminación;
5. inspeccioná logs de fallos;
6. corregí causas reales;
7. commit normal;
8. push normal;
9. repetí gates afectados;
10. volvé a esperar CI.

No declares `PASS` mientras un workflow requerido esté:

```text
queued
pending
in_progress
cancelled
failure
unknown
```

Los éxitos de un SHA anterior no certifican el nuevo SHA.

Si un workflow no se dispara por paths pero es requerido para esta release y soporta `workflow_dispatch`, ejecutalo sobre el SHA/ref correcto.

No falsees evidencia si `gh` no está disponible.

---

# 50. CRITERIOS DE ACEPTACIÓN DEL BACKOFFICE

Debe demostrarse ejecutablemente:

- SUPERADMIN autenticado accede al backoffice;
- usuario tenant no accede;
- admin tenant no accede;
- usuario anónimo no accede;
- SUPERADMIN crea `Escuela Danza Marcos Paz`;
- queda un único tenant;
- no se crean datos demo;
- SUPERADMIN crea o asocia administradora;
- se crea una única membership;
- se asigna rol correcto;
- admin puede iniciar sesión;
- admin sólo administra su tenant;
- IDs manipulados de otro tenant son rechazados;
- no se filtra información cross-tenant;
- tenant suspendido queda bloqueado según política;
- tenant reactivado recupera comportamiento esperado;
- provisioning concurrente no duplica;
- fallos transaccionales no dejan estado parcial;
- auditoría registra actor/acción/target/tenant/timestamp/correlation;
- auditoría no contiene secretos;
- SUPERADMIN sigue sin `SUPERUSER`;
- runtime sigue sin `BYPASSRLS`.

---

# 51. CRITERIOS DE ACEPTACIÓN DE MIGRACIONES

Debe demostrarse:

- DB vacía;
- una ejecución de migración fresh;
- `validate` exitoso;
- esquema completo;
- constraints completos;
- indexes completos;
- RLS completo;
- policies completas;
- grants completos;
- runtime funcional;
- 0 tenants de negocio;
- 0 users funcionales;
- 0 memberships;
- 0 demo seed;
- reference data sólo si es imprescindible;
- estrategia baseline/equivalente documentada;
- migraciones históricas preservadas si deben ser compatibles;
- upgrade histórico exitoso;
- datos preservados;
- ACLs preservadas;
- grants preservados;
- no reaplicar migraciones;
- no alterar `flyway_schema_history` manualmente.

---

# 52. CRITERIOS DE ACEPTACIÓN DEL DEPLOY

Si `deploy.cmd` existe como contrato vigente:

- raíz;
- funciona desde cualquier cwd;
- funciona con espacios;
- propaga exit code;
- delega en PowerShell;
- no requiere admin;
- no inicia Docker Desktop;
- no contiene secretos;
- `--help` pasa;
- `--dry-run` no muta;
- ejecución normal pasa;
- segunda ejecución no-op/convergencia;
- `--verify-only` no muta;
- mismo volumen PostgreSQL;
- mismos secretos;
- misma configuración;
- mismo Flyway state;
- sin backup innecesario;
- lock concurrente probado;
- Docker inaccesible falla antes de mutar;
- demo protegida no cambia;
- upgrade conserva datos.

---

# 53. RELEASE READINESS MATRIX

Mantené una matriz viva:

| Gate | Estado | SHA | Evidencia | Pendiente |
|---|---|---|---|---|
| Git continuity | PASS | 53547baac50063de85fb694124241d9f58e256a1 | Inicio obligatorio: `fetch origin`, `checkout main`, `pull --ff-only origin main` y divergencia `0 0`; los refs locales continúan iguales | Revalidar con `fetch` antes de publicar |
| Backend build | NOT VERIFIED | working tree | El `clean verify` histórico corresponde al SHA base y fue invalidado por los cambios backend actuales | Reejecutar gate completo con PostgreSQL/Docker disponible |
| Frontend build | PASS | working tree | `npm run build` vigente: `tsc -b`, Vite production build y Pages headers PASS; 2402 módulos transformados, Vite 16.13 s | Repetir sobre el SHA definitivo si cambia frontend |
| Unit | PARTIAL | working tree | Suite frontend integral vigente: 81/81 archivos y 582/582 tests PASS; backend conserva sólo gates focales y no una suite integral actual | Falta suite backend integral vigente con PostgreSQL |
| Integration | NOT VERIFIED | working tree | Los artefactos integrados anteriores quedaron invalidados por cambios de backend, migraciones y configuración | Reejecutar integración completa |
| PostgreSQL real | NOT VERIFIED | working tree | Hubo focales PostgreSQL parciales, pero no existe un gate limpio vigente posterior al árbol backend definitivo | Docker/Testcontainers requerido |
| Backend static analysis | PASS | working tree | PMD vigente: 115 hallazgos legacy declarados, 0 regresiones/config errors/suppressions; CPD 0 duplicaciones | Revalidar si vuelve a cambiar backend |
| Frontend static analysis | PASS | working tree | ESLint PASS; duplicación productiva 273/15424 líneas = 1.77%, por debajo del 2%; verificador de artefacto PASS | Repetir sobre el SHA definitivo si cambia frontend |
| Multitenancy | PARTIAL | working tree | Arquitectura y tests adversariales están implementados; falta gate integrado actual | PostgreSQL/Docker y release SHA |
| RLS adversarial | PARTIAL | working tree | Casos HTTP/DB están implementados, pero no existe ejecución integral vigente | Reejecutar con roles runtime reales |
| SUPERADMIN | PARTIAL | working tree | Control-plane, MFA, step-up y scopes separados implementados con pruebas focales | Falta ceremonia completa fresh/bootstrap/E2E |
| Tenant provisioning | PARTIAL | working tree | Provisioning transaccional y tests están implementados | Falta gate PostgreSQL/control-plane y E2E real |
| Tenant lifecycle | PARTIAL | working tree | Suspensión/reactivación e invalidación de sesión están implementadas | Falta evidencia browser/HTTP/DB actual |
| Audit | PARTIAL | working tree | SUCCESS/DENIED/FAILED y append-only están implementados y probados focalmente | Falta gate integrado y consulta E2E |
| Fresh DB | PARTIAL | working tree | B12 aislado ejecutó en PostgreSQL 15.18 con health GREEN y 0 filas funcionales | Falta Flyway+Hibernate integrado vigente |
| No production seed | PARTIAL | working tree | B12 modela 32 permisos de referencia y 0 tenants/users/memberships/roles/admins | Reconfirmar en fresh integrado y E2E |
| Flyway validate | PARTIAL | working tree | B12 y V1-V12 fueron ejecutados en focales parciales; no hay gate final vigente | Reejecutar fresh, validate y upgrade |
| Migration equivalence | NOT VERIFIED | working tree | La evidencia anterior quedó invalidada por correcciones posteriores de B12 | Reejecutar equivalencia estructural y de ACL |
| Historical upgrade | NOT VERIFIED | working tree | V12 preserva filas por diseño; no hay ejecución operacional final vigente | Ejecutar upgrade con datos/ACL y reconciliación |
| Bootstrap SUPERADMIN | PARTIAL | working tree | Job externo one-shot, MFA y recovery codes están implementados; contrato PowerShell estático focal verde | Falta bootstrap real aislado y entrega segura ejecutada |
| Gherkin | NOT VERIFIED | working tree | Features y runner existen; último intento integrado no produjo evidencia verde vigente | Reejecutar con PostgreSQL/Docker |
| Coverage | PARTIAL | working tree | FrontendCoverage vigente PASS: 96.05% líneas, 87.93% ramas, 94.30% sentencias; FrontendDiffCoverage vigente PASS: 98.83% líneas, 97.54% sentencias, 91.18% ramas; ambos con 582/582 tests e inventarios/verificadores fail-closed PASS | BackendCoverage/BackendDiffCoverage requieren PostgreSQL/Docker |
| Mutation | NOT VERIFIED | working tree | PIT global/crítico y verificadores fail-closed están implementados, sin reportes actuales | Ejecutar ambos perfiles con Docker |
| Authorization matrix | PARTIAL | working tree | Matriz security HTTP focal pasó antes de cambios posteriores de observabilidad | Reejecutar authorization/RLS sobre árbol estable |
| E2E | NOT VERIFIED | working tree | Arnés Playwright/axe permanente implementado; TypeScript E2E PASS y exactamente 1 test Chromium descubierto con configuración sintética | Ejecutar flujo browser fresh/bootstrap/MFA/Alpha/Beta/RLS/lifecycle/audit con Docker; la validación estática no es evidencia runtime |
| Accessibility | PARTIAL | working tree | La suite frontend integral vigente (81 archivos, 582 tests) incluye foco, drawers modales, tabs por teclado y asociación de errores | Ejecutar axe/browser real y revisión WCAG restante |
| SAST | NOT VERIFIED | working tree | Workflow/configuración implementados, sin ejecución sobre SHA candidato | Ejecutar security workflow definitivo |
| Dependency audit | PARTIAL | working tree | `npm ci` PASS; auditorías npm producción y total terminaron exit 0 con 0 vulnerabilidades en todas las severidades; lock/manifest de Playwright y axe coinciden | Falta auditoría backend vigente y repetición sobre el SHA definitivo |
| Secret scan | NOT VERIFIED | working tree | Gate diseñado, sin resultado sobre el árbol final | Ejecutar antes de staging y en CI |
| Supply chain | PARTIAL | working tree | Lockfile Playwright/axe íntegro, auditorías npm producción/total en 0 vulnerabilidades y policies/workflows validados estáticamente; SBOM/provenance/scans siguen sin evidencia ejecutada | Ejecutar/publicar artifacts completos en SHA candidato |
| Backup/restore | NOT VERIFIED | working tree | Drill actualizado para V12/B12/control-plane, sin ejecución actual | Docker requerido |
| Rollback | PARTIAL | working tree | Drill corregido: sin worktree alternativo ni hardcodes V7/SHA; usa extracción `git archive` temporal validada, deriva V1..Vlatest/Baseline y verifica control-plane; AST PS7/PS5 y contrato estático PASS | Ejecutar el drill operativo aislado con Docker |
| Deploy idempotency | NOT VERIFIED | working tree | Deploy/verify-only actualizados, sin ejecución actual | Docker requerido |
| Ephemeral database reset | PARTIAL | working tree | Herramienta separada fail-closed y contrato estático 36/36 PASS en PS7/PS5; rechaza prod/staging/demo/remoto y ownership ambiguo antes de `DROP SCHEMA` | Ejecutar sobre un proyecto efímero aislado cuando Docker esté disponible |
| Performance | NOT VERIFIED | working tree | Sin baseline ejecutado sobre la implementación actual | Ejecutar Fase 13 |
| Resilience | NOT VERIFIED | working tree | Failure paths tienen cobertura focal parcial, sin gate de resiliencia | Ejecutar Fase 13 |
| Observability | PARTIAL | working tree | Métricas acotadas sin PII y verificador operativo implementados; sin drill Docker | Ejecutar pruebas focales vigentes y drill |
| Documentation | PARTIAL | working tree | Contrato vivo, gobierno multitenant, desarrollo, bootstrap, rollback, reset efímero, testing y referencias históricas están actualizados; threat model/runbook de plataforma siguen en integración | Completar Fase 14 y reservar evidencia final para el SHA definitivo |
| GitHub Actions | NOT VERIFIED | working tree | Workflows modificados/no publicados; los runs del SHA base no certifican este árbol | Ejecutar todos los requeridos sobre SHA definitivo |
| HEAD == origin/main | PASS | 53547baac50063de85fb694124241d9f58e256a1 | Los refs locales continúan iguales para el SHA base | No certifica el worktree; revalidar tras push final |
| Clean tree | FAIL | working tree | Implementación task-owned extensa todavía sin commit | Debe quedar limpio sobre el SHA definitivo |

Estados permitidos:

```text
PASS
FAIL
PARTIAL
N/A
NOT VERIFIED
```

No uses `PASS` sin ejecución.

`N/A` requiere justificación explícita.

---

# 54. DEFINICIÓN FINAL DE PRODUCTO CERRADO

Gestudio sólo puede clasificarse:

```text
RELEASE_READINESS=PASS
```

cuando una release concreta demuestre:

## Plataforma

- backoffice visual funcional;
- SUPERADMIN separado de tenant roles;
- MFA/step-up según arquitectura;
- tenant provisioning completo;
- tenant admin provisioning;
- roles/memberships;
- lifecycle;
- auditoría.

## Aislamiento

- dos o más tenants;
- pruebas cross-tenant;
- HTTP adversarial;
- DB adversarial;
- RLS;
- runtime sin bypass;
- jobs con contexto;
- archivos con contexto;
- native queries auditadas.

## DB

- fresh DB;
- sin seed funcional;
- bootstrap externo;
- baseline/equivalente;
- upgrade;
- Flyway validate;
- grants;
- ACLs;
- backup/restore.

## Calidad

- tests;
- Gherkin;
- coverage;
- mutation;
- E2E;
- accessibility;
- security;
- performance;
- no gates silenciosamente omitidos.

## Operación

- deploy;
- idempotencia;
- verify;
- rollback;
- observabilidad;
- documentación;
- runbooks.

## Git

- SHA definitivo publicado;
- workflows requeridos del mismo SHA en success;
- `HEAD == origin/main`;
- árbol limpio;
- sin force push;
- sin ramas nuevas;
- sin secretos;
- sin archivos temporales.

Si falta un gate requerido:

```text
RELEASE_READINESS != PASS
```

---

# 55. ORDEN DE TRABAJO OBLIGATORIO

Seguí este orden.

## Fase 0 — Git y continuidad

- verificar repo;
- fetch;
- main;
- ff-only;
- tree;
- origin;
- HEAD;
- workflows actuales;
- estado Docker protegido.

**STOP si Git no es seguro.**

## Fase 1 — Baseline actual

- ejecutar gates existentes relevantes sin modificar;
- registrar fallos reales;
- no culpar al cambio nuevo por fallos preexistentes sin evidencia.

## Fase 2 — Arquitectura real

- multitenancy;
- auth;
- RBAC;
- RLS;
- DB roles;
- migrations;
- seeds;
- frontend;
- observabilidad.

## Fase 3 — Diseño mínimo

Producí una decisión concreta para:

- platform scope;
- SUPERADMIN;
- provisioning;
- lifecycle;
- auditoría;
- DB access;
- baseline;
- bootstrap.

Si la decisión es durable y no obvia, crear/actualizar ADR.

## Fase 4 — Migraciones fresh

- clasificar seeds;
- baseline/equivalente;
- clean-room;
- no producción seed;
- equivalence gate.

## Fase 5 — Backend control plane

- modelo;
- services;
- endpoints;
- authz;
- transactions;
- concurrency;
- audit.

## Fase 6 — Bootstrap SUPERADMIN

- mecanismo seguro;
- idempotencia;
- tests.

## Fase 7 — Frontend backoffice

- routing;
- guards;
- screens;
- forms;
- lifecycle;
- audit UX;
- accessibility.

## Fase 8 — Tests funcionales

- unit;
- integration;
- PG real;
- authorization;
- Gherkin;
- RLS adversarial.

## Fase 9 — Quality metrics

- coverage;
- mutation;
- static analysis;
- duplication/complexity.

## Fase 10 — E2E

- fresh;
- bootstrap;
- login;
- tenant;
- admin;
- cross-tenant;
- suspend/reactivate;
- audit.

## Fase 11 — Operación

- deploy;
- idempotency;
- upgrade;
- backup/restore;
- rollback;
- verify-only;
- protected demo.

## Fase 12 — Security

- threat model;
- SAST;
- dependency;
- secrets;
- supply chain;
- ASVS mapping.

## Fase 13 — Performance/resilience

- baseline;
- smoke/load razonable;
- concurrency;
- failure paths.

## Fase 14 — Docs/autorreferencia

Actualizar:

- este archivo;
- docs de arquitectura;
- multitenancy governance;
- deployment;
- operations;
- backup/restore;
- bootstrap;
- backoffice;
- threat model;
- runbooks.

No dupliques documentación existente.

## Fase 15 — Gate release local

Ejecutar todos los gates reales.

Registrar:

- comando exacto;
- SHA;
- exit code;
- duración;
- tests;
- resultado;
- warnings;
- artefactos.

## Fase 16 — Diff y Git

- `git diff`;
- `git diff --check`;
- `git status`;
- secret scan;
- staging explícito;
- sólo archivos relacionados;
- commit normal descriptivo.

## Fase 17 — Push

- fetch final;
- confirmar continuidad;
- push normal a `origin main`.

## Fase 18 — CI definitivo

- enumerar workflows del SHA;
- esperar;
- corregir fallos reales con commit nuevo;
- repetir hasta verde.

## Fase 19 — Cierre

- fetch;
- `HEAD == origin/main`;
- árbol limpio;
- release matrix;
- informe final.

---

# 56. REGLA DE INVALIDACIÓN

Cualquier edición posterior a un gate invalida todos los gates afectados.

Ejemplos:

- tocar backend invalida backend tests/coverage/mutation/build;
- tocar frontend invalida frontend tests/build/E2E;
- tocar Compose invalida deploy/idempotency;
- tocar migraciones invalida fresh/equivalence/upgrade/backup-restore;
- tocar auth invalida authorization/RLS/E2E/security;
- tocar workflow invalida evidencia remota previa.

No reutilices verde viejo como evidencia nueva.

---

# 57. CAMBIO MÍNIMO

Durante la implementación:

- seguir patrones reales;
- cambio mínimo suficiente;
- no refactor amplio;
- no duplicación;
- no código muerto;
- no feature flags temporales sin necesidad;
- no TODO como sustituto de implementación;
- no comments redundantes;
- no nueva dependencia sin justificación;
- no endpoint paralelo si puede extenderse uno real;
- no sistema de roles paralelo;
- no ORM bypass accidental;
- no SQL manual paralelo a Flyway.

---

# 58. DOCUMENTACIÓN TÉCNICA REQUERIDA

Localizá docs existentes y actualizá en su lugar.

Si faltan, creá sólo las necesarias.

Debe quedar documentado:

- control plane;
- platform vs tenant scope;
- SUPERADMIN;
- DB privileges;
- RLS;
- lifecycle;
- provisioning;
- bootstrap;
- MFA;
- audit;
- migration baseline;
- production no-seed;
- reset dev/test;
- upgrade;
- backup/restore;
- deploy;
- release gates;
- threat model;
- recovery;
- known limitations.

El README principal sólo debe tener referencias breves si ya existe docs dedicada.

---

# 59. INFORME FINAL OBLIGATORIO DE CODEX

No respondas con un resumen superficial.

Usá estas secciones.

## Estado inicial

- repositorio;
- rama;
- HEAD inicial;
- origin/main inicial;
- divergencia;
- worktree;
- Flyway;
- Docker;
- demo protegida;
- baseline de tests;
- baseline de coverage/mutation si existía.

## Auditoría

- arquitectura;
- tenants;
- users;
- memberships;
- roles;
- permissions;
- tenant context;
- RLS;
- queries;
- jobs;
- archivos;
- frontend;
- seeds;
- migraciones;
- riesgos.

## Arquitectura final

- platform scope;
- tenant scope;
- SUPERADMIN;
- auth;
- MFA;
- runtime DB;
- grants;
- RLS;
- lifecycle;
- audit.

## Migraciones

- versiones;
- baseline/equivalente;
- fresh DB;
- reference data;
- seeds eliminados del path productivo;
- equivalence;
- upgrade;
- rollback/restore.

## Implementación

- tenants;
- admin accounts;
- memberships;
- roles;
- backoffice;
- bootstrap;
- lifecycle;
- audit.

## Seguridad

- threat model;
- autorización;
- RLS;
- cross-tenant;
- IDOR;
- mass assignment;
- session/MFA;
- XSS/CSRF;
- secrets;
- supply chain.

## Calidad

Para cada gate:

- comando exacto;
- SHA;
- exit code;
- duración;
- cantidad de tests;
- coverage;
- mutation;
- resultado;
- warnings.

## Operación

- deploy;
- idempotency;
- verify-only;
- upgrade;
- backup/restore;
- rollback;
- observabilidad;
- demo protegida.

## GitHub Actions

- workflow;
- run ID/URL cuando esté disponible;
- SHA;
- conclusión.

## Git

- archivos modificados;
- commits;
- mensajes;
- SHA final;
- push;
- `HEAD == origin/main`;
- clean tree.

## Release Readiness

Tabla final `PASS / FAIL / PARTIAL / N/A / NOT VERIFIED`.

## Riesgos y pendientes

Sólo riesgos reales.

No presentes como “pendiente externo” trabajo interno que está dentro de esta misión.

---

# 60. ESTADOS FINALES REQUERIDOS

Informá explícitamente:

```text
GIT_CONTINUITY=
BACKEND_BUILD=
FRONTEND_BUILD=
MULTITENANCY=
RLS=
PLATFORM_CONTROL_PLANE=
PLATFORM_SUPERADMIN=
TENANT_PROVISIONING=
TENANT_ADMIN_PROVISIONING=
TENANT_LIFECYCLE=
AUDIT=
BOOTSTRAP_SUPERADMIN=
FRESH_DATABASE=
PRODUCTION_NO_SEED=
FLYWAY_VALIDATE=
MIGRATION_EQUIVALENCE=
HISTORICAL_UPGRADE=
BACKUP_RESTORE=
ROLLBACK=
DEPLOY_IDEMPOTENCY=
GHERKIN=
COVERAGE=
MUTATION=
AUTHORIZATION_MATRIX=
E2E=
ACCESSIBILITY=
SAST=
DEPENDENCY_AUDIT=
SECRET_SCAN=
SUPPLY_CHAIN=
PERFORMANCE=
RESILIENCE=
OBSERVABILITY=
DOCUMENTATION=
GITHUB_ACTIONS=
HEAD_EQUALS_ORIGIN_MAIN=
CLEAN_TREE=
RELEASE_READINESS=
```

Valores permitidos:

```text
EXECUTED_PASS
EXECUTED_FAIL
PARTIAL
N/A
NOT_EXECUTED
```

Para `RELEASE_READINESS`:

```text
PASS
FAIL
PARTIAL
```

No uses `EXECUTED_PASS` si no ejecutaste el gate.

---

# 61. CONDICIÓN DE CIERRE

No entregues el informe final mientras falte cualquiera de estos hechos, salvo imposibilidad externa real y documentada:

- Git seguro;
- implementación completa;
- fresh DB;
- sin seed productivo;
- bootstrap SUPERADMIN;
- backoffice;
- tenant provisioning;
- tenant admin provisioning;
- cross-tenant denegado;
- RLS verificado;
- audit;
- Gherkin;
- coverage;
- mutation;
- backend;
- frontend;
- E2E;
- security gates;
- backup/restore;
- upgrade;
- deploy idempotency;
- CI del SHA final;
- `HEAD == origin/main`;
- árbol limpio.

Si una limitación externa impide un gate:

- no inventes el resultado;
- clasificalo `PARTIAL` o `NOT_EXECUTED`;
- explicá exactamente por qué;
- indicá el comando que queda pendiente.

---

# 62. INSTRUCCIÓN DE ARRANQUE

Empezá ahora.

No respondas con un plan teórico.

Primero ejecutá la verificación Git obligatoria y reconstruí el estado real.

No asumas el SHA histórico.

No empieces por la UI.

No toques migraciones hasta entender compatibilidad.

No uses el SUPERADMIN como bypass de RLS.

No metas seed de negocio en producción.

No destruyas ninguna DB no efímera.

No toques recursos Docker ajenos.

No termines después de compilar.

No declares `PASS` sin evidencia.

Trabajá de forma autónoma, conservadora, incremental y verificable hasta completar la misión o encontrar una STOP CONDITION real.
