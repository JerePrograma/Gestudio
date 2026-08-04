# Autorreferencia operativa de Gestudio

## Identidad del repositorio

- Ruta local: `C:\laburo\Gestudio`.
- Remoto: `https://github.com/JerePrograma/Gestudio.git`.
- Rama: `main`.
- HEAD inicial: `1d8ad314abdb3efa0ab9704395c2505b98087672`.
- origin/main inicial después de `git fetch origin`: `1d8ad314abdb3efa0ab9704395c2505b98087672`.
- Fecha y hora de inicio: `2026-08-04T14:25:30-03:00`.
- Continuidad reanudada: `2026-08-04`; `git fetch origin` volvió a confirmar
  `HEAD == origin/main == 1d8ad314abdb3efa0ab9704395c2505b98087672`, sin
  staging, conflictos ni worktrees adicionales.
- Worktrees: solo `C:\laburo\Gestudio`, asociado a `refs/heads/main`.

## Restricciones

- Publicación directa y normal sobre `main`; sin rama nueva, PR, worktree alternativo ni force push.
- Sin `reset --hard`, `clean`, `restore`, `stash`, `rebase` ni reescritura de historial.
- Demo estable, proyecto Docker `gestudio-remote-demo`, puertos `18080`, `18081` y `15432` protegidos.
- Java 21 Corretto limitado al proceso; sin modificar variables globales.
- Sin secretos ni credenciales reales; los valores de tests deben ser ficticios y aislados.
- Sin staging hasta completar gates, diff review, limpieza y secret scan.

## Estado inicial de Git

- Rama alineada: `HEAD == origin/main`; fetch correcto; sin conflictos.
- Staged: ninguno.
- Modificados tracked: 82. Clasificación actual: desarrollo multitenancy heredado
  revisado por familias; repetir la revisión final antes del staging.
  - Configuración/runtime: `.env.example`, `.env.local.example`, `backend/src/main/resources/application-dev.yml`, `application-prod.yml`, `application-remote-demo.yml`, `application.yml`, `docker-compose.prod.yml`, `docker-compose.remote-demo.yml`, `docker-compose.yml`.
  - Auth/API/modelo: `AuditService.java`, `AutenticacionControlador.java`, `UsuarioControlador.java`, `LoginRequest.java`, `UsuarioResponse.java`, `RefreshSession.java`, `Usuario.java`, `AutenticacionService.java`, `LocalAdminPasswordResetRunner.java`, `RbacService.java`, `RefreshSessionService.java`, `SecurityConfigurations.java`, `SecurityFilter.java`, `SuperadminBootstrapService.java`, `TokenService.java`, `UsuarioDetailsService.java`, `VerifiedToken.java`, `UsuarioRepositorio.java`, `RefreshSessionRepositorio.java`.
  - Consumidores tenant-aware: `SourceTenantMapping.java`, `StudentSourceExportService.java`, `StudentSourceExportProperties.java`, `StudentSourceExportStore.java`, `NotificacionRepositorio.java`, `ScheduledTasks.java`, `EmailAsyncService.java`, `NotificacionService.java`, `ReciboStorageService.java`, `RolServicio.java`, `UsuarioServicio.java`, `CondicionEconomicaServicio.java`, `TarifaDisciplinaServicio.java`.
  - Tests backend: `RuntimeProfilesTest.java`, `ObservabilityPostgreSqlTest.java`, `IdempotenciaCanonicaPostgreSqlTest.java`, `PostgreSqlIntegrationTest.java`, `PostgreSqlSchemaValidationTest.java`, `AutenticacionServiceTest.java`, `LocalAdminPasswordResetRunnerTest.java`, `RefreshSessionPostgreSqlTest.java`, `SecurityHttpIntegrationTest.java`, `TokenServiceTest.java`, `SourceTenantMappingTest.java`, `StudentSourceExportCryptoTest.java`, `StudentSourceExportPostgreSqlTest.java`, `StudentSourceExportServiceTest.java`, `CargoSaldoPostgreSqlTest.java`, `EmailAsyncServiceTest.java`, `NotificacionIdempotenciaPostgreSqlTest.java`, `NotificacionServiceTest.java`, `PagoCanonicoPostgreSqlTest.java`, `ReciboPathResolverTest.java`, `ReciboStorageServiceTest.java`, `RolServicioTest.java`, `UsuarioServicioTest.java`, `CondicionEconomicaPostgreSqlTest.java`, `TarifaDisciplinaPostgreSqlTest.java`.
  - Frontend: `authSession.ts`, `axiosConfig.test.ts`, `axiosConfig.ts`, `Header.tsx`, `auth-context.test.ts`, `auth-context.ts`, `authContext.tsx`, `queryClient.ts`, `Login.test.tsx`, `Login.tsx`, `types.ts`.
  - Documentación/operación: `README.md`,
    `docs/architecture/multitenancy-governance-and-health.md`,
    `docs/development/local-development.md`,
    `scripts/deploy-remote-demo-public.ps1`,
    `scripts/ops/verify-email-delivery.ps1`.
