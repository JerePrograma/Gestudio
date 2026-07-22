# Cierre técnico de release — 2026-07-22

## Decisión

El árbol quedó localmente apto para desarrollo, demo, CI, backup/restore y
rollback de aplicación. La publicación productiva sigue siendo una decisión de
operaciones sobre un ambiente con TLS, secretos, almacenamiento, monitoreo,
correo y recuperación configurados.

SHA de código validado: `c1f88c7a2e3118bbbd7f770135815056dc6fcebb`.
El informe externo de publicación registra por separado el SHA documental final
y los enlaces de Actions de ese propio commit.

## Correcciones consolidadas

- Fecha civil de Buenos Aires y cumpleaños exactos, incluidos año nuevo y 29/2.
- Exclusión de personas inactivas, inserción atómica y envío posterior al commit.
- Flyway dinámico y contiguo, seed idempotente de 914 filas y RBAC de cinco roles.
- Producción fail-closed, cookie `Secure`, CORS explícito, métrica protegida,
  request ID y eliminación de logs sensibles.
- Java 21/Spring Boot 3.5.16, OSIV desactivado, límites de login, consultas
  PostgreSQL, horarios civiles invariantes a la zona del host y correcciones de
  estado/lazy loading.
- Frontend reproducible, fechas civiles, logout, notificaciones accesibles,
  Nginx no-root, headers y rutas SPA.
- Backup/restore v2 con manifiesto, `backupSetId`, SHA-256 y recibos confinados.
- Rollback de imagen forward-compatible y retorno a la versión actual.
- Workflows en `main`, acciones fijadas, auditorías, gates operativos y cleanup.

## Matriz ejecutada

| Superficie | Evidencia |
|---|---|
| Backend | `clean test` y `clean verify`: 203 pruebas, 0/0, 2 skips Windows |
| Frontend | `npm ci`, auditorías 0, lint, 149 tests, 2 contratos Nginx y build |
| Docker | config local/prod, build sin cache, usuarios 100/101, HTTP/SPA/headers |
| Demo | volúmenes vacíos, 914 filas, cinco logins, RBAC y segunda corrida idéntica |
| Smoke | 20/20 |
| Observabilidad | 8/8 |
| Backup/restore | 12/12 en PowerShell 7 y 12/12 en Windows PowerShell 5.1 |
| Rollback | 8/8 en PowerShell 7 y 8/8 en Windows PowerShell 5.1 |
| Navegador | cinco roles, escritorio/móvil, rutas, foco, refresh y logout |

## Seguridad y recuperación

No se versionaron secretos, `.env` reales, dumps, backups, logs, recibos,
capturas, traces, `target`, `dist`, `node_modules` ni reportes de Playwright.
Producción rechaza configuración insuficiente. Los scripts operativos generan
secretos efímeros, neutralizan variables host heredadas y limpian sólo recursos
Docker del proyecto aislado.

El restore valida antes de mutar y rechaza nombre/manifiesto manipulados,
`backupSetId` ausente o inconsistente, hashes/dump alterados, traversal, rutas
absolutas, miembros fuera de `receipts/`, symlink, hardlink, destino declarado,
tar malformado, recibos mezclados, archivo faltante y backup parcial.

## Límites

- No existen down migrations automáticas; el rollback de base es un restore.
- Una imagen anterior incompatible con el esquema avanzado se rechaza antes de
  recrear el backend.
- SMTP, Jere Platform y despliegue productivo real requieren infraestructura y
  autorización externas; no se simulan como evidencia de entrega.
- Las versiones mayores informadas por `npm outdated` no se incorporan sin una
  migración compatible y su propia matriz de regresión.

Los comandos exactos se mantienen en `TESTING.md` y en los runbooks de
`docs/operations/`.
