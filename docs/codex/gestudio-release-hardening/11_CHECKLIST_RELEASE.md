# Checklist de release vigente

> Fecha de corte: 20 de julio de 2026  
> Estado global: **NO-GO para demo comercial, staging y producción**

Sólo se marca lo demostrado con ejecución o evidencia verificable.

## Código y entorno

- [x] Java 21, Maven Wrapper, Node 22.14.0, npm 10.x, Docker y Compose verificados.
- [x] `git diff --check` sin errores en gates integrados.
- [x] secretos reales fuera de Git.
- [x] imágenes backend y frontend construidas en CI.
- [x] imagen backend declara revisión Git y versión Flyway.

## Backend y base

- [x] `clean verify` sin `-SkipTests`.
- [x] 162/162 pruebas backend verdes después de V7.
- [x] PostgreSQL real mediante Testcontainers.
- [x] migraciones V1-V7 aplicadas sobre base vacía.
- [x] V1-V7 inmutables y forward-only.
- [x] 401, 403 y 409 diferenciados.
- [x] backend fail-closed.
- [x] idempotencia secuencial y concurrente.
- [x] liquidación por vigencia y snapshot atómico.

## Frontend

- [x] lint PASS.
- [x] 142/142 pruebas PASS.
- [x] build Vite PASS.
- [x] permisos alineados con backend.
- [x] fuentes financieras legacy retiradas de UI operativa.
- [ ] inventario final de IDs técnicos visibles.
- [ ] loading/empty/error completos.
- [ ] móvil real.
- [ ] foco, teclado, labels y contraste.

## Seguridad y demo

- [x] catálogo de 32 permisos.
- [x] cinco roles operativos.
- [x] PROFESOR inactivo/no asignable.
- [x] refresh token HttpOnly.
- [x] STOMP retirado.
- [x] seed doble y cinco logins PASS.
- [x] smoke V1-V7 PASS.
- [x] recursos Docker residuales: ninguno.
- [ ] recorridos humanos completos por rol.
- [ ] guion comercial y capturas definitivas.

## Integración V7

- [x] emisor source-owned mínimo y firmado.
- [x] mapping tenant fail-closed.
- [x] feature deshabilitada por defecto.
- [x] secreto externo independiente.
- [x] permisos administrativos dobles.
- [x] snapshots/páginas inmutables.
- [ ] receptor multipágina end-to-end compatible.
- [ ] transporte automático autorizado.

## Backup y restore

- [x] dump PostgreSQL custom.
- [x] backup de recibos.
- [x] manifiesto con tamaños y SHA-256.
- [x] consistencia de aplicación con backend detenido.
- [x] restore destructivo protegido.
- [x] restore alternativo de datos, V7 y recibo.
- [x] cleanup completo.
- [ ] destino externo cifrado.
- [ ] retención, RPO/RTO y responsables.

## Rollback

- [x] metadata Flyway por imagen.
- [x] confirmación explícita.
- [x] race guard de imagen actual.
- [x] imagen V6 rechazada antes del cambio.
- [x] backup consistente previo.
- [x] rollback a artefacto anterior compatible.
- [x] dato, Flyway V7 y tablas V7 preservados.
- [x] retorno al artefacto actual.
- [x] recuperación automática ante target unhealthy implementada.
- [x] cleanup de stack, imágenes, worktree y temporales.
- [ ] registry productivo por digest.
- [ ] firma, promoción y retención de artefactos.
- [ ] coordinación de rollback frontend.
- [ ] procedimiento para efectos externos.

## Observabilidad y ambiente

- [ ] health/readiness/liveness seguros.
- [ ] métricas HTTP, JVM, pool y DB.
- [ ] correlación de requests.
- [ ] logs sanitizados y estructurados.
- [ ] alertas y runbook de incidentes.
- [ ] staging definido.
- [ ] secret manager.
- [ ] TLS, CORS y cookies verificados.
- [ ] todos los gates repetidos en staging.
- [ ] autorización de producción.

## Decisión

Seguridad, finanzas, V7, demo automatizada, backup, restore y rollback técnico están aprobados dentro de infraestructura descartable. Observabilidad, GATE-2, demo humana, políticas operativas y ambiente externo siguen bloqueando demo comercial, staging y producción.
