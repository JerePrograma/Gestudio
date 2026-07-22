# Estado vigente y riesgos controlados

Corte: 2026-07-22, `America/Argentina/Buenos_Aires`.

## Cerrado en el árbol de release

- Cumpleaños/notificaciones, concurrencia e inactivos.
- Manifiesto Flyway dinámico, seed demo, cinco logins y RBAC.
- JWT/cookie/CORS/métricas fail-closed y límites de credenciales.
- OSIV, consultas PostgreSQL, estado de alumno y horarios sin duplicados.
- Fechas civiles, logs frontend, logout y modal de notificaciones.
- Imágenes no-root, Nginx, SPA y headers.
- Smoke 20/20 y observabilidad 8/8.
- Backup/restore 12/12 y rollback 8/8 en PS 7 y PS 5.1.
- Recorrido real de navegador de los cinco roles.
- CI sobre `main` con acciones fijadas y gates críticos sin tolerancia de error.

## Riesgos residuales explícitos

| ID | Alcance | Condición exacta | Tratamiento soportado |
|---|---|---|---|
| API-PAGE-001 | API | algunas respuestas serializan `PageImpl` directamente | mantener contrato actual; versionar la respuesta antes de migrarla |
| OPS-ENV-001 | Producción | TLS, DNS, secret manager, storage, SMTP y alertas dependen del ambiente | validar con el runbook antes de promover |
| ROLLBACK-DB-001 | Base | Flyway no ofrece down migrations | restaurar un backup compatible; no simular rollback automático |
| INT-001 | Integración | transporte real a Jere Platform está deshabilitado | habilitar sólo con tenant/secreto y smoke autorizado |
| DEP-MAJOR-001 | Frontend | `npm outdated` informa majors incompatibles | migración separada con regresión completa; no forzar en este release |

Estos puntos no son marcadores: describen límites concretos del producto o del
ambiente. Ninguno reduce los gates ejecutados del release.

## Decisión de promoción

- Desarrollo: apto.
- Demo local: apta.
- CI: configurado; el SHA publicado debe terminar verde.
- Backup/restore: apto para el formato documentado.
- Rollback de aplicación: apto si la imagen anterior comprende el esquema.
- Producción: el repositorio está preparado, pero la autorización depende de
  completar la validación del ambiente real indicada en `docs/operations/`.
