# Gestudio — relevamiento técnico de continuidad

> Documento vivo y autorreferencial.
>
> Actualizador: `scripts/ops/Update-GestudioTechnicalSurvey.ps1`
>
> Este archivo registra estado observable, evidencia, bloqueos y próximos
> pasos. No demuestra por sí solo que Gestudio esté listo para release.

## Contrato de uso

1. La fuente de verdad son comandos realmente ejecutados sobre el SHA registrado.
2. Todo `PASS` queda invalidado si posteriormente cambia código, configuración,
   migraciones, pruebas o scripts relacionados.
3. Las zonas delimitadas por marcadores `AUTO` no deben editarse manualmente.
4. Las decisiones y notas fuera de esas zonas se preservan.
5. El actualizador no ejecuta tests, no inicia Docker, no modifica la demo, no
   hace staging, no crea commits y no hace push.
6. `RELEASE_READINESS=PASS` exige árbol limpio, `HEAD == origin/main`, confirmación
   explícita y evidencia de CI sobre el SHA publicado.

## Estado histórico recibido — pendiente de revalidación

- `RELEASE_READINESS` quedó en `PARTIAL`.
- El control-plane `PLATFORM`/`TENANT` está ampliamente implementado.
- MFA/TOTP, refresh rotation, step-up, idempotencia y auditoría fueron desarrollados.
- `B12` fresh y `V1→V12` tuvieron evidencia verde en etapas anteriores, invalidada
  por cambios posteriores.
- Docker Desktop quedó detenido o deshabilitado.
- PostgreSQL, Testcontainers, PIT y E2E real no quedaron cerrados sobre el árbol final.
- Playwright y Axe quedaron preparados estáticamente.
- Supply Chain quedó parcial: npm/SBOM tuvieron resultados favorables, pero OWASP
  Dependency-Check no produjo un análisis válido por fallos externos.
- La última ejecución registrada había detectado fallos frontend en páginas de plataforma.
- No hubo commit/push final de release.

## Orden obligatorio de continuidad

### P0 — Preservación y congelamiento

- [ ] Verificar repositorio, `main`, `origin/main`, HEAD, índice y worktree.
- [ ] Confirmar ausencia de merge, rebase, cherry-pick o revert incompleto.
- [ ] Confirmar que no haya ediciones concurrentes.
- [ ] Identificar procesos Maven, Vitest o Playwright huérfanos.
- [ ] Clasificar todos los archivos tracked, staged y untracked.
- [ ] Rechazar credenciales, `.env` reales, generados y temporales.
- [ ] Registrar cualquier divergencia respecto de `origin/main`.

### P1 — Resolver y validar el árbol sin Docker

- [ ] Reproducir los fallos frontend pendientes.
- [ ] Registrar prueba, archivo, mensaje y causa exacta.
- [ ] Corregir sólo defectos reales con cambios mínimos.
- [ ] Ejecutar suite frontend completa.
- [ ] Ejecutar coverage release y coverage del diff.
- [ ] Ejecutar ESLint, duplicación productiva, TypeScript y build.
- [ ] Ejecutar compilación backend limpia y suites no-Docker.
- [ ] Ejecutar PMD, CPD y verificadores fail-closed.

### P2 — Recuperación segura de Docker

- [ ] Habilitar Docker manualmente; ningún script de continuidad debe iniciarlo.
- [ ] Tomar snapshot read-only de `gestudio-remote-demo`.
- [ ] Registrar IDs, nombres, imágenes, estados y puertos.
- [ ] No reutilizar puertos, redes, volúmenes, secretos ni base de la demo.
- [ ] Usar proyectos Compose únicos, puertos efímeros y secretos sintéticos.
- [ ] Verificar invariancia de la demo después de cada cleanup.

### P3 — PostgreSQL, Flyway, RLS y control-plane

- [ ] Validar `B12` en base vacía y confirmar cero datos funcionales.
- [ ] Validar upgrade histórico `V1→V12` y preservación de datos.
- [ ] Validar equivalencia estructural fresh frente a upgrade.
- [ ] Ejecutar Hibernate validate y roles PostgreSQL reales.
- [ ] Ejecutar seguridad `PLATFORM`/`TENANT`, MFA, refresh, reuse y step-up.
- [ ] Ejecutar provisioning, lifecycle, RLS entre dos tenants y auditoría.

### P4 — Quality Fortress backend

- [ ] Ejecutar `clean verify` con Java 21.
- [ ] Ejecutar PostgreSQL/Testcontainers y generar JaCoCo desde cero.
- [ ] Verificar cobertura global, crítica y diferencial.
- [ ] Ejecutar PIT sobre las clases críticas reales.
- [ ] Ejecutar Gherkin/integración definida por el repositorio.
- [ ] Revisar artefactos y reportes, no sólo exit codes.

### P5 — E2E, accesibilidad y operación

- [ ] Ejecutar Playwright Chromium contra un entorno fresh real.
- [ ] Ejecutar Axe y recorridos de teclado/foco.
- [ ] Probar bootstrap, activación, login `PLATFORM`, TOTP, recovery y step-up.
- [ ] Crear dos tenants sintéticos y probar aislamiento adversarial.
- [ ] Probar suspensión/reactivación y preservación de datos.
- [ ] Ejecutar smoke, reset efímero y rollback fail-closed.
- [ ] Verificar que traces, screenshots y logs no contengan secretos.

### P6 — Supply Chain y seguridad

- [ ] Ejecutar npm audit completo y sólo producción.
- [ ] Regenerar y validar SBOM frontend/backend.
- [ ] Reejecutar OWASP Dependency-Check con NVD utilizable.
- [ ] Ejecutar secret scan, CodeQL y revisión de GitHub Actions.
- [ ] No clasificar un fallo de infraestructura como `PASS`.

### P7 — Cierre Git y publicación

- [ ] Congelar definitivamente el árbol.
- [ ] Reejecutar todos los gates invalidados sobre el mismo SHA.
- [ ] Ejecutar `git diff --check` sobre worktree e índice.
- [ ] Revisar diff, status, temporales y credenciales.
- [ ] Stagear explícitamente sólo archivos relacionados.
- [ ] Revisar el diff staged completo.
- [ ] Crear un único commit coherente en `main`.
- [ ] Hacer push directo a `origin/main`.
- [ ] Verificar GitHub Actions sobre el SHA publicado.
- [ ] Actualizar este documento con hash, mensaje y resultados.
- [ ] Cambiar `RELEASE_READINESS` a `PASS` sólo al final.

## Uso del actualizador

Snapshot sin evento:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\ops\Update-GestudioTechnicalSurvey.ps1 `
    -Fetch
```

Registrar un resultado:

```powershell
pwsh -NoLogo -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\ops\Update-GestudioTechnicalSurvey.ps1 `
    -Event 'Frontend suite completa' `
    -EventStatus FAIL `
    -CommandText 'npm test -- --run' `
    -Result 'Dos pruebas fallaron' `
    -NextAction 'Reproducirlas aisladamente y corregir la causa'