- Untracked iniciales: 46. Clasificación actual: implementación, migraciones,
  pruebas y documentación multitenancy legítimas revisadas por familias.
  - Config/API/receipts: `MultitenancyConfigurationGuard.java`, `TenantMappingController.java`, `ReceiptNamespaceMigrator.java`.
  - Paquete `gestudio.tenancy`: `PlatformAdmin.java`, `PlatformAdminAccessService.java`, `PlatformAdminRepository.java`, `Tenant.java`, `TenantAccess.java`, `TenantAccessService.java`, `TenantAwareDataSource.java`, `TenantContext.java`, `TenantDataSourceConfiguration.java`, `TenantExecutionService.java`, `TenantMembership.java`, `TenantMembershipManagementService.java`, `TenantMembershipRepository.java`, `TenantMembershipRole.java`, `TenantMembershipRoleId.java`, `TenantMembershipRoleRepository.java`, `TenantMembershipStatus.java`, `TenantMetrics.java`, `TenantPlatformController.java`, `TenantProvisioningService.java`, `TenantRepository.java`, `TenantSelection.java`, `TenantStatus.java`, `TenantStructuralHealthIndicator.java`, `TenantSummaryResponse.java`.
  - Flyway: `V8__tenant_control_plane.sql`, `V9__tenant_domain_isolation.sql`, `V10__tenant_rls_and_health.sql`, `V11__foreign_key_index_coverage.sql`.
  - Tests: `AuditServiceTest.java`, `MultitenancyConfigurationGuardTest.java`, `ApplicationRoleAuthenticationPostgreSqlTest.java`, `TenantTestAccess.java`, `PlatformAdminAccessServiceTest.java`, `TenantAwareDataSourceTest.java`, `TenantContextTest.java`, `TenantExecutionServiceTest.java`, `TenantMetricsTest.java`, `TenantStructuralHealthIndicatorTest.java`, `frontend/src/hooks/context/authContext.test.tsx`.
  - Documentación/operación: `docs/CODEX_AUTORREFERENCIA_GESTUDIO.md`,
    `docs/architecture/adr-0008-shared-schema-multitenancy.md`,
    `scripts/db/10-create-application-role.sh`.
- Artefactos: no hay candidatos tracked/untracked `*.patch`, `*.diff`, `*.rej`,
  `*.orig`, `*.bak`, `*.tmp`, ZIP, dumps, logs, `.env` real, `target`,
  `node_modules`, `coverage` ni `dist`.

## Recursos protegidos

- Repositorio: `C:\laburo\Gestudio-Demo-Stable`; remoto correcto; rama `main`; commit `1d8ad314abdb3efa0ab9704395c2505b98087672`; árbol/index limpios; 0 untracked.
- Proyecto Docker: `gestudio-remote-demo`. La inspección histórica inicial fue
  `BLOCKED_EXTERNAL`; en la continuidad Docker Desktop 4.67.0 volvió a estar
  disponible con Engine 29.3.1 y contexto `desktop-linux`, sin que Codex lo
  iniciara ni modificara.
