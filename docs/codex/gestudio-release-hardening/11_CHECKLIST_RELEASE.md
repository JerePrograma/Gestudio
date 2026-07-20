# Checklist de release vigente

> Fecha de corte: 20 de julio de 2026  
> Estado global: **NO-GO para staging y producción**

Sólo se marca lo demostrado con ejecución o evidencia verificable. Este archivo reemplaza los checklist operativos anteriores; la historia permanece en la bitácora.

## Código y entorno

- [x] Java 21 verificado.
- [x] Maven Wrapper reproducible.
- [x] Node 22.14.0 y npm 10.x verificados.
- [x] Docker Engine y Compose v2 verificados.
- [x] `git diff --check` sin errores en gates integrados.
- [x] secretos reales fuera de Git.
- [x] imágenes backend y frontend construidas en CI.

## Backend

- [x] `clean verify` sin `-SkipTests`.
- [x] 162/162 pruebas backend verdes después de V7.
- [x] PostgreSQL 15 real mediante Testcontainers.
- [x] migraciones V1-V7 aplicadas sobre base vacía.
- [x] V1-V6 inmutables.
- [x] V7 validada en smoke, seed y restore.
- [x] 401, 403 y 409 diferenciados.
- [x] backend fail-closed.
- [x] idempotencia secuencial y concurrente.
- [x] liquidación financiera por vigencia.
- [x] cargo y snapshot atómicos.

## Frontend

- [x] lint PASS.
- [x] 142/142 pruebas PASS.
- [x] build Vite PASS.
- [x] permisos alineados con backend.
- [x] fuentes financieras legacy retiradas de la UI operativa.
- [ ] inventario final de IDs técnicos visibles.
- [ ] estados loading/empty/error completos.
- [ ] recorrido móvil real.
- [ ] foco, teclado, labels y contraste completos.

## Seguridad y roles

- [x] catálogo de 32 permisos.
- [x] SUPERADMIN, DIRECCION, ADMINISTRADOR, SECRETARIA y CAJA.
- [x] PROFESOR inactivo y no asignable.
- [x] refresh token sólo en cookie HttpOnly.
- [x] roles/permisos inactivos no autorizan.
- [x] STOMP retirado.
- [ ] recorridos humanos completos por los cinco roles.

## Demo

- [x] seed sintético.
- [x] primera aplicación PASS.
- [x] segunda aplicación con snapshot idéntico.
- [x] cinco logins PASS.
- [x] RBAC e integridad financiera PASS.
- [x] smoke canónico V1-V7 PASS.
- [x] recursos Docker residuales: ninguno.
- [ ] recorrido visual humano completo.
- [ ] guion comercial cronometrado.
- [ ] capturas definitivas.

## Integración V7

- [x] emisor source-owned implementado.
- [x] payload mínimo y firmado.
- [x] mapping de tenant fail-closed.
- [x] función deshabilitada por defecto.
- [x] secreto independiente externo.
- [x] permisos administrativos dobles.
- [x] snapshots/páginas inmutables.
- [ ] receptor multipágina end-to-end compatible.
- [ ] transporte automático autorizado.

## Backup y restore

- [x] dump PostgreSQL custom.
- [x] backup de recibos.
- [x] manifiesto con tamaños y SHA-256.
- [x] backup consistente con backend detenido.
- [x] restore destructivo protegido.
- [x] restore sobre base alternativa.
- [x] datos sintéticos recuperados.
- [x] Flyway V7 verificada después del restore.
- [x] recibo recuperado.
- [x] origen no alterado por restore alternativo.
- [x] cleanup sin contenedores, volúmenes ni redes residuales.
- [ ] destino externo cifrado.
- [ ] retención definida.
- [ ] RPO/RTO aprobados.
- [ ] responsables y frecuencia definidos.

## Rollback y observabilidad

- [ ] rollback forward-compatible probado.
- [ ] retorno a la versión actual probado.
- [ ] health de aplicación y dependencias publicado de forma segura.
- [ ] métricas mínimas.
- [ ] logs correlacionados y sanitizados.
- [ ] alertas.
- [ ] runbook de incidentes y escalamiento.

## Ambiente

- [ ] staging definido.
- [ ] secretos cargados mediante secret manager.
- [ ] TLS verificado.
- [ ] CORS verificado.
- [ ] cookies Secure/SameSite/Domain verificadas.
- [ ] backup/restore ejecutado en staging.
- [ ] rollback ejecutado en staging.
- [ ] observabilidad operativa en staging.
- [ ] autorización de producción.

## Decisión

La aprobación de GATE-1, GATE-1B, demo automatizada y backup/restore técnico **no autoriza** demo comercial, staging ni producción. El siguiente gate operativo es rollback forward-compatible, seguido por observabilidad y recorridos humanos.