```

## Estado vivo automático

<!-- AUTO:CURRENT:START -->
| Campo | Valor |
|---|---|
| Fecha | 2026-08-20T15:01:56.679-03:00 |
| Repositorio | C:\laburo\Gestudio |
| Origin | https://github.com/JerePrograma/Gestudio.git |
| Rama | main |
| HEAD | 53547baac50063de85fb694124241d9f58e256a1 |
| origin/main | 53547baac50063de85fb694124241d9f58e256a1 |
| Divergencia | ahead=0; behind=0 |
| RELEASE_READINESS | **PARTIAL** |
| Unstaged | 114 |
| Staged | 0 |
| Untracked | 157 |
| diff --check | PASS |
| Docker | AVAILABLE server=29.7.2 |
| Docker service | State=Stopped; StartMode=Manual |
| Evidencia CI |  |
| Próxima acción | Congelar ediciones y renovar los gates invalidados. |

### Advertencias

- El árbol contiene cambios.

### git status --short

~~~text
 M .env.example
 M .env.local.example
 M .env.remote-demo.example
 M .github/workflows/application-rollback-verification.yml
 M .github/workflows/ci.yml
 M .gitignore
 M README.md
 M TESTING.md
 M backend/Dockerfile
 M backend/pom.xml
 M backend/src/main/java/gestudio/entidades/Usuario.java
 M backend/src/main/java/gestudio/infra/configuracion/ConfiguracionCors.java
 M backend/src/main/java/gestudio/infra/configuracion/MultitenancyConfigurationGuard.java
 M backend/src/main/java/gestudio/infra/errores/TratadorDeErrores.java
 M backend/src/main/java/gestudio/infra/observabilidad/RequestCorrelationFilter.java
 M backend/src/main/java/gestudio/infra/seguridad/SecurityConfigurations.java
 M backend/src/main/java/gestudio/infra/seguridad/SecurityFilter.java
 M backend/src/main/java/gestudio/infra/seguridad/SuperadminBootstrapProperties.java
 M backend/src/main/java/gestudio/infra/seguridad/SuperadminBootstrapRunner.java
 M backend/src/main/java/gestudio/infra/seguridad/SuperadminBootstrapService.java
 M backend/src/main/java/gestudio/tenancy/TenantDataSourceConfiguration.java
 D backend/src/main/java/gestudio/tenancy/TenantPlatformController.java
 M backend/src/main/resources/application-dev.yml
 M backend/src/main/resources/application-prod.yml
 M backend/src/main/resources/application-remote-demo.yml
 M backend/src/main/resources/application-test.yml
 M backend/src/main/resources/application.yml
 M backend/src/test/java/gestudio/infra/configuracion/MultitenancyConfigurationGuardTest.java
 M backend/src/test/java/gestudio/infra/observabilidad/ObservabilityPostgreSqlTest.java
 M backend/src/test/java/gestudio/infra/observabilidad/RequestCorrelationFilterTest.java
 M backend/src/test/java/gestudio/infra/persistencia/CanonicalArchitectureContractTest.java
 M backend/src/test/java/gestudio/infra/persistencia/PostgreSqlIntegrationTest.java
 M backend/src/test/java/gestudio/infra/persistencia/PostgreSqlSchemaValidationTest.java
 M backend/src/test/java/gestudio/infra/seguridad/ApplicationRoleAuthenticationPostgreSqlTest.java
 M backend/src/test/java/gestudio/infra/seguridad/SecurityHttpIntegrationTest.java
 M backend/src/test/java/gestudio/infra/seguridad/SuperadminBootstrapPostgreSqlTest.java
 M backend/src/test/java/gestudio/infra/seguridad/SuperadminBootstrapRunnerTest.java
 M docker-compose.prod.yml
 M docker-compose.remote-demo.yml
 M docker-compose.yml
 M docs/CODEX_AUTORREFERENCIA_GESTUDIO.md
 M docs/ai-reference/03-architecture.md
 M docs/ai-reference/07-frontend-reference.md
 M docs/ai-reference/08-api-reference.md
 M docs/ai-reference/09-data-and-persistence.md
 M docs/ai-reference/10-security.md
 M docs/ai-reference/13-testing-strategy.md
 M docs/ai-reference/14-build-deployment-operations.md
 M docs/ai-reference/18-known-risks-and-technical-debt.md
 M docs/ai-reference/22-source-index.md
 M docs/ai-reference/23-ai-working-context.md
 M docs/ai-reference/25-rbac-and-route-matrix.md
 M docs/ai-reference/27-remote-state-and-release-evidence.md
 M docs/architecture/multitenancy-governance-and-health.md
 M docs/deployment-windows.md
 M docs/development/environment-variables.md
 M docs/development/local-development.md
 M docs/operations/backup-restore.md
 M docs/operations/local-runbook.md
 M docs/operations/observability.md
 M docs/operations/rollback.md
 M docs/project-status-and-handoff.md
 M frontend/.dockerignore
 M frontend/eslint.config.js
 M frontend/nginx/default.conf
 M frontend/nginx/security-headers.check.mjs
 M frontend/package-lock.json
 M frontend/package.json
 M frontend/public/_headers
 M frontend/src/api/authSession.ts
 M frontend/src/api/axiosConfig.test.ts
 M frontend/src/api/axiosConfig.ts
 M frontend/src/componentes/Header.tsx
 M frontend/src/componentes/Sidebar.tsx
 M frontend/src/componentes/layout/MainLayout.tsx
 M frontend/src/funcionalidades/bonificaciones/BonificacionesFormulario.tsx
 M frontend/src/funcionalidades/conceptos/ConceptosFormulario.tsx
 M frontend/src/funcionalidades/metodos-pago/MetodosPagoFormulario.tsx
 M frontend/src/funcionalidades/pagos/PagosFormulario.test.tsx
 M frontend/src/funcionalidades/pagos/PagosPagina.test.tsx
 M frontend/src/funcionalidades/profesores/ProfesoresFormulario.tsx
 M frontend/src/funcionalidades/recargos/RecargosFormulario.tsx
 M frontend/src/funcionalidades/salones/SalonesFormulario.tsx
 M frontend/src/funcionalidades/subconceptos/SubConceptosFormulario.tsx
 M frontend/src/hooks/context/auth-context.test.ts
 M frontend/src/hooks/context/auth-context.ts
 M frontend/src/hooks/context/authContext.test.tsx
 M frontend/src/hooks/context/authContext.tsx
 M frontend/src/rutas/AppRouter.tsx
 M frontend/src/rutas/ProtectedRoute.test.tsx
 M frontend/src/rutas/ProtectedRoute.tsx
 M frontend/src/rutas/routes.ts
 M frontend/tsconfig.json
 M frontend/tsconfig.node.json
 M frontend/vite.config.ts
 M scripts/db/10-create-application-role.sh
 M scripts/demo-local.ps1
 M scripts/deploy/deploy.env.example
 M scripts/deploy/deploy.ps1
 M scripts/deploy/test-idempotency.ps1
 M scripts/deploy/verify-deployment.ps1
 M scripts/gestudio_demo_seed_full.sql
 M scripts/ops/backup-postgres.ps1
 M scripts/ops/restore-postgres.ps1
 M scripts/ops/rollback-backend.ps1
 M scripts/ops/verify-application-rollback.ps1
 M scripts/ops/verify-backup-restore.ps1
 M scripts/ops/verify-email-delivery.ps1
 M scripts/ops/verify-observability.ps1
 M scripts/remote-demo/database.ps1
 M scripts/remote-demo/environment.ps1
 M scripts/smoke-local.ps1
 M scripts/validate-demo-seed.ps1
?? .github/workflows/e2e.yml
?? .github/workflows/quality-fortress.yml
?? .github/workflows/security-supply-chain.yml
?? GESTUDIO_FINALIZACION_SUPERADMIN_MEGAPROMPT.md
?? GESTUDIO_RELEVAMIENTO_TECNICO_CONTINUIDAD.md
?? backend/src/main/java/gestudio/platform/PlatformMetrics.java
?? backend/src/main/java/gestudio/platform/control/MembershipMutationCoordinator.java
?? backend/src/main/java/gestudio/platform/control/PlatformAdminMutationCoordinator.java
?? backend/src/main/java/gestudio/platform/control/PlatformAuditService.java
?? backend/src/main/java/gestudio/platform/control/PlatformControlPlaneCommandSupport.java
?? backend/src/main/java/gestudio/platform/control/PlatformControlPlaneController.java
?? backend/src/main/java/gestudio/platform/control/PlatformControlPlaneQueries.java
?? backend/src/main/java/gestudio/platform/control/PlatformControlPlaneRepository.java
?? backend/src/main/java/gestudio/platform/control/PlatformControlPlaneService.java
?? backend/src/main/java/gestudio/platform/control/PlatformIdempotencyRepository.java
?? backend/src/main/java/gestudio/platform/control/PlatformIdentityActivationController.java
?? backend/src/main/java/gestudio/platform/control/PlatformIdentityActivationService.java
?? backend/src/main/java/gestudio/platform/control/PlatformMutationExecutor.java
?? backend/src/main/java/gestudio/platform/control/PlatformRequestHash.java
?? backend/src/main/java/gestudio/platform/control/TenantMutationCoordinator.java
?? backend/src/main/java/gestudio/platform/security/Base32.java
?? backend/src/main/java/gestudio/platform/security/PlatformAuthController.java
?? backend/src/main/java/gestudio/platform/security/PlatformAuthenticationService.java
?? backend/src/main/java/gestudio/platform/security/PlatformIdentityRepository.java
?? backend/src/main/java/gestudio/platform/security/PlatformMfaCrypto.java
?? backend/src/main/java/gestudio/platform/security/PlatformMfaRateLimitedException.java
?? backend/src/main/java/gestudio/platform/security/PlatformMfaService.java
?? backend/src/main/java/gestudio/platform/security/PlatformPreconditionRequiredException.java
?? backend/src/main/java/gestudio/platform/security/PlatformPrincipal.java
?? backend/src/main/java/gestudio/platform/security/PlatformRefreshSessionRepository.java
?? backend/src/main/java/gestudio/platform/security/PlatformRefreshSessionService.java
?? backend/src/main/java/gestudio/platform/security/PlatformSecurityFilter.java
?? backend/src/main/java/gestudio/platform/security/PlatformSecurityProperties.java
?? backend/src/main/java/gestudio/platform/security/PlatformStepUpController.java
?? backend/src/main/java/gestudio/platform/security/PlatformStepUpRepository.java
?? backend/src/main/java/gestudio/platform/security/PlatformStepUpService.java
?? backend/src/main/java/gestudio/platform/security/PlatformTokenService.java
?? backend/src/main/java/gestudio/platform/security/PlatformVerifiedToken.java
?? backend/src/main/java/gestudio/platform/security/TotpService.java
?? backend/src/main/java/gestudio/tenancy/PlatformDataSourceConfiguration.java
?? backend/src/main/resources/db/migration/B12__gestudio_production_baseline.sql
?? backend/src/main/resources/db/migration/V12__platform_identity_and_seedless_health.sql
?? backend/src/test/java/gestudio/infra/seguridad/SuperadminBootstrapMetricsTest.java
?? backend/src/test/java/gestudio/platform/PlatformMetricsTest.java
?? backend/src/test/java/gestudio/platform/control/PlatformControlPlanePostgreSqlTest.java
?? backend/src/test/java/gestudio/platform/security/PlatformAuthenticationServiceTest.java
?? backend/src/test/java/gestudio/platform/security/PlatformCryptographyTest.java
?? backend/src/test/java/gestudio/platform/security/PlatformIdentityActivationAtomicityPostgreSqlTest.java
?? backend/src/test/java/gestudio/platform/security/PlatformIdentityActivationPostgreSqlTest.java
?? backend/src/test/java/gestudio/platform/security/PlatformMfaServiceTest.java
?? backend/src/test/java/gestudio/platform/security/PlatformRefreshSessionServiceTest.java
?? backend/src/test/java/gestudio/platform/security/PlatformSecurityHttpTest.java
?? backend/src/test/java/gestudio/platform/security/PlatformSecurityTestSupport.java
?? backend/src/test/java/gestudio/platform/security/PlatformSessionStepUpPostgreSqlTest.java
?? backend/src/test/java/gestudio/platform/security/PlatformStepUpServiceTest.java
?? backend/src/test/java/gestudio/quality/bdd/ControlPlaneSteps.java
?? backend/src/test/java/gestudio/quality/bdd/CucumberSpringConfiguration.java
?? backend/src/test/java/gestudio/quality/bdd/QualityFortressBddTest.java
?? backend/src/test/resources/features/control_plane.feature
?? docs/architecture/adr-0009-platform-control-plane.md
?? docs/architecture/threat-model-platform-control-plane.md
?? docs/operations/platform-control-plane-runbook.md
?? frontend/e2e/control-plane.spec.ts
?? frontend/e2e/support/e2e-state.ts
?? frontend/e2e/support/totp.ts
?? frontend/e2e/tsconfig.json
?? frontend/playwright.config.ts
?? frontend/scripts/verify-coverage-source-inventory.mjs
?? frontend/src/api/academicApis.test.ts
?? frontend/src/api/catalogAndSecurityApis.test.ts
?? frontend/src/api/financialApis.test.ts
?? frontend/src/componentes/Header.test.tsx
?? frontend/src/componentes/NavGroup.test.tsx
?? frontend/src/componentes/layout/MainLayout.test.tsx
?? frontend/src/funcionalidades/alumnos/AlumnosFormulario.test.tsx
?? frontend/src/funcionalidades/asistencias-diarias/AsistenciaDiariaFormulario.test.tsx
?? frontend/src/funcionalidades/asistencias-mensuales/AsistenciaMensualDetalle.test.tsx
?? frontend/src/funcionalidades/bonificaciones/BonificacionesFormulario.test.tsx
?? frontend/src/funcionalidades/bonificaciones/BonificacionesPagina.test.tsx
?? frontend/src/funcionalidades/caja/CajaPagina.test.tsx
?? frontend/src/funcionalidades/caja/EgresosPagina.test.tsx
?? frontend/src/funcionalidades/conceptos/ConceptosFormulario.test.tsx
?? frontend/src/funcionalidades/conceptos/ConceptosPagina.test.tsx
?? frontend/src/funcionalidades/disciplinas/DisciplinasFormulario.test.tsx
?? frontend/src/funcionalidades/disciplinas/DisciplinasPagina.test.tsx
?? frontend/src/funcionalidades/disciplinas/HorariosFieldArray.test.tsx
?? frontend/src/funcionalidades/disciplinas/TarifasDisciplinaPagina.ui.test.tsx
?? frontend/src/funcionalidades/inscripciones/InscripcionesFormulario.test.tsx
?? frontend/src/funcionalidades/inscripciones/InscripcionesPagina.test.tsx
?? frontend/src/funcionalidades/mensualidades/MensualidadPagina.test.tsx
?? frontend/src/funcionalidades/metodos-pago/MetodosPagoFormulario.test.tsx
?? frontend/src/funcionalidades/metodos-pago/MetodosPagoPagina.test.tsx
?? frontend/src/funcionalidades/profesores/ProfesoresFormulario.test.tsx
?? frontend/src/funcionalidades/profesores/ProfesoresPagina.test.tsx
?? frontend/src/funcionalidades/recargos/RecargosFormulario.test.tsx
?? frontend/src/funcionalidades/recargos/RecargosPagina.test.tsx
?? frontend/src/funcionalidades/reportes/AlumnosPorDIsciplina.test.tsx
?? frontend/src/funcionalidades/salones/SalonesFormulario.test.tsx
?? frontend/src/funcionalidades/salones/SalonesPagina.test.tsx
?? frontend/src/funcionalidades/stock/StocksFormulario.test.tsx
?? frontend/src/funcionalidades/stock/StocksPagina.test.tsx
?? frontend/src/funcionalidades/subconceptos/SubConceptosFormulario.test.tsx
?? frontend/src/funcionalidades/subconceptos/SubConceptosPagina.test.tsx
?? frontend/src/hooks/context/SideBarContext.test.tsx
?? frontend/src/main.test.tsx
?? frontend/src/paginas/Dashboard.test.tsx
?? frontend/src/paginas/Navigation.test.tsx
?? frontend/src/paginas/Reportes.test.tsx
?? frontend/src/paginas/Unauthorized.test.tsx
?? frontend/src/platform/ConfirmDialog.test.tsx
?? frontend/src/platform/ConfirmDialog.tsx
?? frontend/src/platform/OneTimeActivationNotice.test.tsx
?? frontend/src/platform/OneTimeActivationNotice.tsx
?? frontend/src/platform/PlatformLayout.test.tsx
?? frontend/src/platform/PlatformLayout.tsx
?? frontend/src/platform/StepUpProvider.test.tsx
?? frontend/src/platform/StepUpProvider.tsx
?? frontend/src/platform/activationLink.ts
?? frontend/src/platform/pages/PlatformActivatePage.test.tsx
?? frontend/src/platform/pages/PlatformActivatePage.tsx
?? frontend/src/platform/pages/PlatformAdminsPage.test.tsx
?? frontend/src/platform/pages/PlatformAdminsPage.tsx
?? frontend/src/platform/pages/PlatformAuditPage.test.tsx
?? frontend/src/platform/pages/PlatformAuditPage.tsx
?? frontend/src/platform/pages/PlatformLogin.test.tsx
?? frontend/src/platform/pages/PlatformLogin.tsx
?? frontend/src/platform/pages/TenantDetailPage.test.tsx
?? frontend/src/platform/pages/TenantDetailPage.tsx
?? frontend/src/platform/pages/TenantFormPage.test.tsx
?? frontend/src/platform/pages/TenantFormPage.tsx
?? frontend/src/platform/pages/TenantsPage.test.tsx
?? frontend/src/platform/pages/TenantsPage.tsx
?? frontend/src/platform/platformApi.test.ts
?? frontend/src/platform/platformApi.ts
?? frontend/src/platform/platformTypes.ts
?? frontend/src/platform/stepUpContext.ts
?? frontend/src/rutas/AppRouter.test.tsx
?? frontend/src/test/coverageInventory.test.ts
?? frontend/src/test/renderPlatformPage.tsx
?? frontend/vite.diff-coverage.config.ts
?? scripts/codex/pmd-baseline.json
?? scripts/codex/pmd-quality-ruleset.xml
?? scripts/codex/quality-fortress.ps1
?? scripts/codex/run-frontend-diff-coverage.ps1
?? scripts/codex/verify-actions-policy.ps1
?? scripts/codex/verify-backend-diff-coverage.ps1
?? scripts/codex/verify-backend-static-analysis.ps1
?? scripts/codex/verify-quality-artifacts.ps1
?? scripts/e2e/run-control-plane.ps1
?? scripts/e2e/test-run-control-plane-contract.ps1
?? scripts/ops/Update-GestudioTechnicalSurvey.ps1
?? scripts/ops/bootstrap-platform-admin.ps1
?? scripts/ops/reset-ephemeral-database.ps1
?? scripts/ops/test-bootstrap-platform-admin-contract.ps1
?? scripts/ops/test-local-docker-guards-contract.ps1
?? scripts/ops/test-reset-ephemeral-database-contract.ps1
?? scripts/ops/test-rollback-backend-contract.ps1
~~~

### Cambios tracked sin stage

~~~text
warning: in the working copy of 'backend/src/test/java/gestudio/infra/persistencia/PostgreSqlIntegrationTest.java', CRLF will be replaced by LF the next time Git touches it
M	.env.example
M	.env.local.example
M	.env.remote-demo.example
M	.github/workflows/application-rollback-verification.yml
M	.github/workflows/ci.yml
M	.gitignore
M	README.md
M	TESTING.md
M	backend/Dockerfile
M	backend/pom.xml
M	backend/src/main/java/gestudio/entidades/Usuario.java
M	backend/src/main/java/gestudio/infra/configuracion/ConfiguracionCors.java
M	backend/src/main/java/gestudio/infra/configuracion/MultitenancyConfigurationGuard.java
M	backend/src/main/java/gestudio/infra/errores/TratadorDeErrores.java
M	backend/src/main/java/gestudio/infra/observabilidad/RequestCorrelationFilter.java
M	backend/src/main/java/gestudio/infra/seguridad/SecurityConfigurations.java
M	backend/src/main/java/gestudio/infra/seguridad/SecurityFilter.java
M	backend/src/main/java/gestudio/infra/seguridad/SuperadminBootstrapProperties.java
M	backend/src/main/java/gestudio/infra/seguridad/SuperadminBootstrapRunner.java
M	backend/src/main/java/gestudio/infra/seguridad/SuperadminBootstrapService.java
M	backend/src/main/java/gestudio/tenancy/TenantDataSourceConfiguration.java
D	backend/src/main/java/gestudio/tenancy/TenantPlatformController.java
M	backend/src/main/resources/application-dev.yml
M	backend/src/main/resources/application-prod.yml
M	backend/src/main/resources/application-remote-demo.yml
M	backend/src/main/resources/application-test.yml
M	backend/src/main/resources/application.yml
M	backend/src/test/java/gestudio/infra/configuracion/MultitenancyConfigurationGuardTest.java
M	backend/src/test/java/gestudio/infra/observabilidad/ObservabilityPostgreSqlTest.java
M	backend/src/test/java/gestudio/infra/observabilidad/RequestCorrelationFilterTest.java
M	backend/src/test/java/gestudio/infra/persistencia/CanonicalArchitectureContractTest.java
M	backend/src/test/java/gestudio/infra/persistencia/PostgreSqlIntegrationTest.java
M	backend/src/test/java/gestudio/infra/persistencia/PostgreSqlSchemaValidationTest.java
M	backend/src/test/java/gestudio/infra/seguridad/ApplicationRoleAuthenticationPostgreSqlTest.java
M	backend/src/test/java/gestudio/infra/seguridad/SecurityHttpIntegrationTest.java
M	backend/src/test/java/gestudio/infra/seguridad/SuperadminBootstrapPostgreSqlTest.java
M	backend/src/test/java/gestudio/infra/seguridad/SuperadminBootstrapRunnerTest.java
M	docker-compose.prod.yml
M	docker-compose.remote-demo.yml
M	docker-compose.yml
M	docs/CODEX_AUTORREFERENCIA_GESTUDIO.md
M	docs/ai-reference/03-architecture.md
M	docs/ai-reference/07-frontend-reference.md
M	docs/ai-reference/08-api-reference.md
M	docs/ai-reference/09-data-and-persistence.md
M	docs/ai-reference/10-security.md
M	docs/ai-reference/13-testing-strategy.md
M	docs/ai-reference/14-build-deployment-operations.md
M	docs/ai-reference/18-known-risks-and-technical-debt.md
M	docs/ai-reference/22-source-index.md
M	docs/ai-reference/23-ai-working-context.md
M	docs/ai-reference/25-rbac-and-route-matrix.md
M	docs/ai-reference/27-remote-state-and-release-evidence.md
M	docs/architecture/multitenancy-governance-and-health.md
M	docs/deployment-windows.md
M	docs/development/environment-variables.md
M	docs/development/local-development.md
M	docs/operations/backup-restore.md
M	docs/operations/local-runbook.md
M	docs/operations/observability.md
M	docs/operations/rollback.md
M	docs/project-status-and-handoff.md
M	frontend/.dockerignore
M	frontend/eslint.config.js
M	frontend/nginx/default.conf
M	frontend/nginx/security-headers.check.mjs
M	frontend/package-lock.json
M	frontend/package.json
M	frontend/public/_headers
M	frontend/src/api/authSession.ts
M	frontend/src/api/axiosConfig.test.ts
M	frontend/src/api/axiosConfig.ts
M	frontend/src/componentes/Header.tsx
M	frontend/src/componentes/Sidebar.tsx
M	frontend/src/componentes/layout/MainLayout.tsx
M	frontend/src/funcionalidades/bonificaciones/BonificacionesFormulario.tsx
M	frontend/src/funcionalidades/conceptos/ConceptosFormulario.tsx
M	frontend/src/funcionalidades/metodos-pago/MetodosPagoFormulario.tsx
M	frontend/src/funcionalidades/pagos/PagosFormulario.test.tsx
M	frontend/src/funcionalidades/pagos/PagosPagina.test.tsx
M	frontend/src/funcionalidades/profesores/ProfesoresFormulario.tsx
M	frontend/src/funcionalidades/recargos/RecargosFormulario.tsx
M	frontend/src/funcionalidades/salones/SalonesFormulario.tsx
M	frontend/src/funcionalidades/subconceptos/SubConceptosFormulario.tsx
M	frontend/src/hooks/context/auth-context.test.ts
M	frontend/src/hooks/context/auth-context.ts
M	frontend/src/hooks/context/authContext.test.tsx
M	frontend/src/hooks/context/authContext.tsx
M	frontend/src/rutas/AppRouter.tsx
M	frontend/src/rutas/ProtectedRoute.test.tsx
M	frontend/src/rutas/ProtectedRoute.tsx
M	frontend/src/rutas/routes.ts
M	frontend/tsconfig.json
M	frontend/tsconfig.node.json
M	frontend/vite.config.ts
M	scripts/db/10-create-application-role.sh
M	scripts/demo-local.ps1
M	scripts/deploy/deploy.env.example
M	scripts/deploy/deploy.ps1
M	scripts/deploy/test-idempotency.ps1
M	scripts/deploy/verify-deployment.ps1
M	scripts/gestudio_demo_seed_full.sql
M	scripts/ops/backup-postgres.ps1
M	scripts/ops/restore-postgres.ps1
M	scripts/ops/rollback-backend.ps1
M	scripts/ops/verify-application-rollback.ps1
M	scripts/ops/verify-backup-restore.ps1
M	scripts/ops/verify-email-delivery.ps1
M	scripts/ops/verify-observability.ps1
M	scripts/remote-demo/database.ps1
M	scripts/remote-demo/environment.ps1
M	scripts/smoke-local.ps1
M	scripts/validate-demo-seed.ps1
~~~

### Resumen del diff

~~~text
warning: in the working copy of 'backend/src/test/java/gestudio/infra/persistencia/PostgreSqlIntegrationTest.java', CRLF will be replaced by LF the next time Git touches it
 .env.example                                       |   20 +
 .env.local.example                                 |   18 +
 .env.remote-demo.example                           |   14 +
 .../application-rollback-verification.yml          |   10 +
 .github/workflows/ci.yml                           |   36 +-
 .gitignore                                         |    5 +
 README.md                                          |   31 +-
 TESTING.md                                         |   58 +
 backend/Dockerfile                                 |   33 +-
 backend/pom.xml                                    |  249 ++
 .../src/main/java/gestudio/entidades/Usuario.java  |    4 +-
 .../infra/configuracion/ConfiguracionCors.java     |    3 +-
 .../MultitenancyConfigurationGuard.java            |   14 +-
 .../gestudio/infra/errores/TratadorDeErrores.java  |    8 +
 .../observabilidad/RequestCorrelationFilter.java   |   19 +-
 .../infra/seguridad/SecurityConfigurations.java    |   11 +-
 .../gestudio/infra/seguridad/SecurityFilter.java   |   43 +-
 .../seguridad/SuperadminBootstrapProperties.java   |    5 +-
 .../infra/seguridad/SuperadminBootstrapRunner.java |   33 +-
 .../seguridad/SuperadminBootstrapService.java      |  203 +-
 .../tenancy/TenantDataSourceConfiguration.java     |   12 +-
 .../gestudio/tenancy/TenantPlatformController.java |  126 -
 backend/src/main/resources/application-dev.yml     |    7 +
 backend/src/main/resources/application-prod.yml    |    8 +
 .../src/main/resources/application-remote-demo.yml |    7 +
 backend/src/main/resources/application-test.yml    |    1 +
 backend/src/main/resources/application.yml         |   20 +
 .../MultitenancyConfigurationGuardTest.java        |   45 +-
 .../ObservabilityPostgreSqlTest.java               |   11 +-
 .../RequestCorrelationFilterTest.java              |   64 +-
 .../CanonicalArchitectureContractTest.java         |   71 +-
 .../persistencia/PostgreSqlIntegrationTest.java    |    6 +
 .../PostgreSqlSchemaValidationTest.java            |  373 ++-
 ...pplicationRoleAuthenticationPostgreSqlTest.java |   10 +-
 .../seguridad/SecurityHttpIntegrationTest.java     |   38 +-
 .../SuperadminBootstrapPostgreSqlTest.java         |  239 +-
 .../seguridad/SuperadminBootstrapRunnerTest.java   |   75 +-
 docker-compose.prod.yml                            |   16 +
 docker-compose.remote-demo.yml                     |   16 +
 docker-compose.yml                                 |   20 +-
 docs/CODEX_AUTORREFERENCIA_GESTUDIO.md             |    7 +
 docs/ai-reference/03-architecture.md               |    7 +-
 docs/ai-reference/07-frontend-reference.md         |    8 +-
 docs/ai-reference/08-api-reference.md              |   15 +-
 docs/ai-reference/09-data-and-persistence.md       |    8 +-
 docs/ai-reference/10-security.md                   |   13 +-
 docs/ai-reference/13-testing-strategy.md           |   34 +-
 .../ai-reference/14-build-deployment-operations.md |    9 +-
 .../18-known-risks-and-technical-debt.md           |    5 +-
 docs/ai-reference/22-source-index.md               |    5 +-
 docs/ai-reference/23-ai-working-context.md         |    9 +-
 docs/ai-reference/25-rbac-and-route-matrix.md      |    8 +-
 .../27-remote-state-and-release-evidence.md        |    5 +
 .../multitenancy-governance-and-health.md          |   99 +-
 docs/deployment-windows.md                         |   95 +-
 docs/development/environment-variables.md          |   38 +-
 docs/development/local-development.md              |  120 +-
 docs/operations/backup-restore.md                  |   26 +-
 docs/operations/local-runbook.md                   |   74 +-
 docs/operations/observability.md                   |   76 +-
 docs/operations/rollback.md                        |  164 +-
 docs/project-status-and-handoff.md                 |    5 +
 frontend/.dockerignore                             |    8 +
 frontend/eslint.config.js                          |    8 +-
 frontend/nginx/default.conf                        |    7 +-
 frontend/nginx/security-headers.check.mjs          |   46 +-
 frontend/package-lock.json                         | 2973 ++++++++++++++++++--
 frontend/package.json                              |   15 +-
 frontend/public/_headers                           |    6 +
 frontend/src/api/authSession.ts                    |  168 +-
 frontend/src/api/axiosConfig.test.ts               |  151 +
 frontend/src/api/axiosConfig.ts                    |   48 +-
 frontend/src/componentes/Header.tsx                |   21 +-
 frontend/src/componentes/Sidebar.tsx               |   71 +-
 frontend/src/componentes/layout/MainLayout.tsx     |   32 +-
 .../bonificaciones/BonificacionesFormulario.tsx    |   14 +-
 .../conceptos/ConceptosFormulario.tsx              |   11 +-
 .../metodos-pago/MetodosPagoFormulario.tsx         |    9 +-
 .../funcionalidades/pagos/PagosFormulario.test.tsx |  125 +-
 .../src/funcionalidades/pagos/PagosPagina.test.tsx |  142 +-
 .../profesores/ProfesoresFormulario.tsx            |    8 +-
 .../recargos/RecargosFormulario.tsx                |   15 +-
 .../funcionalidades/salones/SalonesFormulario.tsx  |    3 +-
 .../subconceptos/SubConceptosFormulario.tsx        |    2 +-
 frontend/src/hooks/context/auth-context.test.ts    |   42 +-
 frontend/src/hooks/context/auth-context.ts         |   67 +
 frontend/src/hooks/context/authContext.test.tsx    |  261 +-
 frontend/src/hooks/context/authContext.tsx         |   77 +-
 frontend/src/rutas/AppRouter.tsx                   |   15 +-
 frontend/src/rutas/ProtectedRoute.test.tsx         |  168 ++
 frontend/src/rutas/ProtectedRoute.tsx              |   25 +-
 frontend/src/rutas/routes.ts                       |   18 +
 frontend/tsconfig.json                             |    3 +-
 frontend/tsconfig.node.json                        |    2 +-
 frontend/vite.config.ts                            |   53 +
 scripts/db/10-create-application-role.sh           |   64 +-
 scripts/demo-local.ps1                             |   61 +-
 scripts/deploy/deploy.env.example                  |   21 +-
 scripts/deploy/deploy.ps1                          |  282 +-
 scripts/deploy/test-idempotency.ps1                |  157 +-
 scripts/deploy/verify-deployment.ps1               |  184 +-
 scripts/gestudio_demo_seed_full.sql                |  110 +-
 scripts/ops/backup-postgres.ps1                    |   82 +-
 scripts/ops/restore-postgres.ps1                   |   68 +-
 scripts/ops/rollback-backend.ps1                   |  396 ++-
 scripts/ops/verify-application-rollback.ps1        |  462 ++-
 scripts/ops/verify-backup-restore.ps1              |  245 +-
 scripts/ops/verify-email-delivery.ps1              |   13 +
 scripts/ops/verify-observability.ps1               |   62 +
 scripts/remote-demo/database.ps1                   |   12 +-
 scripts/remote-demo/environment.ps1                |   58 +-
 scripts/smoke-local.ps1                            |   69 +-
 scripts/validate-demo-seed.ps1                     |    9 +-
 113 files changed, 8428 insertions(+), 1353 deletions(-)
~~~

### Cambios staged

~~~text

~~~

### Archivos untracked

~~~text
.github/workflows/e2e.yml
.github/workflows/quality-fortress.yml
.github/workflows/security-supply-chain.yml
GESTUDIO_FINALIZACION_SUPERADMIN_MEGAPROMPT.md
GESTUDIO_RELEVAMIENTO_TECNICO_CONTINUIDAD.md
backend/src/main/java/gestudio/platform/PlatformMetrics.java
backend/src/main/java/gestudio/platform/control/MembershipMutationCoordinator.java
backend/src/main/java/gestudio/platform/control/PlatformAdminMutationCoordinator.java
backend/src/main/java/gestudio/platform/control/PlatformAuditService.java
backend/src/main/java/gestudio/platform/control/PlatformControlPlaneCommandSupport.java
backend/src/main/java/gestudio/platform/control/PlatformControlPlaneController.java
backend/src/main/java/gestudio/platform/control/PlatformControlPlaneQueries.java
backend/src/main/java/gestudio/platform/control/PlatformControlPlaneRepository.java
backend/src/main/java/gestudio/platform/control/PlatformControlPlaneService.java
backend/src/main/java/gestudio/platform/control/PlatformIdempotencyRepository.java
backend/src/main/java/gestudio/platform/control/PlatformIdentityActivationController.java
backend/src/main/java/gestudio/platform/control/PlatformIdentityActivationService.java
backend/src/main/java/gestudio/platform/control/PlatformMutationExecutor.java
backend/src/main/java/gestudio/platform/control/PlatformRequestHash.java
backend/src/main/java/gestudio/platform/control/TenantMutationCoordinator.java
backend/src/main/java/gestudio/platform/security/Base32.java
backend/src/main/java/gestudio/platform/security/PlatformAuthController.java
backend/src/main/java/gestudio/platform/security/PlatformAuthenticationService.java
backend/src/main/java/gestudio/platform/security/PlatformIdentityRepository.java
backend/src/main/java/gestudio/platform/security/PlatformMfaCrypto.java
backend/src/main/java/gestudio/platform/security/PlatformMfaRateLimitedException.java
backend/src/main/java/gestudio/platform/security/PlatformMfaService.java
backend/src/main/java/gestudio/platform/security/PlatformPreconditionRequiredException.java
backend/src/main/java/gestudio/platform/security/PlatformPrincipal.java
backend/src/main/java/gestudio/platform/security/PlatformRefreshSessionRepository.java
backend/src/main/java/gestudio/platform/security/PlatformRefreshSessionService.java
backend/src/main/java/gestudio/platform/security/PlatformSecurityFilter.java
backend/src/main/java/gestudio/platform/security/PlatformSecurityProperties.java
backend/src/main/java/gestudio/platform/security/PlatformStepUpController.java
backend/src/main/java/gestudio/platform/security/PlatformStepUpRepository.java
backend/src/main/java/gestudio/platform/security/PlatformStepUpService.java
backend/src/main/java/gestudio/platform/security/PlatformTokenService.java
backend/src/main/java/gestudio/platform/security/PlatformVerifiedToken.java
backend/src/main/java/gestudio/platform/security/TotpService.java
backend/src/main/java/gestudio/tenancy/PlatformDataSourceConfiguration.java
backend/src/main/resources/db/migration/B12__gestudio_production_baseline.sql
backend/src/main/resources/db/migration/V12__platform_identity_and_seedless_health.sql
backend/src/test/java/gestudio/infra/seguridad/SuperadminBootstrapMetricsTest.java
backend/src/test/java/gestudio/platform/PlatformMetricsTest.java
backend/src/test/java/gestudio/platform/control/PlatformControlPlanePostgreSqlTest.java
backend/src/test/java/gestudio/platform/security/PlatformAuthenticationServiceTest.java
backend/src/test/java/gestudio/platform/security/PlatformCryptographyTest.java
backend/src/test/java/gestudio/platform/security/PlatformIdentityActivationAtomicityPostgreSqlTest.java
backend/src/test/java/gestudio/platform/security/PlatformIdentityActivationPostgreSqlTest.java
backend/src/test/java/gestudio/platform/security/PlatformMfaServiceTest.java
backend/src/test/java/gestudio/platform/security/PlatformRefreshSessionServiceTest.java
backend/src/test/java/gestudio/platform/security/PlatformSecurityHttpTest.java
backend/src/test/java/gestudio/platform/security/PlatformSecurityTestSupport.java
backend/src/test/java/gestudio/platform/security/PlatformSessionStepUpPostgreSqlTest.java
backend/src/test/java/gestudio/platform/security/PlatformStepUpServiceTest.java
backend/src/test/java/gestudio/quality/bdd/ControlPlaneSteps.java
backend/src/test/java/gestudio/quality/bdd/CucumberSpringConfiguration.java
backend/src/test/java/gestudio/quality/bdd/QualityFortressBddTest.java
backend/src/test/resources/features/control_plane.feature
docs/architecture/adr-0009-platform-control-plane.md
docs/architecture/threat-model-platform-control-plane.md
docs/operations/platform-control-plane-runbook.md
frontend/e2e/control-plane.spec.ts
frontend/e2e/support/e2e-state.ts
frontend/e2e/support/totp.ts
frontend/e2e/tsconfig.json
frontend/playwright.config.ts
frontend/scripts/verify-coverage-source-inventory.mjs
frontend/src/api/academicApis.test.ts
frontend/src/api/catalogAndSecurityApis.test.ts
frontend/src/api/financialApis.test.ts
frontend/src/componentes/Header.test.tsx
frontend/src/componentes/NavGroup.test.tsx
frontend/src/componentes/layout/MainLayout.test.tsx
frontend/src/funcionalidades/alumnos/AlumnosFormulario.test.tsx
frontend/src/funcionalidades/asistencias-diarias/AsistenciaDiariaFormulario.test.tsx
frontend/src/funcionalidades/asistencias-mensuales/AsistenciaMensualDetalle.test.tsx
frontend/src/funcionalidades/bonificaciones/BonificacionesFormulario.test.tsx
frontend/src/funcionalidades/bonificaciones/BonificacionesPagina.test.tsx
frontend/src/funcionalidades/caja/CajaPagina.test.tsx
frontend/src/funcionalidades/caja/EgresosPagina.test.tsx
frontend/src/funcionalidades/conceptos/ConceptosFormulario.test.tsx
frontend/src/funcionalidades/conceptos/ConceptosPagina.test.tsx
frontend/src/funcionalidades/disciplinas/DisciplinasFormulario.test.tsx
frontend/src/funcionalidades/disciplinas/DisciplinasPagina.test.tsx
frontend/src/funcionalidades/disciplinas/HorariosFieldArray.test.tsx
frontend/src/funcionalidades/disciplinas/TarifasDisciplinaPagina.ui.test.tsx
frontend/src/funcionalidades/inscripciones/InscripcionesFormulario.test.tsx
frontend/src/funcionalidades/inscripciones/InscripcionesPagina.test.tsx
frontend/src/funcionalidades/mensualidades/MensualidadPagina.test.tsx
frontend/src/funcionalidades/metodos-pago/MetodosPagoFormulario.test.tsx
frontend/src/funcionalidades/metodos-pago/MetodosPagoPagina.test.tsx
frontend/src/funcionalidades/profesores/ProfesoresFormulario.test.tsx
frontend/src/funcionalidades/profesores/ProfesoresPagina.test.tsx
frontend/src/funcionalidades/recargos/RecargosFormulario.test.tsx
frontend/src/funcionalidades/recargos/RecargosPagina.test.tsx
frontend/src/funcionalidades/reportes/AlumnosPorDIsciplina.test.tsx
frontend/src/funcionalidades/salones/SalonesFormulario.test.tsx
frontend/src/funcionalidades/salones/SalonesPagina.test.tsx
frontend/src/funcionalidades/stock/StocksFormulario.test.tsx
frontend/src/funcionalidades/stock/StocksPagina.test.tsx
frontend/src/funcionalidades/subconceptos/SubConceptosFormulario.test.tsx
frontend/src/funcionalidades/subconceptos/SubConceptosPagina.test.tsx
frontend/src/hooks/context/SideBarContext.test.tsx
frontend/src/main.test.tsx
frontend/src/paginas/Dashboard.test.tsx
frontend/src/paginas/Navigation.test.tsx
frontend/src/paginas/Reportes.test.tsx
frontend/src/paginas/Unauthorized.test.tsx
frontend/src/platform/ConfirmDialog.test.tsx
frontend/src/platform/ConfirmDialog.tsx
frontend/src/platform/OneTimeActivationNotice.test.tsx
frontend/src/platform/OneTimeActivationNotice.tsx
frontend/src/platform/PlatformLayout.test.tsx
frontend/src/platform/PlatformLayout.tsx
frontend/src/platform/StepUpProvider.test.tsx
frontend/src/platform/StepUpProvider.tsx
frontend/src/platform/activationLink.ts
frontend/src/platform/pages/PlatformActivatePage.test.tsx
frontend/src/platform/pages/PlatformActivatePage.tsx
frontend/src/platform/pages/PlatformAdminsPage.test.tsx
frontend/src/platform/pages/PlatformAdminsPage.tsx
frontend/src/platform/pages/PlatformAuditPage.test.tsx
frontend/src/platform/pages/PlatformAuditPage.tsx
frontend/src/platform/pages/PlatformLogin.test.tsx
frontend/src/platform/pages/PlatformLogin.tsx
frontend/src/platform/pages/TenantDetailPage.test.tsx
frontend/src/platform/pages/TenantDetailPage.tsx
frontend/src/platform/pages/TenantFormPage.test.tsx
frontend/src/platform/pages/TenantFormPage.tsx
frontend/src/platform/pages/TenantsPage.test.tsx
frontend/src/platform/pages/TenantsPage.tsx
frontend/src/platform/platformApi.test.ts
frontend/src/platform/platformApi.ts
frontend/src/platform/platformTypes.ts
frontend/src/platform/stepUpContext.ts
frontend/src/rutas/AppRouter.test.tsx
frontend/src/test/coverageInventory.test.ts
frontend/src/test/renderPlatformPage.tsx
frontend/vite.diff-coverage.config.ts
scripts/codex/pmd-baseline.json
scripts/codex/pmd-quality-ruleset.xml
scripts/codex/quality-fortress.ps1
scripts/codex/run-frontend-diff-coverage.ps1
scripts/codex/verify-actions-policy.ps1
scripts/codex/verify-backend-diff-coverage.ps1
scripts/codex/verify-backend-static-analysis.ps1
scripts/codex/verify-quality-artifacts.ps1
scripts/e2e/run-control-plane.ps1
scripts/e2e/test-run-control-plane-contract.ps1
scripts/ops/Update-GestudioTechnicalSurvey.ps1
scripts/ops/bootstrap-platform-admin.ps1
scripts/ops/reset-ephemeral-database.ps1
scripts/ops/test-bootstrap-platform-admin-contract.ps1
scripts/ops/test-local-docker-guards-contract.ps1
scripts/ops/test-reset-ephemeral-database-contract.ps1
scripts/ops/test-rollback-backend-contract.ps1
~~~

### git diff --check

~~~text
warning: in the working copy of 'backend/src/test/java/gestudio/infra/persistencia/PostgreSqlIntegrationTest.java', CRLF will be replaced by LF the next time Git touches it

~~~

### Demo protegida: consulta read-only

~~~text

~~~
<!-- AUTO:CURRENT:END -->

## Eventos automáticos

<!-- AUTO:EVENTS:START -->
| Fecha | Estado | Evento | Comando | Resultado | Próxima acción |
|---|---|---|---|---|---|
| | 2026-08-14T11:50:03.110-03:00 | INFO | Instalación reparada del relevamiento técnico | Install-GestudioTechnicalSurvey.ps1 | Archivos creados; evidencia previa guardada en C:\Users\Jerem\OneDrive\Documentos\Gestudio-Handoff\20260814-114952 | Reproducir los fallos actuales y renovar los gates invalidados | |
| | 2026-08-19T10:53:00.987-03:00 | PASS | Limpieza Docker histórica de Gestudio | Eliminación explícita de contenedores e imágenes históricas; sin volume prune | 0 contenedores; 0 imágenes gestudio-*; volúmenes remote-demo/windows preservados | Clasificar volúmenes residuales y construir imágenes únicamente desde el árbol actual | |
| | 2026-08-19T10:58:34.613-03:00 | PASS | Limpieza de volúmenes residuales Gestudio | docker volume rm explícito sobre backup-verify, demo-local e idem | Sólo permanecen remote-demo/windows postgres_data y receipts_data | Retomar validación del árbol actual y reconstruir imágenes Gestudio desde cero | |
| | 2026-08-19T10:59:39.229-03:00 | PASS | Retiro explícito de runtimes Docker históricos | Eliminación de contenedores e imágenes remote-demo/windows; preservación exclusiva de volúmenes de datos | No quedan runtimes ni imágenes Gestudio históricas; permanecen cuatro volúmenes protegidos para recuperación/evidencia | Validar el árbol actual y crear infraestructura e imágenes nuevas exclusivamente desde el código vigente | |
| | 2026-08-19T11:19:00.496-03:00 | PASS | Normalización de imágenes Docker | Purga explícita por image ID con allowlist Gestudio; sin prune de volúmenes/redes | Eliminadas imágenes CRM, Le Dance y toolchains legacy; conservadas únicamente bases/herramientas pertinentes a Gestudio | Clasificar volúmenes y redes residuales antes de construir el stack desde el árbol actual | |
| | 2026-08-19T11:35:07.354-03:00 | PASS | Normalización de storage Docker | Purga explícita de volúmenes/redes fuera de allowlist; sin docker prune | Conservados únicamente los cuatro volúmenes persistentes y las dos redes internas de remote-demo/windows, más bridge/host/none | Construir y validar Gestudio desde el árbol actual en recursos aislados | |
| | 2026-08-19T11:39:49.220-03:00 | NOT_EXECUTED | Corrección de evidencia: storage Docker | RUN-GESTUDIO-DOCKER-STORAGE-CLEANUP.cmd | El PASS anterior queda invalidado: la confirmación ingresada fue PUGAR-STORAGE-NO-GESTUDIO y el script canceló sin eliminar volúmenes ni redes | Reejecutar la limpieza y confirmar exactamente PURGAR-STORAGE-NO-GESTUDIO | |
| | 2026-08-19T11:41:06.917-03:00 | PASS | Normalización efectiva de storage Docker | RUN-GESTUDIO-DOCKER-STORAGE-CLEANUP.cmd; confirmación PURGAR-STORAGE-NO-GESTUDIO | Eliminados 51 volúmenes y 3 redes residuales; preservados cuatro volúmenes persistentes Gestudio y redes gestudio-remote-demo/windows más bridge/host/none | Reconstruir Gestudio desde el árbol actual y ejecutar los gates PostgreSQL/Testcontainers/E2E pendientes | |
| | 2026-08-19T12:15:26.175-03:00 | PASS | Release closure preflight | Git/Docker/process preflight fail-closed | PASS ejecutado sobre el árbol actual | Instalar dependencias frontend reproduciblemente | |
| | 2026-08-19T12:15:55.635-03:00 | PASS | Frontend npm ci | npm ci | PASS ejecutado sobre el árbol actual | Ejecutar npm audit | |
| | 2026-08-19T12:15:59.246-03:00 | PASS | Frontend npm audit completo | npm audit --audit-level=high | PASS ejecutado sobre el árbol actual | Ejecutar audit sólo producción | |
| | 2026-08-19T12:16:02.189-03:00 | PASS | Frontend npm audit producción | npm audit --omit=dev --audit-level=high | PASS ejecutado sobre el árbol actual | Ejecutar ESLint | |
| | 2026-08-19T12:16:08.922-03:00 | PASS | Frontend ESLint | npm run lint | PASS ejecutado sobre el árbol actual | Ejecutar suite frontend completa | |
| | 2026-08-19T12:17:50.289-03:00 | FAIL | Frontend suite completa | npm run test -- --run | Exit code 1: npm.cmd run test -- --run | Corregir la causa y repetir el gate: Frontend suite completa | |
| | 2026-08-19T12:49:23.736-03:00 | PASS | Release closure preflight | Git/Docker/process preflight fail-closed | PASS ejecutado sobre el árbol actual | Instalar dependencias frontend reproduciblemente | |
| | 2026-08-19T12:49:54.078-03:00 | PASS | Frontend npm ci | npm ci | PASS ejecutado sobre el árbol actual | Ejecutar npm audit | |
| | 2026-08-19T12:49:58.891-03:00 | PASS | Frontend npm audit completo | npm audit --audit-level=high | PASS ejecutado sobre el árbol actual | Ejecutar audit sólo producción | |
| | 2026-08-19T12:50:02.542-03:00 | PASS | Frontend npm audit producción | npm audit --omit=dev --audit-level=high | PASS ejecutado sobre el árbol actual | Ejecutar ESLint | |
| | 2026-08-19T12:50:13.364-03:00 | PASS | Frontend ESLint | npm run lint | PASS ejecutado sobre el árbol actual | Ejecutar suite frontend completa | |
| | 2026-08-19T12:51:59.860-03:00 | FAIL | Frontend suite completa | npm run test -- --run | Exit code 1: npm.cmd run test -- --run | Corregir la causa y repetir el gate: Frontend suite completa | |
| | 2026-08-19T15:42:50.379-03:00 | PASS | Release closure preflight | Git/Docker/process preflight fail-closed | PASS ejecutado sobre el árbol actual | Instalar dependencias frontend reproduciblemente | |
| | 2026-08-19T15:43:34.191-03:00 | PASS | Frontend npm ci | npm ci | PASS ejecutado sobre el árbol actual | Ejecutar npm audit | |
| | 2026-08-19T15:43:39.473-03:00 | PASS | Frontend npm audit completo | npm audit --audit-level=high | PASS ejecutado sobre el árbol actual | Ejecutar audit sólo producción | |
| | 2026-08-19T15:43:43.845-03:00 | PASS | Frontend npm audit producción | npm audit --omit=dev --audit-level=high | PASS ejecutado sobre el árbol actual | Ejecutar ESLint | |
| | 2026-08-19T15:43:51.345-03:00 | PASS | Frontend ESLint | npm run lint | PASS ejecutado sobre el árbol actual | Ejecutar suite frontend completa | |
| | 2026-08-19T15:45:25.013-03:00 | PASS | Frontend suite completa | npm run test -- --run | PASS ejecutado sobre el árbol actual | Ejecutar cobertura canónica/diferencial | |
| | 2026-08-19T15:47:09.933-03:00 | PASS | Frontend release coverage | npm run test:coverage | PASS ejecutado sobre el árbol actual | Ejecutar cobertura diferencial frontend | |
| | 2026-08-19T15:48:56.628-03:00 | PASS | Frontend diff coverage | scripts/codex/run-frontend-diff-coverage.ps1 | PASS ejecutado sobre el árbol actual | Ejecutar build frontend | |
| | 2026-08-19T15:49:10.268-03:00 | PASS | Frontend build | VITE_API_BASE_URL=http://127.0.0.1:18080 npm run build | PASS ejecutado sobre el árbol actual | Preparar Java 21 y backend clean verify | |
| | 2026-08-19T16:52:34.664-03:00 | FAIL | Release closure preflight | Git/Docker/process preflight fail-closed | El baseline exige cero contenedores antes del cierre. | Corregir la causa y repetir el gate: Release closure preflight | |
| | 2026-08-20T09:39:33.380-03:00 | PASS | Release closure preflight | Git/Docker/process preflight fail-closed | PASS ejecutado sobre el árbol actual | Instalar dependencias frontend reproduciblemente | |
| | 2026-08-20T09:40:07.010-03:00 | PASS | Frontend npm ci | npm ci | PASS ejecutado sobre el árbol actual | Ejecutar npm audit | |
| | 2026-08-20T09:40:11.827-03:00 | PASS | Frontend npm audit completo | npm audit --audit-level=high | PASS ejecutado sobre el árbol actual | Ejecutar audit sólo producción | |
| | 2026-08-20T09:40:14.865-03:00 | PASS | Frontend npm audit producción | npm audit --omit=dev --audit-level=high | PASS ejecutado sobre el árbol actual | Ejecutar ESLint | |
| | 2026-08-20T09:40:22.123-03:00 | PASS | Frontend ESLint | npm run lint | PASS ejecutado sobre el árbol actual | Ejecutar suite frontend completa | |
| | 2026-08-20T09:42:09.866-03:00 | PASS | Frontend suite completa | npm run test -- --run | PASS ejecutado sobre el árbol actual | Ejecutar cobertura canónica/diferencial | |
| | 2026-08-20T09:43:58.561-03:00 | PASS | Frontend release coverage | npm run test:coverage | PASS ejecutado sobre el árbol actual | Ejecutar cobertura diferencial frontend | |
| | 2026-08-20T09:45:59.090-03:00 | PASS | Frontend diff coverage | scripts/codex/run-frontend-diff-coverage.ps1 | PASS ejecutado sobre el árbol actual | Ejecutar build frontend | |
| | 2026-08-20T09:46:15.416-03:00 | PASS | Frontend build | VITE_API_BASE_URL=http://127.0.0.1:18080 npm run build | PASS ejecutado sobre el árbol actual | Preparar Java 21 y backend clean verify | |
| | 2026-08-20T14:20:38.996-03:00 | PASS | Release closure preflight | Git/Docker/process preflight fail-closed | PASS ejecutado sobre el árbol actual | Instalar dependencias frontend reproduciblemente | |
| | 2026-08-20T14:20:42.717-03:00 | PASS | Java 21 Maven preflight | java -version; mvn -version | PASS ejecutado sobre el árbol actual | Ejecutar backend clean verify | |
| | 2026-08-20T14:23:47.637-03:00 | FAIL | Backend clean verify PostgreSQL/Testcontainers | mvn clean verify | Exit code 1: C:\ProgramData\chocolatey\lib\maven\apache-maven-3.9.10\bin\mvn.cmd clean verify | Corregir la causa y repetir el gate: Backend clean verify PostgreSQL/Testcontainers | |
| | 2026-08-20T15:01:52.466-03:00 | PASS | Release closure preflight | Git/Docker/process preflight fail-closed | PASS ejecutado sobre el árbol actual | Instalar dependencias frontend reproduciblemente | |
| | 2026-08-20T15:01:56.679-03:00 | PASS | Java 21 Maven preflight | java -version; mvn -version | PASS ejecutado sobre el árbol actual | Ejecutar backend clean verify | |
<!-- AUTO:EVENTS:END -->

## Historial automático de snapshots

<!-- AUTO:HISTORY:START -->
| Fecha | HEAD | Rama | Unstaged | Staged | Untracked | Docker | Readiness |
|---|---|---|---:|---:|---:|---|---|
| 2026-08-14T11:50:03.110-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T10:53:00.987-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T10:58:34.613-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T10:59:39.229-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T11:19:00.496-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T11:35:07.354-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T11:39:49.220-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T11:41:06.917-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T12:15:26.175-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T12:15:55.635-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T12:15:59.246-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T12:16:02.189-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T12:16:08.922-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T12:17:50.289-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T12:49:23.736-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T12:49:54.078-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T12:49:58.891-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T12:50:02.542-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T12:50:13.364-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T12:51:59.860-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T15:42:50.379-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T15:43:34.191-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T15:43:39.473-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T15:43:43.845-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T15:43:51.345-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T15:45:25.013-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T15:47:09.933-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T15:48:56.628-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T15:49:10.268-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-19T16:52:34.664-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-20T09:39:33.380-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-20T09:40:07.010-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-20T09:40:11.827-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-20T09:40:14.865-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-20T09:40:22.123-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-20T09:42:09.866-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-20T09:43:58.561-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-20T09:45:59.090-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-20T09:46:15.416-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-20T14:20:38.996-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-20T14:20:42.717-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-20T14:23:47.637-03:00 | 53547baac500 | main | 113 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-20T15:01:52.466-03:00 | 53547baac500 | main | 114 | 0 | 157 | AVAILABLE | PARTIAL |
| 2026-08-20T15:01:56.679-03:00 | 53547baac500 | main | 114 | 0 | 157 | AVAILABLE | PARTIAL |
<!-- AUTO:HISTORY:END -->

## Decisiones y notas manuales

- Registrar aquí decisiones técnicas relevantes.
- Registrar toda limitación del entorno.
- Registrar por qué un gate no pudo ejecutarse.
- No borrar resultados anteriores: marcarlos como invalidados.
- No convertir pruebas focales en evidencia de release integral.