- Fotografía protegida de continuidad: backend
  `0d7622933694be26eec11cda005975cb6f464b2c2e7a0f9b4309448373a7d495`
  (`gestudio-backend:remote-demo`, healthy, `127.0.0.1:18080`) y PostgreSQL
  `e5309bcba05d1e6d57776755308b7cf7010dc04aa9222ebf06c3bcc17dcc8614`
  (`postgres:15.18-alpine3.24`, healthy, sin puerto host). Sólo se ejecutaron
  `docker version/info/context/ps/compose ls` e `inspect` de campos no sensibles.
- Estado público: `public-deployment.json` presente, 679 bytes, SHA-256 `317AB6C7DC3C19439F2DC998FA3166C9DBCF1BCE7D2987050B6108A2324C04B2`, sin leer ni registrar valores sensibles.
- Cloudflared: no hay proceso `cloudflared.exe` visible en la continuidad.
- Frontend público: `GET https://gestudio-demo-jere-287b8c90.pages.dev` = 200 HTML.
- Backend protegido en la continuidad: `GET /api/usuarios/perfil` = 404 vacío;
  `GET /actuator/health/readiness` = 200. No se inició ni reinició el runtime.
- No se ejecutó ninguna acción de escritura ni migración sobre la demo.
- Verificación previa al staging: repositorio estable en el mismo SHA y limpio;
  ambos contenedores conservan ID, imagen, estado healthy y puertos; estado
  público conserva 679 bytes, fecha de modificación y SHA-256
  `317AB6C7DC3C19439F2DC998FA3166C9DBCF1BCE7D2987050B6108A2324C04B2`;
  frontend público 200 HTML, perfil anónimo 404 vacío y readiness 200.
- Existe un contenedor PostgreSQL 17 detenido y etiquetado históricamente por
  Testcontainers; es ajeno, no se usó y no se eliminó ni modificó.
- La verificación final histórica de la intervención anterior encontró Docker
  detenido. No describe el estado actual; la comparación final de esta
  continuidad debe usar los dos IDs protegidos anteriores.

## Objetivo técnico actual

- Defecto heredado confirmado y corregido: el login con rol PostgreSQL real
  fallaba `SQLSTATE 42501 tenant context missing` por cargar roles/permisos
  protegidos por RLS antes de seleccionar tenant.
- Alcance: cerrar autenticación, refresh/access token, membership/versiones, RLS/grants/datasource, migraciones V1-V11 y V7-V11, frontend, documentación, validación, commit y push.
- Contratos principales: `CredencialesAutenticacion`, `TenantSelection`, `TenantAccess`, claims JWT, `TenantContext`, datasource runtime y DTOs de sesión.

## Mapa de archivos relevantes

| Ruta | Símbolo | Responsabilidad | Estado | Riesgo |
|---|---|---|---|---|
| `UsuarioRepositorio.java` | `CredencialesAutenticacion` | Credenciales globales sin roles | corregido | RLS pre-tenant/TOCTOU |
| `UsuarioDetailsService.java` | `loadUserByUsername` | Identidad inicial | corregido | carga implícita |
| `AutenticacionService.java` | `login`/selección | Login y emisión | corregido | tokens sin acceso válido |
| `SecurityFilter.java` | `doFilterInternal` | Revalidación request | PostgreSQL PASS | contexto/authorities |
| `RefreshSessionService.java` | refresh/rotate | Refresh ligado a acceso | PostgreSQL PASS | replay/versiones |
| `TenantAccessService.java` | `activeSelections`/`revalidate` | Acceso tenant-aware | PostgreSQL PASS | fallo abierto/joins RLS |
| `TenantMembershipRepository.java` | queries | Control plane y domain plane | PostgreSQL PASS | consulta sin contexto |
| `TenantAwareDataSource.java` | `prepare`/`close` | `set_config` y limpieza | PostgreSQL PASS | fuga descartada en conexión física reutilizada |
| `V8`-`V11` | migraciones | control plane, aislamiento, RLS, índices | PostgreSQL y clean verify PASS | V1-V7 intactas; publicación pendiente |
| `ApplicationRoleAuthenticationPostgreSqlTest.java` | integración real | migrador separado/runtime no privilegiado | PostgreSQL y clean verify PASS | aviso de API deprecada no bloqueante |
| `AutenticacionServiceTest.java` | helper `credenciales` | regresión login/versiones | corregido, 6 tests | carrera de identidad |

