# Estrategia de pruebas

> Estado: REFERENCIA HISTÓRICA CON ADDENDUM ACTUAL
> Última revisión: 2026-08-13
> Fuentes principales: `../../AGENTS.md`, `../../backend/pom.xml`, frontend, CI y evidencia de release

## Frameworks

Backend: JUnit 5, Spring Boot Test, Spring Security Test, Mockito, MockMvc, Testcontainers PostgreSQL y JaCoCo.

Frontend: Vitest, Testing Library y Node test runner para contratos Nginx.

Sistema: scripts PowerShell, Docker Compose, PostgreSQL real, navegación Playwright y certificación pública.

## Pirámide esperada

1. Unitarias de cálculos, estados y mappers.
2. Repositorios con semántica PostgreSQL.
3. Integración de servicios.
4. MockMvc para API/RBAC.
5. End-to-end para pagos y flujos críticos.
6. Smoke/operación para imágenes, recuperación y observabilidad.

H2 no prueba migraciones, locking, constraints ni SQL PostgreSQL.

## Contrato API y seguridad

La cifra histórica de mappings que sigue abajo pertenece al corte 2026-07-24;
no debe usarse como inventario del control plane actual. El contrato vivo de
release está en `../../GESTUDIO_FINALIZACION_SUPERADMIN_MEGAPROMPT.md`.

`SecurityHttpIntegrationTest` en aquel corte:

- descubre todos los `@RestController`;
- fija 146 mappings en el árbol inspeccionado;
- exige política explícita;
- prueba anónimo, permiso funcional sin APP, APP sin permiso y usuario autorizado;
- cubre tokens, sesiones, CORS, roles/permisos activos y errores sanitizados.

Una ruta nueva requiere actualizar seguridad y esta prueba.

## Smoke integral

`scripts/smoke-local.ps1` usa proyecto Docker efímero y cubre altas académicas, tarifas, inscripción, liquidaciones, cargos, pagos parciales/totales, recibos, caja, egresos, idempotencia, stock, reversión, RBAC, reinicio e integridad SQL.

## Certificación integral

`scripts/certify-api-complete.ps1` combina inventario/RBAC, ciclo aislado y demo pública no mutante. Genera JSON/Markdown fuera del checkout y no registra secretos.

## Evidencia fechada del release

El handoff 22-07-2026 registra:

| Gate | Resultado |
|---|---|
| Backend | 203 tests, 0 fallos, 2 skips de symlink Windows |
| Frontend | 149 Vitest + 2 contratos Nginx |
| Smoke | 20/20 |
| Observabilidad | 8/8 |
| Backup/restore | 12/12 |
| Rollback | 8/8 |
| Demo | 914 filas, 5 logins |
| Navegador | 5 roles, desktop/móvil |

Estos conteos no se extrapolan automáticamente al HEAD posterior.

## Addendum Quality Fortress y control plane

El árbol actual incorpora scopes canónicos en
`scripts/codex/quality-fortress.ps1`:

- backend global 90% líneas/85% ramas;
- backend crítico 95% líneas/90% ramas y autorización 95% ramas;
- backend diff 90%;
- PIT global 80% mutation/85% test strength y crítico 90%/90%;
- frontend release 85% líneas/80% ramas/85% sentencias, con servicios y guards
  críticos a 90% líneas;
- frontend diff 90% en líneas/sentencias/ramas de hunks ejecutables;
- PMD/CPD y duplicación frontend product-only a 2%;
- OWASP, ambos SBOM, `npm audit` y policy de Actions.

Los verificadores son fail-closed respecto de inventario, frescura, contenido y
marcador de ejecución. Los resultados pertenecen al árbol/SHA que los produjo;
una edición posterior los invalida.

El E2E permanente vive en `frontend/e2e/control-plane.spec.ts` y se orquesta con
`scripts/e2e/run-control-plane.ps1`. Cubre fresh B12, bootstrap externo, MFA y
step-up, provisioning Alpha/Beta, aislamiento RLS, lifecycle, auditoría y axe.
Typecheck o discovery no sustituyen la ejecución browser con Docker.

## CI

`.github/workflows/ci.yml` ejecuta `mvnw clean verify`, npm audit/ci/lint/test/build, Compose local/productivo, contratos demo remota, builds Docker con metadata y smoke. Existen workflows especializados para rollback, observabilidad, backup/restore, manual y GATE-1B.

## Datos, fixtures y secretos

- Datos sintéticos.
- Testcontainers para PostgreSQL.
- Seed demo fuera de Flyway e idempotente.
- Credenciales solicitadas de forma segura.
- Informes sanitizados fuera del checkout.

## Criterio para nuevas pruebas

Todo bug debe tener regresión cuando sea práctico. Cambios financieros legacy requieren caracterización previa. Migraciones requieren base limpia y upgrade. Seguridad exige 401/403 y matriz de permisos. Frontend debe probar ruta, estado de carga/error y accesibilidad.

## Fallos

No afirmar PASS si el comando no se ejecutó. Diferenciar fallo de producto, dependencia, entorno y privilegio de symlink.
