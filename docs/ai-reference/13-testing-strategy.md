# Estrategia de pruebas

> Estado: CONFIRMADO  
> Última revisión: 2026-07-24  
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

`SecurityHttpIntegrationTest`:

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