## Hechos confirmados

- `git fetch origin` ejecutado correctamente; SHAs iniciales iguales.
- Una única worktree; sin staged, conflictos ni archivos ajenos detectados.
- `UsuarioRepositorio.CredencialesAutenticacion` es una interface projection global; ahora expone id, nombre, hash, activo y `authVersion` sin materializar `Usuario` ni su rol legacy.
- La proyección nativa consulta solo `usuarios`; el helper unitario usa el
  record inmutable `Credenciales`, sin stubbing Mockito anidado.
- `TenantAccessService.activeSelections` obtiene candidatos control-plane y valida cada uno dentro de `TenantContext`.
- `TenantAwareDataSource` usa `set_config(..., false)` al adquirir y limpia antes
  de devolver la conexión; PostgreSQL reutilizó el mismo `pg_backend_pid` para
  tenant inicial, ausencia de contexto y tenant secundario sin fuga.
- `refresh_sessions` ya era tenant-aware desde V8 y todos sus flujos productivos abren `TenantContext`, pero V10 la concedía como control plane sin RLS: aislamiento contradictorio con el modelo y la documentación.
- `LocalAdminPasswordResetRunner`, habilitable sólo en `dev`, era el único consumidor productivo localizado que cargaba roles sin abrir tenant; ahora opera en el tenant inicial y cierra el scope.
- `AuditService` persistía `actor_role_snapshot` desde `Usuario.rol` legacy; la membership activa es la autoridad correcta cuando existe contexto.
- El test de upgrade existente partía de V5; se reutilizó para materializar V7, insertar datos V7 representativos y migrar desde allí a la última versión descubierta por Flyway.
- Línea base de demo registrada; frontend y runtime protegido responden,
  `cloudflared` no está activo y Docker sólo se inspeccionó en lectura.
- Toolchain verificado por proceso: Maven 3.9.10 y Java 21.0.7 Amazon Corretto desde `C:\Program Files\Java\corretto-21.0.7`.
- Fallo focalizado reproducido: los 5 casos de `AutenticacionServiceTest` terminan en `UnfinishedStubbingException` desde `credenciales()`; 0 fallos de aserción y 5 errores de infraestructura Mockito.
- `Usuario.rol` era EAGER por defecto: una identidad global con memberships en dos tenants podía materializar el rol legacy del tenant A dentro del contexto B. No quedan consumidores productivos directos de `getRol()`; la asociación pasó a LAZY y el test PostgreSQL cubre ambos tenants.
- La proyección inicial carecía de `authVersion`: un cambio concurrente de contraseña podía autenticar el hash anterior y emitir un token con la versión nueva cargada después. El login compara la identidad global validada con la entidad tenant-bound antes de emitir tokens.
- Frontend auditado: selección por `409`, tenant activo, refresh ligado al mismo tenant, rotación de cache/scope y cambio de tenant preservan el contrato. El interceptor pisaba el `AbortSignal` del caller; ahora combina ambas cancelaciones mediante `AbortSignal.any`.
- V8 omitía un SUPERADMIN legacy del backfill de `platform_admins` cuando el mismo usuario tenía cualquier rol suplementario no SUPERADMIN: `COALESCE(ur.rol_id, u.rol_id)` ocultaba `u.rol_id`.
- La función `SECURITY DEFINER` de health no necesita resolver objetos desde `public`; su `search_path` se restringió a `pg_catalog` y su owner/configuración quedan comprobados por PostgreSQL real.
- V11 consideraba un índice parcial como cobertura completa de una FK; ahora sólo acepta índices no parciales y la prueba de catálogo usa el mismo criterio.
- `SuperadminBootstrapService` y el alta de usuarios insertan la asociación legacy compatible en `usuario_roles`, pero V10 sólo concedía `SELECT` al runtime; el bootstrap real habría fallado por permisos.
- `SuperadminBootstrapService` y `LocalAdminPasswordResetRunner` abrían `TenantContext` dentro de un método `@Transactional`; el transaction manager podía adquirir antes una conexión configurada sin tenant.
- `TarifaDisciplinaServicio` y `CondicionEconomicaServicio` eran los últimos consumidores productivos de `Usuario.tienePermiso`: recargaban `usuario_roles` legacy y autorizaban fuera del contrato de la membership activa.
- La guía vigente de desarrollo todavía describía V1-V7 como cadena actual; los documentos históricos y de la demo sí deben conservar ese corte, pero README y desarrollo local debían distinguir V1-V11 del árbol actual y la demo estable protegida en V7.

