# Threat model del control plane de plataforma

- Estado del documento: `PARTIAL`
- Estado de la implementación evaluada: `IMPLEMENTED_NOT_RUN`
- Fecha de revisión: 2026-08-13
- Alcance: autenticación, autorización, sesiones, MFA, step-up,
  aprovisionamiento, lifecycle, auditoría y operación `SUPERADMIN`
- Decisión de arquitectura: [ADR-0009](adr-0009-platform-control-plane.md)
- Operación: [runbook del control plane](../operations/platform-control-plane-runbook.md)

## Límite de esta evaluación

Este documento describe el código y las pruebas presentes en el checkout. No
certifica un ambiente desplegado ni atribuye `PASS` a un control por existir su
implementación o su test. En esta revisión no se ejecutaron PostgreSQL,
Testcontainers, Docker, navegador E2E, workflows de CI, backup/restore ni un
smoke operativo sobre el SHA candidato.

Los estados usados son deliberadamente estrictos:

- `IMPLEMENTED_NOT_RUN`: existen el control y una prueba automatizada relevante,
  pero no se ejecutó el gate integrado requerido sobre el candidato.
- `PARTIAL`: hay defensas útiles, pero falta una capa, una prueba adversarial o
  evidencia del entorno necesaria para cerrar el riesgo.
- `NOT_EXECUTED`: el control depende principalmente de un gate externo o de CI
  que no se ejecutó en esta revisión.

Ninguno de estos estados equivale a aceptación del riesgo, certificación ASVS o
release readiness.

## Sistema y fronteras de confianza

El control plane vive dentro del monolito Gestudio, pero mantiene fronteras
explícitas respecto del plano tenant:

1. El navegador conserva el access token de plataforma sólo en memoria y envía
   el refresh token en una cookie dedicada `HttpOnly`.
2. `/api/platform/**` acepta únicamente un principal de plataforma; los tokens
   tenant y platform tienen audiencia, scope y semántica diferentes.
3. La aplicación usa un runtime PostgreSQL de control plane separado del
   migrador y del runtime tenant. No se espera que tenga ownership,
   `SUPERUSER`, `BYPASSRLS` ni acceso funcional global.
4. Las operaciones que materializan roles o memberships abren contexto tenant
   sólo dentro de la transacción autorizada y continúan sujetas a RLS.
5. Los efectos operativos externos —TLS, proxy, custodia de recovery codes,
   backups, alertas y cadena de suministro— están fuera del proceso Java y
   requieren controles del ambiente.

### Activos

- identidades globales, hashes de contraseña y estado de activación;
- capacidad `PLATFORM_SUPERADMIN`, sesiones access/refresh y familias de
  refresh;
- secretos TOTP cifrados, contadores, recovery codes hasheados y pruebas de
  step-up;
- metadata de tenants, memberships, roles e idempotencia de provisioning;
- datos funcionales tenant protegidos por contexto y RLS;
- eventos de auditoría, correlación, métricas y logs;
- credenciales runtime/migrador, paquetes de backup, recovery codes exportados
  y artefactos de build.

### Actores

- administrador de plataforma legítimo;
- administrador o usuario tenant sin capacidad de plataforma;
- usuario anónimo o atacante web remoto;
- atacante con sesión, access token, refresh cookie o segundo factor robado;
- operador de despliegue, backup o recuperación;
- aplicación comprometida con una credencial runtime;
- migrador, dependencia, workflow o artefacto de cadena de suministro
  comprometido;
- insider con acceso a host, base, logs, backups o consola del proveedor.

## Matriz de amenazas