## Comprobaciones finales

- Los 128 paths candidatos fueron reclasificados y continúan íntegramente
  atribuidos al desarrollo multitenancy; no hay paths sospechosos ni ajenos.
- Documentación, secretos, recursos protegidos, artefactos, V1-V7, lockfile y
  diff fueron revisados; identidad/origen e index explícito fueron revalidados.
  Faltan únicamente commit, push y la fotografía protegida posterior.

## Cambios implementados

- En la continuidad actual no fue necesario modificar código productivo,
  migraciones ni pruebas: PostgreSQL real confirmó las correcciones heredadas.
  Se actualizaron esta autorreferencia y el estado normativo de gobernanza con
  la evidencia ejecutada.
- `AutenticacionServiceTest.credenciales`: reemplazado el mock Mockito anidado por el record inmutable privado `Credenciales`, implementación exacta de los cinco getters de la proyección. No cambió el contrato productivo ni los asserts.
- `AuditService.actorRoleSnapshot`: el snapshot usa `TenantAccessService.currentAccess` sólo con tenant y membership presentes; ausencia o denegación produce `null`, fallos de infraestructura no se ocultan. Añadido `AuditServiceTest`.
- `LocalAdminPasswordResetRunner.run`: abre el tenant inicial antes de consultar el rol administrativo y garantiza el cierre del contexto; el test comprueba que no queda contexto residual.
- `V10__tenant_rls_and_health.sql`: `refresh_sessions` pasa a RLS forzado con política `USING`/`WITH CHECK`; grant tenant-aware separado y health actualizado a 40 tablas RLS, 39 discriminadores/políticas y 38 defaults.
- `ApplicationRoleAuthenticationPostgreSqlTest`: conserva login/filtro real y añade atributos/ownership del rol, RLS de refresh y reutilización de una misma conexión física sin fuga de tenant.
- `PostgreSqlSchemaValidationTest`: el upgrade ahora materializa V7 con usuario, roles custom, alumno, refresh y export Jere; luego verifica backfills, constraints, health y RLS hasta la última migración disponible.
- `UsuarioRepositorio`/`UsuarioDetailsService`/`AutenticacionService`: la identidad global transporta `authVersion` y se revalida contra el usuario tenant-bound antes de emitir credenciales; añadido caso concurrente.
- `Usuario.rol`: asociación legacy LAZY para impedir una consulta implícita a `roles` del tenant equivocado; authorities y auditoría ya proceden de membership.
- `ApplicationRoleAuthenticationPostgreSqlTest`: además de reutilización de conexión, cubre dos memberships, selección obligatoria, tenant inválido, filtro JWT, membership suspendida y rol inactivo.
- Frontend `axiosConfig`: conserva la cancelación individual y la de cambio de tenant con una señal combinada; añadido test de regresión.
- ADR-0008 y gobierno multitenancy: comandos reales, Java 21, V11, roles
  runtime/Flyway y demo V7 protegida. El gate técnico local es
  `EXECUTED_PASS`; la certificación operativa absoluta continúa `AMBER` por el
  backup/restore multitenant separado.
- `V8__tenant_control_plane.sql`: el backfill de `platform_admins` evalúa por separado el rol legacy y los roles suplementarios; la prueba V7 representa un SUPERADMIN legacy con `ADMINISTRADOR` suplementario y exige ambos roles de membership más la capacidad global.
- `V10`/`V11`: `SECURITY DEFINER` usa únicamente `pg_catalog`; la cobertura de FKs excluye índices parciales. La prueba del rol real verifica owner, `prosecdef` y `proconfig`.
- `V10` concede a `gestudio_app` sólo `SELECT, INSERT` sobre `usuario_roles`; la prueba del rol real ejecuta el bootstrap completo para validar ese camino, memberships, auditoría y grants sin owner.
- Bootstrap y reset local reutilizan el patrón existente `TenantContext` exterior + `TransactionTemplate` interior, garantizando que la conexión se adquiera después de seleccionar tenant; el test unitario observa el contexto al iniciar la transacción.
- El binding común de refresh compara también `authVersion` entre JWT y sesión persistida, además de usuario, tenant, membership y sus versiones.
- La reutilización de conexión del rol real ahora comprueba también filas de `alumnos` en dos tenants, no sólo `refresh_sessions`, para representar el plano de dominio.
- Los dos servicios de tarifas reutilizan `RbacService`/`TenantAccess` para los permisos administrativos e históricos; sus pruebas PostgreSQL crean y seleccionan la membership correspondiente a cada actor.
- La prueba con rol PostgreSQL real ahora cubre también contraseña incorrecta antes de tenant (incluida auditoría global bajo RLS) y rotación real del refresh ligada a la misma membership.
- `README.md` y `docs/development/local-development.md` documentan V1-V11, los
  roles de V8-V11, el gate PostgreSQL reproducible y la prohibición de aplicar
  esas migraciones a la demo estable V7; la corrida actual pasó y no se
  reescribieron documentos históricos de release.

## Pruebas

| Comando | Resultado real | Duración | Tests | Fallos/errores/skips |
|---|---|---:|---:|---|
| `.\mvnw.cmd -v` con Java 21 por proceso | PASS | 2 s | - | - |
| `.\mvnw.cmd '-Dtest=AutenticacionServiceTest' test` | FAIL reproducido | 32.655 s Maven | 5 | 0/5/0 |
| `.\mvnw.cmd '-Dtest=AutenticacionServiceTest' test` después del fix | PASS | 33.428 s Maven | 5 | 0/0/0 |
| `.\mvnw.cmd '-Dtest=ApplicationRoleAuthenticationPostgreSqlTest,AutenticacionServiceTest' test` | BLOCKED_EXTERNAL: Docker/Testcontainers no disponible; unitarios pasan | 38.760 s Maven | 6 intentados | 0/1/0 |
| `.\mvnw.cmd '-Dtest=AuditServiceTest' test` | PASS | 31.643 s Maven | 2 | 0/0/0 |
| `.\mvnw.cmd '-Dtest=LocalAdminPasswordResetRunnerTest,AuditServiceTest,AutenticacionServiceTest' test` | PASS | 39.549 s Maven | 10 | 0/0/0 |
| `.\mvnw.cmd '-DskipTests' test` después de ampliar pruebas PostgreSQL | FAIL testCompile: ambigüedad AssertJ en `SQLException` | 21.806 s Maven | 0 ejecutados | compilación |
| `.\mvnw.cmd '-DskipTests' test` después de tipar la aserción | PASS testCompile; tests omitidos explícitamente | 25.300 s Maven | 0 | 0/0/0 |
| `.\mvnw.cmd '-DskipTests' test` después del caso multitenant/LAZY | PASS testCompile; tests omitidos explícitamente | 31.157 s Maven | 0 | 0/0/0 |
| `.\mvnw.cmd '-Dtest=AutenticacionServiceTest,AuditServiceTest,LocalAdminPasswordResetRunnerTest,TokenServiceTest,TenantAwareDataSourceTest,TenantContextTest,MultitenancyConfigurationGuardTest' test` | PASS | 39.088 s Maven | 21 | 0/0/0 |
| `npm ci` | PASS; 401 paquetes desde lockfile | 27.2 s | - | warning local de scripts pendientes para esbuild |
| `npm test` | PASS | 31.8 s | 166 (9 Node + 157 Vitest) | 0/0/0 |
| `npm run lint` | PASS | 27.9 s | - | 0 errores |
| `npm run build` sin `VITE_API_BASE_URL` | FAIL esperado, configuración obligatoria ausente después de compilar bundle | 14.6 s | - | generador `_headers` |
| `npm run build` con `VITE_API_BASE_URL=https://example.invalid/api` por proceso | PASS | 11.5 s | 2388 módulos | 0 errores |
| `.\mvnw.cmd '-DskipTests' test` después de cerrar autorización de tarifas | PASS testCompile; tests omitidos explícitamente | 27.152 s Maven | 0 | 0/0/0 |
| `.\mvnw.cmd '-Dtest=AutenticacionServiceTest' test` final | PASS | 31.037 s Maven / 33.084 s pared | 6 | 0/0/0 |
| `.\mvnw.cmd '-Dtest=ApplicationRoleAuthenticationPostgreSqlTest,AutenticacionServiceTest' test` final | BLOCKED_EXTERNAL: Docker/Testcontainers no disponible; unitarios pasan | 35.615 s Maven / 37.656 s pared | 7 intentados | 0/1/0 |
| `.\mvnw.cmd '-Dtest=PostgreSqlSchemaValidationTest' test` final | BLOCKED_EXTERNAL antes de migrar: Docker/Testcontainers no disponible | 33.553 s Maven / 35.559 s pared | 1 intento de inicialización | 0/1/0 |
| `.\mvnw.cmd '-Dtest=*Test,!*PostgreSql*' test` diagnóstico final | PASS; no sustituye PostgreSQL ni `clean verify` | 1:04 min Maven / 66.854 s pared | 200 | 0/0/2 |
| `.\mvnw.cmd clean verify` final | FAIL ambiental en `test`; compilación completa, JaCoCo/package final no alcanzados | 1:06 min Maven / 68.551 s pared | 224 | 0/24/2 |
| `.\mvnw.cmd -DskipTests package` diagnóstico final | PASS; JAR ensamblado, tests omitidos explícitamente | 34.127 s Maven / 36.628 s pared | 0 | 0/0/0 |