Las referencias `E-*` apuntan al [catálogo de evidencia](#catálogo-de-evidencia-estática).
Un test citado es fuente de evidencia pendiente, no un resultado ejecutado en
esta revisión.

| ID | Amenaza | Estado | Activo | Actor | Ruta de ataque | Impacto | Control preventivo | Control detective | Prueba / evidencia | Riesgo residual |
|---|---|---|---|---|---|---|---|---|---|---|
| T01 | Escalada tenant → plataforma | `IMPLEMENTED_NOT_RUN` | Capacidad platform y metadata global | Usuario tenant | Presentar token tenant, incluso con rol tenant llamado `SUPERADMIN`, ante `/api/platform/**` | Control global de tenants y administradores | Audiencia, scope, tipo de token y security chain separados; autoridad `PlatformPrincipal` obligatoria | Auditoría de denegaciones y métrica de authorization denial | E01, E02, E08 | Falta ejecutar la matriz HTTP/PG completa y E2E sobre el candidato |
| T02 | IDOR cross-tenant | `IMPLEMENTED_NOT_RUN` | Memberships y datos tenant | Platform admin o usuario tenant | Cambiar `tenantId`, membership o target de una solicitud autorizada | Lectura o mutación de otro tenant | IDs explícitos, autorización del target, contexto transaccional y RLS forzado; runtime platform sin grants funcionales globales | Auditoría con target/tenant/correlación | E07, E08, E09 | Falta evidencia ejecutada con dos tenants y consultas nativas reales |
| T03 | Inyección de contexto tenant | `IMPLEMENTED_NOT_RUN` | Frontera RLS | Cliente o código comprometido | Forzar un tenant mediante header, parámetro o conexión reutilizada | Bypass de aislamiento | El servidor deriva y acota `TenantContext`; no acepta un header como autoridad; limpieza del contexto y RLS fail-closed | Errores SQL/authorization denial y correlación | E07, E09 | La reutilización de conexiones y jobs debe revalidarse en PostgreSQL real |
| T04 | Manipulación de headers | `PARTIAL` | Origen, correlación e idempotencia | Atacante web o proxy | Falsificar `Origin`, request ID, idempotency o step-up headers | CSRF, confusión de auditoría o replay | Allowlist CORS exacta, validación explícita de origen en auth cookie, request ID sanitizado y proofs server-side | Correlación segura y auditoría de rechazo | E01, E12, E13 | No se probó la cadena proxy/CDN ni fuzzing de headers en navegador |
| T05 | Manipulación de claims JWT | `IMPLEMENTED_NOT_RUN` | Sesiones platform/tenant | Portador de token alterado | Cambiar scope, audiencia, tipo, versiones o incluir tenant en token platform | Suplantación o escalada | Firma y validación semántica de audiencia/scope/tipo; token platform excluye claims tenant; revalidación de versiones | Fallos de autenticación sin volcar el token | E01, E02, E08 | Falta ejecución integrada con claves/configuración finales |
| T06 | Mass assignment | `PARTIAL` | Estado de tenants, memberships y admins | Cliente autenticado | Agregar campos no previstos o estados/roles arbitrarios al JSON | Escalada o corrupción de lifecycle | DTOs explícitos, allowlists de estados y roles, mapeo server-side; tenant code inmutable | Auditoría de acción/resultado | E07, E14 | No hay evidencia de fuzzing genérico de propiedades; el backend permite estados válidos sin imponer todo el grafo de transición UI |
| T07 | CSRF | `PARTIAL` | Refresh/logout/activación y acciones privilegiadas | Sitio hostil desde navegador | Forzar requests con cookie refresh o credenciales del navegador | Toma/revocación de sesión o acción no deseada | Access token bearer en memoria, refresh cookie `SameSite`, validación exacta de `Origin` en endpoints con cookie y step-up para alto riesgo | Auth failures y auditoría de denegación | E01, E12, E15 | CSRF de Spring está deshabilitado; faltan pruebas adversariales en navegador y validación del edge real |
| T08 | XSS reflejado o DOM | `PARTIAL` | Sesión en memoria y acciones platform | Atacante que controla URL o texto mostrado | Inyectar script en error, query, ruta o mensaje | Robo del access token o acción como admin | Escapado de React, CSP `script-src 'self'`, `object-src 'none'`, sin HTML arbitrario previsto | Reportes CSP externos no están configurados; correlación ayuda al análisis | E14, E15 | No se ejecutó browser E2E/CSP contra payloads; un XSS mismo-origen aún alcanzaría el token en memoria |
| T09 | Stored XSS en nombres de tenant/usuario | `PARTIAL` | UI platform y operadores | Admin tenant o dato importado | Persistir HTML/JS en nombre y renderizarlo en listas/detalle/auditoría | Compromiso de sesiones administrativas | SQL parametrizado, React representa texto de forma literal y CSP restringe scripts | Auditoría conserva snapshots para rastreo | E07, E14 | Falta recorrido E2E real de escritura, lectura y exportaciones futuras con payloads adversariales |
| T10 | Robo de sesión | `PARTIAL` | Access token y refresh cookie platform | XSS, malware o atacante local | Leer memoria del navegador, cookie o perfil | Acceso privilegiado hasta revocación/expiración | Access token sólo en memoria; refresh `HttpOnly`, `Secure` por defecto y separado por path; expiración y security versions | Métricas de auth, sesiones revocables y auditoría | E01, E04, E05 | No hay device binding; no se probó TLS/host/browser final ni detección de anomalías |
| T11 | Abuso de refresh token | `IMPLEMENTED_NOT_RUN` | Familias refresh | Portador de cookie robada | Reusar token rotado, usarlo vencido o tras cambio de seguridad | Persistencia del atacante | Hash en DB, rotación, detección de reuse con revocación de familia, expiración, audience/scope y versionado | Motivo de revocación y auth failure | E01, E04, E05 | Falta ejecución PostgreSQL y concurrencia real sobre el candidato |
| T12 | Bypass de MFA | `IMPLEMENTED_NOT_RUN` | Login platform y acciones críticas | Atacante con contraseña | Omitir TOTP/recovery, reutilizar contador o enviar código inválido | Acceso `SUPERADMIN` | Login platform exige segundo factor; secreto AES-GCM; verificación TOTP con contador anti-replay; rate limit persistido | Fallos MFA y métrica de autenticación | E02, E03, E05 | Falta ejecutar reloj, concurrencia y configuración criptográfica final |
| T13 | Abuso de recovery MFA | `PARTIAL` | Recovery codes y reset MFA | Atacante u operador | Reutilizar código, capturar archivo one-shot o abusar del reset | Toma de cuenta persistente | Códigos hasheados y one-use; archivo bootstrap con ACL restringida; reset exige step-up de otro admin y revoca sesiones | Auditoría de reset/uso y postcondiciones del bootstrap | E03, E06, E07, E11 | Custodia y entrega externa no están certificadas; no hay procedimiento break-glass documentado si se pierde el único acceso |
| T14 | Escalada de roles | `IMPLEMENTED_NOT_RUN` | Roles tenant y capacidad platform | Admin tenant o platform comprometido | Autoasignarse capacidad global, asignar roles fuera del tenant o remover último admin | Pérdida de control de acceso | Tablas/capacidades separadas, roles seleccionados por código válido del tenant, step-up y protección del último administrador | Auditoría de grant/status/roles y denegaciones | E07, E08, E09 | Falta ejecución real de matrices, concurrencia y acceso DB restringido |
| T15 | Provisioning duplicado | `IMPLEMENTED_NOT_RUN` | Tenant, roles e identidad inicial | Retries, dos operadores o cliente malicioso | Repetir creación con misma o distinta carga | Duplicados, tokens múltiples o estado parcial | Idempotency key + hash de payload, UUID determinístico y transacción única; replay igual no reexpone activación | Registro de idempotencia y auditoría correlacionada | E07 | Falta ejecutar simultaneidad sobre PostgreSQL real |
| T16 | Replay de operación privilegiada | `IMPLEMENTED_NOT_RUN` | Step-up, activaciones, provisioning y MFA | Portador de request/token previo | Reusar proof, token de activación, TOTP o idempotency key | Repetición de alta, reset o cambio de estado | Proof ligado a usuario/sesión/acción/target/idempotencia, TTL y consumo único; activación hasheada/purpose-bound; TOTP anti-replay | Auditoría de éxito/denegación y estado consumido | E03, E05, E06, E07 | Falta ejecución integrada con concurrencia y reloj del entorno |
| T17 | Race conditions | `IMPLEMENTED_NOT_RUN` | Último admin, membresías, sesiones y provisioning | Requests concurrentes | Intercalar grants/revokes/rotaciones o replay | Lockout, doble creación o autorización obsoleta | Locks/transacciones, constraints, optimistic security versions e idempotencia | Conflictos y auditoría por correlación | E05, E07 | La prueba fuente no sustituye carga concurrente ni ejecución PG actual |
| T18 | Manipulación de auditoría | `IMPLEMENTED_NOT_RUN` | `platform_audit_events` | Runtime comprometido o insider DB | Actualizar/borrar eventos o evitar su escritura | Pérdida de trazabilidad | Trigger append-only rechaza `UPDATE/DELETE`; runtime limitado a `SELECT/INSERT`; acciones críticas auditan éxito y denegación | Reconciliación de eventos por correlación | E07, E09, E10 | Un owner/migrador/DBA sigue siendo actor privilegiado; falta validación de backup/restore de auditoría |
| T19 | Inyección de logs | `PARTIAL` | Logs y correlación | Cliente remoto | Insertar CR/LF/tab o payloads en request ID/campos logueados | Falsificación de eventos u ocultamiento | Request ID sanitizado; contrato de logs omite query, body, auth, cookies y secretos; snapshots mínimos | Correlación HTTP/auditoría y métricas | E01, E13 | No se probó el colector/visualizador final ni todos los campos de metadata frente a caracteres de control |
| T20 | Fuga de credenciales | `PARTIAL` | Passwords, JWT, TOTP, cookies, tokens one-shot y credenciales DB | Operador, atacante o dependencia | CLI, logs, errores, Git, memoria, entorno, artefactos o token de activación colocado en query/history/referrer | Compromiso total o toma de una identidad pendiente | Secretos externos, `SecureString` en bootstrap, respuestas no exponen refresh, no logging de auth/body; la UI emite el enlace completo con `#token`, rechaza el query, captura el fragmento sólo en memoria y hace `replace` antes del paint; el borde aplica `no-referrer` a activación sin perder CSP ni los demás headers | Secret scan definido, revisión de logs y contratos frontend/header | E01, E11, E13, E14, E16 | El secret scan/CI y el borde HTTP real no se ejecutaron; memoria de proceso, historial previo a cargar la app, canal de entrega, host y proveedor quedan fuera del control de la app |
| T21 | Fuga de credenciales seed | `IMPLEMENTED_NOT_RUN` | Primer admin y baseline fresh | Operador o consumidor del artefacto | Credencial default en migración, imagen o arranque | Cuenta conocida universal | B12 fresh sin usuarios/admins; bootstrap deshabilitado por defecto; job explícito sin defaults y recuperación no impresa | Postcondición bootstrap y reconciliación fresh | E10, E11 | Falta ejecutar baseline fresh y ceremonia completa sobre el candidato |
| T22 | Abuso de privilegios de migración | `IMPLEMENTED_NOT_RUN` | Esquema, ACL y RLS | Aplicación comprometida o credencial migrador robada | Ejecutar DDL o usar ownership/BYPASSRLS desde runtime | Bypass total o persistencia | Credenciales Flyway/runtime separadas; runtime platform sin ownership, creación, superusuario ni bypass; migraciones forward-only | Validación de catálogo, schema history y health | E09, E10 | Migrador y DBA conservan privilegio alto; rotación/custodia del entorno no están probadas |
| T23 | Fuga de backup | `PARTIAL` | Dump, recibos y metadata histórica | Operador, malware o storage externo | Leer paquete sin autorización o extraer PII | Exposición masiva y persistente | Manifiesto con hashes; configuración/secretos fuera del paquete; ACL/custodia exigidas por runbook | Validación de manifiesto y drill de restore | E17 | El paquete no aporta cifrado automático; custodia, retención y RPO/RTO externos están pendientes |
| T24 | Compromiso de supply chain | `NOT_EXECUTED` | Código, dependencias, actions, imágenes y SBOM | Dependencia o workflow comprometido | Paquete malicioso, action mutable o artefacto sustituido | Ejecución arbitraria y fuga de secretos | Workflows definen CodeQL, auditorías, dependency review, secret scan, política de Actions y SBOM | Checks de GitHub y metadata de artefacto | E16 | Ningún workflow ni artefacto fue verificado sobre el SHA candidato |
| T25 | CORS mal configurado | `PARTIAL` | API y cookies de autenticación | Sitio web hostil u operador | Wildcard/HTTP/origen no autorizado con credenciales | Requests cross-origin privilegiados | Orígenes exactos, credentials controladas, guard de producción para CORS; `SameSite=None` requiere `Secure` | Preflight/origin failures y tests de configuración | E01, E12 | No se verificó el proxy final; el guard de producción no demuestra explícitamente `Secure=true` para toda configuración de cookie refresh platform |
| T26 | Open redirect | `PARTIAL` | Activación y navegación platform | Atacante de phishing | Inyectar URL de retorno o conservar token en ubicación navegable | Phishing o filtración de token | Rutas internas explícitas; activación elimina el token de la URL; no se documenta redirect arbitrario server-side | Correlación de activación | E06, E14 | No existe evidencia adversarial dedicada para esquemas, hosts y parámetros de retorno futuros |
| T27 | Enumeración de usuarios/tenants | `PARTIAL` | Identidades y catálogo tenant | Anónimo o platform admin abusivo | Diferenciar errores/tiempos de login o consultar búsquedas amplias | Descubrimiento de cuentas y estructura comercial | Errores de auth acotados, rate limit persistido; búsquedas sólo bajo sesión platform; paginación | Métricas de auth y auditoría de las mutaciones posteriores | E01, E03, E07 | No hay prueba de timing/volumen ni detección específica de scraping de consultas autenticadas |
| T28 | Bypass de autorización por acceso DB directo | `IMPLEMENTED_NOT_RUN` | Datos tenant y control-plane | Proceso con credencial runtime | Ejecutar SQL fuera de controladores/servicios | Lectura o mutación sin RBAC | Least privilege, roles separados, RLS forzado y grants acotados; contexto requerido para DML tenant dirigido | Errores SQL, health de ACL/RLS y auditoría de catálogo | E07, E09, E10 | DBA/migrador están fuera de esta frontera; falta ejecutar catálogo, restore y consultas negativas actuales |

## Catálogo de evidencia estática

Estas fuentes fueron inspeccionadas como contratos implementados. El estado de
esta revisión no afirma que hayan sido ejecutadas:

- **E01** —
  [`PlatformSecurityHttpTest`](../../backend/src/test/java/gestudio/platform/security/PlatformSecurityHttpTest.java):
  matriz anónimo/tenant/platform, cookies, refresh/logout, origen, rate limit,
  activación, step-up y respuestas `no-store`.
- **E02** —
  [`PlatformCryptographyTest`](../../backend/src/test/java/gestudio/platform/security/PlatformCryptographyTest.java):
  TOTP/Base32, AES-GCM, audiencia/scope/tipo JWT y configuración criptográfica.
- **E03** —
  [`PlatformMfaServiceTest`](../../backend/src/test/java/gestudio/platform/security/PlatformMfaServiceTest.java):
  anti-replay TOTP, bloqueo, recovery one-shot, cifrado y hashes.
- **E04** —
  [`PlatformRefreshSessionServiceTest`](../../backend/src/test/java/gestudio/platform/security/PlatformRefreshSessionServiceTest.java):
  hash, rotación, reuse, expiración, versiones y logout idempotente.
- **E05** —
  [`PlatformSessionStepUpPostgreSqlTest`](../../backend/src/test/java/gestudio/platform/security/PlatformSessionStepUpPostgreSqlTest.java):
  familias refresh y proof de step-up ligado, expirable y one-shot en PostgreSQL.
- **E06** —
  [`PlatformIdentityActivationPostgreSqlTest`](../../backend/src/test/java/gestudio/platform/security/PlatformIdentityActivationPostgreSqlTest.java):
  activación, enrolamiento/reset MFA, expiración y TOTP incorrecto.
- **E07** —
  [`PlatformControlPlanePostgreSqlTest`](../../backend/src/test/java/gestudio/platform/control/PlatformControlPlanePostgreSqlTest.java):
  provisioning atómico/concurrente, lifecycle, último admin, proofs, XSS literal,
  RLS, privilegios y auditoría append-only.
- **E08** —
  [`SecurityHttpIntegrationTest`](../../backend/src/test/java/gestudio/infra/seguridad/SecurityHttpIntegrationTest.java):
  auth tenant, tokens inválidos, separación platform, autorización, CORS y
  errores seguros.
- **E09** —
  [`ApplicationRoleAuthenticationPostgreSqlTest`](../../backend/src/test/java/gestudio/infra/seguridad/ApplicationRoleAuthenticationPostgreSqlTest.java):
  roles reales, restricciones y reutilización de conexión.
- **E10** —
  [`PostgreSqlSchemaValidationTest`](../../backend/src/test/java/gestudio/infra/persistencia/PostgreSqlSchemaValidationTest.java):
  Flyway fresh/upgrade, equivalencia B12 y validación de esquema.
- **E11** —
  [`SuperadminBootstrapPostgreSqlTest`](../../backend/src/test/java/gestudio/infra/seguridad/SuperadminBootstrapPostgreSqlTest.java),
  [`SuperadminBootstrapRunnerTest`](../../backend/src/test/java/gestudio/infra/seguridad/SuperadminBootstrapRunnerTest.java)
  y
  [`bootstrap-platform-admin.ps1`](../../scripts/ops/bootstrap-platform-admin.ps1):
  claim, transacción, runner condicional y ceremonia externa.
- **E12** —
  [`ConfiguracionCorsTest`](../../backend/src/test/java/gestudio/infra/configuracion/ConfiguracionCorsTest.java),
  [`ProductionConfigurationGuardTest`](../../backend/src/test/java/gestudio/infra/configuracion/ProductionConfigurationGuardTest.java)
  y
  [`MultitenancyConfigurationGuardTest`](../../backend/src/test/java/gestudio/infra/configuracion/MultitenancyConfigurationGuardTest.java).
- **E13** —
  [`ObservabilityPostgreSqlTest`](../../backend/src/test/java/gestudio/infra/observabilidad/ObservabilityPostgreSqlTest.java)
  y [contrato de observabilidad](../operations/observability.md).
- **E14** — tests unitarios y de componentes bajo
  [`frontend/src/platform`](../../frontend/src/platform), más
  [`AppRouter.test.tsx`](../../frontend/src/rutas/AppRouter.test.tsx) y
  [`ProtectedRoute.test.tsx`](../../frontend/src/rutas/ProtectedRoute.test.tsx).
- **E15** —
  [`control-plane.spec.ts`](../../frontend/e2e/control-plane.spec.ts): harness
  browser presente, con ejecución runtime `NOT_EXECUTED` en esta revisión.
- **E16** —
  [`security-supply-chain.yml`](../../.github/workflows/security-supply-chain.yml)
  y [`quality-fortress.yml`](../../.github/workflows/quality-fortress.yml):
  workflows presentes, estado `NOT_EXECUTED` sobre el candidato.
- **E17** —
  [`backup-postgres.ps1`](../../scripts/ops/backup-postgres.ps1),
  [`restore-postgres.ps1`](../../scripts/ops/restore-postgres.ps1),
  [`verify-backup-restore.ps1`](../../scripts/ops/verify-backup-restore.ps1) y
  [runbook de backup/restore](../operations/backup-restore.md): contratos
  presentes, con ejecución `NOT_EXECUTED` en esta revisión.

## Correspondencia OWASP ASVS

Esta es una correspondencia temática a capítulos de OWASP ASVS 4.x para guiar
la verificación. No es un checklist requisito por requisito, no determina un
nivel ASVS y no constituye certificación. No se asigna `PASS` a ninguna fila.

| Área ASVS | Cobertura del control plane | Estado | Evidencia y brecha principal |
|---|---|---|---|
| V1 Arquitectura | Fronteras tenant/platform, roles DB, RLS, bootstrap y ADR | `PARTIAL` | ADR y threat model existen; falta revisión independiente y evidencia de despliegue |
| V2 Autenticación | Password, TOTP/recovery, activación, rate limit y MFA reset | `IMPLEMENTED_NOT_RUN` | E01–E03, E05–E07 y E11 pendientes de ejecución integrada |
| V3 Gestión de sesión | Token en memoria, cookie refresh, rotación/reuse, logout y versiones | `IMPLEMENTED_NOT_RUN` | E01, E04 y E05; falta navegador/TLS final |
| V4 Control de acceso | Principal platform, separación de scopes, step-up, último admin y RLS | `IMPLEMENTED_NOT_RUN` | E01, E07–E09; falta matriz completa sobre PostgreSQL actual |
| V5 Validación, sanitización y encoding | DTOs/allowlists, SQL parametrizado, React y CSP | `PARTIAL` | E07 y E14; faltan fuzzing y E2E XSS/mass-assignment |
| V6 Criptografía almacenada | AES-GCM para TOTP, hashes de tokens/recovery y versionado de clave | `IMPLEMENTED_NOT_RUN` | E02–E06; faltan ejecución con configuración final, rotación y custodia externa de claves |
| V7 Errores, logging y auditoría | Errores acotados, correlación, eventos append-only y métricas | `PARTIAL` | E01, E07 y E13; sin colector/alertas externos ni clasificación recursiva probada |
| V8 Protección de datos | Cifrado TOTP, hashes, no-secret logging y backups con manifiesto | `PARTIAL` | Cifrado/custodia externa de backups y host no certificados |
| V9 Comunicaciones | HTTPS/CORS/cookies seguras previstos por configuración | `NOT_EXECUTED` | No se verificaron TLS, proxy, headers ni dominios de staging/producción |
| V10 Código malicioso y supply chain | CodeQL, dependency/secret scan, política Actions y SBOM | `NOT_EXECUTED` | E16 no ejecutada; no hay artefacto publicado verificable |
| V11 Lógica de negocio | Idempotencia, locks, versiones, lifecycle y protección del último admin | `PARTIAL` | E05 y E07 pendientes; el backend no impone por sí solo todo el grafo de transición tenant |
| V12 Archivos y recursos | Recovery one-shot, ACL local, recibos y paquete de backup | `PARTIAL` | Entrega, retención, cifrado y borrado seguro dependen de operación externa |
| V13 API y servicios web | Authz backend, DTOs, paginación, idempotencia y `no-store` | `IMPLEMENTED_NOT_RUN` | E01, E06 y E07; falta E2E y pruebas de volumen |
| V14 Configuración | Guards, secretos externos, datasource separado y baseline seedless | `PARTIAL` | E10–E12 pendientes; permanece la brecha del guard `Secure` de cookie platform |

## Criterios para cerrar esta revisión

El estado sólo puede elevarse con evidencia ligada al mismo SHA candidato:

1. backend `clean verify` con PostgreSQL/Testcontainers y matriz tenant/platform;
2. fresh B12 y upgrades soportados con catálogo de roles, grants, owners y RLS;
3. E2E browser real de login, activación, lifecycle, step-up, XSS, CSRF y logout;
4. bootstrap y recuperación one-shot en un proyecto descartable y no protegido;
5. backup/restore con ACL, auditoría, sesiones y smoke posterior;
6. workflows de Quality Fortress y supply chain concluidos sobre ese SHA;
7. validación del ambiente autorizado: TLS, CORS, cookies, CSP, logging,
   alertas, custodia de secretos/backups y respuesta a incidentes.

Hasta completar esos gates, el threat model permanece `PARTIAL` y no habilita
una declaración de `RELEASE_READINESS=PASS`.