Las ejecuciones listadas arriba son evidencia histórica de la intervención
anterior, no evidencia PostgreSQL de esta continuidad. El bloqueo quedó
superado por las ejecuciones actuales con Docker y Java 21 listadas debajo.

### Continuidad actual del 2026-08-04

| Comando | Resultado real | Duración | Tests | Fallos/errores/skips |
|---|---|---:|---:|---|
| `.\mvnw.cmd -v` con Java 21 por proceso | PASS | 1.3 s pared | - | - |
| `.\mvnw.cmd '-Dtest=AutenticacionServiceTest' test` | PASS | 43.355 s Maven / 46.2 s pared | 6 | 0/0/0 |
| `.\mvnw.cmd '-Dtest=ApplicationRoleAuthenticationPostgreSqlTest,PostgreSqlSchemaValidationTest,AutenticacionServiceTest' test` | PASS | 2:12 min Maven / 135.4 s pared | 13 | 0/0/0 |
| `.\mvnw.cmd clean verify` | PASS | 3:52 min Maven / 237.7 s pared | 282 | 0/0/2 |
| `npm ci` | PASS | 38.4 s pared | - | - |
| `npm test` | PASS | 25.3 s pared | 166 | 0/0/0 |
| `npm run lint` | PASS | 8.5 s pared | - | 0 errores |
| `npm run build` con `VITE_API_BASE_URL=https://example.invalid/api` por proceso | PASS | 21.4 s pared | 2388 módulos | 0 errores |

Testcontainers 1.21.4 conectó al Engine 29.3.1 y levantó PostgreSQL
15.18-alpine3.24 en puertos host aleatorios `59840` y `62906`; no usó los
puertos, volúmenes, networks ni contenedores de la demo.

## Migraciones

- V1-V11 limpio: PASS real; 11 migraciones aplicadas y validadas, versión final V11.
- V7-V11 incremental: PASS real con identidades, roles custom, alumno, refresh y export V7 representativos; cuatro migraciones aplicadas hasta V11.
- Hibernate validate: PASS contra el esquema limpio y durante el arranque con el usuario runtime.
- Usuario migrador: `migration_owner`, separado y propietario de los objetos.
- Usuario de aplicación: `gestudio_app_test`, `LOGIN`, miembro de `gestudio_app`, sin `SUPERUSER`, `CREATEDB`, `CREATEROLE`, `REPLICATION` ni `BYPASSRLS`, y sin ownership.
- RLS: PASS real para fail-closed sin tenant, tenants inicial/secundario,
  `refresh_sessions`, `alumnos`, `FORCE RLS`, políticas, grants, función health
  `SECURITY DEFINER` con `search_path=pg_catalog` y reutilización de conexión.
- Gate backend completo: PASS; JaCoCo analizó 339 clases y Maven creó y
  reempaquetó `target/backend-1.0.jar`.
- Frontend actual: PASS; `npm ci`, 9 contratos Node, 157 tests Vitest, lint y
  build. `package-lock.json` quedó sin diff y conservó SHA-256
  `C37EED9E41953E2B1E82D7A054F9F5D6D340AB22CCF1D6CDA9F3BA39E5C31113`.

## Pendientes

- Crear el commit y hacer push normal después de la última revisión del index.
- Verificar `HEAD == origin/main`, árbol limpio y recursos protegidos después
  del push.

## Preparación de commit

- Archivos que deben incluirse: solo implementación, migraciones, pruebas, documentación y scripts permanentes atribuibles a multitenancy, incluido este archivo.
- Archivos excluidos: `backend/target`, `frontend/dist` y `frontend/node_modules` ignorados; no existen evidencias, logs, dumps, ZIP, `.env` real, parches ni temporales candidatos al commit.
- Staging explícito: 128 paths enumerados; 0 unstaged y 0 untracked.
- Diff cached: 128 archivos, 7.774 inserciones y 615 eliminaciones; 0 deletes,
  0 renames y 0 cambios de modo inesperados.
- `git diff --cached --check`: PASS.
- Secret scan: PASS, 0 coincidencias de alta confianza. Catorce candidatos
  léxicos de contraseña clasificados como fixtures sintéticos, placeholders
  documentados o referencias obligatorias a variables de entorno.
- Dependencias: 0 manifests/lockfiles modificados; 0 archivos binarios o mayores a 1 MiB; V1-V7 intactas.
- Estado inicial clasificado: 82 tracked modificados y 46 untracked legítimos.
  Estado precommit: los 128 paths están staged; `HEAD == origin/main` después
  del fetch final.

## Commit y push

- Hash: se verifica después de crear el commit y se informa externamente; el
  SHA de un commit no puede auto-incrustarse dentro de su propio contenido.
- Mensaje previsto: `feat: complete tenant-aware authentication under PostgreSQL RLS`.
- Push: no ejecutado.
- Motivo actual: backend, PostgreSQL, frontend, limpieza, secret scan, diff,
  recursos protegidos e index pasan; commit y push aún no se ejecutaron.

## Riesgos o limitaciones finales

- El bloqueo Docker de la intervención anterior quedó superado. PostgreSQL
  real, V1-V11, V7-V11, RLS/grants y reutilización de conexión pasaron en los
  focalizados y dentro de `clean verify`.
- Históricamente `clean verify` terminó con 224 tests, 0 fallos, 24 errores de
  inicialización PostgreSQL y 2 skips; quedó superado por el gate actual PASS
  de 282 tests y no se usa como evidencia final.
- La prueba del rol real emite un aviso de API deprecada no bloqueante; fue
  evaluada funcionalmente con Testcontainers y pasó.
- La demo protegida está activa y sólo se inspeccionó en lectura: frontend 200,
  perfil anónimo 404 vacío, readiness 200 y dos contenedores healthy. No hay
  `cloudflared` visible.
- La certificación operativa absoluta definida por gobernanza continúa AMBER
  porque el backup/restore multitenant no formó parte de este cierre técnico.
- No se intentó iniciar Docker ni la demo porque el contrato operativo prohíbe hacerlo automáticamente y exige no mutar `gestudio-remote-demo`.
