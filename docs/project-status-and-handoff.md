# Estado de release y traspaso

Fecha de validación local: 2026-07-22

Zona de negocio: `America/Argentina/Buenos_Aires`

Rama de publicación: `main`

Este documento describe el árbol de release. El SHA final, su enlace y las
ejecuciones de GitHub Actions se registran fuera del propio commit, en el informe
de cierre que acompaña la publicación. Incluir el SHA de un commit dentro de ese
mismo commit produciría una auto-referencia imposible.

## Alcance cerrado

- Cumpleaños del día civil de Buenos Aires, con `anchor_date` y
  `business_date` separados, personas activas y regla de 29 de febrero.
- Notificación única mediante inserción atómica y efecto posterior al commit.
- Manifiesto Flyway dinámico y contiguo; la cadena actual es V1-V7 sin
  constantes ejecutables que fijen siete migraciones.
- Seed demo idempotente de 914 filas, cinco usuarios, cinco logins y matriz RBAC.
- Producción fail-closed para JWT, cookie refresh, CORS y métricas.
- `open-in-view=false`, límites de login, DTO/estado de alumno y carga de
  disciplinas sin horarios duplicados ni desplazamiento por la zona del runner.
- Frontend con fecha civil, logout accesible, modal de notificaciones con estados
  de carga/error, CSP, headers Nginx y bundle sin sourcemaps.
- Imágenes backend/frontend no-root y metadata de build.
- Backup/restore con formato v2, `backupSetId`, SHA-256, recibos confinados y
  validación completa antes de modificar datos.
- Rollback de aplicación forward-compatible, sin prometer down migrations.
- Readiness/liveness, Prometheus protegido, `X-Request-ID` y logs sanitizados.
- Workflows con permisos mínimos, acciones fijadas a SHA, timeouts y artefactos
  de evidencia con retención limitada.

## Evidencia local del árbol de release

| Gate | Resultado real | Duración |
|---|---:|---:|
| Backend `clean test` | 203 pruebas; 0 fallos; 0 errores; 2 skips de symlink en Windows | 187,7 s |
| Backend `clean verify` | 203 pruebas; 0 fallos; 0 errores; 2 skips de symlink en Windows | 186,8 s |
| Frontend `npm ci` | 421 paquetes desde lockfile; exit 0 | 43,9 s |
| Auditoría npm total/productiva | 0 vulnerabilidades / 0 vulnerabilidades | — |
| Frontend lint | exit 0 | — |
| Frontend tests | 149 Vitest + 2 contratos Nginx; 0 fallos | 29,3 s |
| Frontend build | TypeScript/Vite; 2.340 módulos; 0 sourcemaps | 17,8 s |
| Compose local/productivo | ambas configuraciones válidas | — |
| Docker `build --no-cache` | backend y frontend construidos; UID 100/101 | 496,2 s |
| Smoke canónico | 20/20 | 112,7 s |
| Observabilidad | 8/8 | 39,8 s |
| Backup/restore PowerShell 7 | 12/12 | 163 s aprox. |
| Backup/restore Windows PowerShell 5.1 | 12/12 | 168 s aprox. |
| Rollback PowerShell 7 | 8/8 | 264 s aprox. |
| Rollback Windows PowerShell 5.1 | 8/8 | 173 s aprox. |
| Demo desde volúmenes vacíos | 914 filas; 5 logins; RBAC; doble seed idéntico | exit 0 |
| Navegador headed | 5 roles; escritorio/móvil; 1/1 prueba | 24,1 s |

Los dos skips locales requieren privilegios de creación de symlinks que este
host Windows no concede. Linux/GitHub Actions ejecuta esos casos y el gate local
mantiene además traversal, rutas absolutas, hardlinks y destinos de enlace.

`npm outdated` devuelve 1 porque hay versiones mayores incompatibles disponibles
(por ejemplo React 19 y Vite 8). Es inventario informativo, no una vulnerabilidad;
no se forzaron upgrades mayores en este release.

## Navegador y RBAC

El recorrido real se ejecutó contra la demo recreada desde volúmenes vacíos. Para
cada rol comprobó login, menú, rutas permitidas/denegadas, datos y vacío, foco,
primer Tab en el enlace de salto, refresh de sesión, viewport 1440×1000 y
390×844, cumpleaños, notificaciones y logout desde la interfaz.

| Rol | Contrato observado |
|---|---|
| `SUPERADMIN` | acceso total, roles y usuarios; reporte con datos |
| `DIRECCION` | gestión y usuarios; roles denegado |
| `ADMINISTRADOR` | gestión y usuarios; roles denegado |
| `SECRETARIA` | alumnos, inscripciones, asistencia, pagos, caja y reportes; seguridad/egresos denegados |
| `CAJA` | alumnos, pagos, caja, stock y métodos en lectura; inscripciones, reportes, profesores y seguridad denegados |

Los cinco `401` visibles en la consola son el refresh anónimo esperado antes de
cada login; no hubo errores de consola ni respuestas fallidas inesperadas.
Capturas y trazas se conservaron fuera del repositorio y no se versionaron.

## Límites operativos reales

- Flyway es forward-only. El rollback probado cambia la imagen de aplicación
  sólo si la imagen anterior entiende el esquema actual. Recuperar la base exige
  el procedimiento de backup/restore.
- No se probó entrega real SMTP ni transporte a Jere Platform; ambos permanecen
  desconectados salvo configuración explícita del ambiente.
- El repositorio está preparado para despliegue, pero no acredita por sí solo
  TLS, DNS, secret manager, almacenamiento persistente, retención, alertas ni
  restauración en infraestructura productiva.
- Spring Data aún advierte que algunas respuestas serializan `PageImpl`
  directamente. El contrato actual se preservó para no introducir una ruptura
  de API en este cierre; debe versionarse antes de cambiar esa forma JSON.

## Documentación operativa

- [Desarrollo local](development/local-development.md)
- [Variables de entorno](development/environment-variables.md)
- [Runbook](operations/local-runbook.md)
- [Observabilidad](operations/observability.md)
- [Backup y restore](operations/backup-restore.md)
- [Rollback](operations/rollback.md)
- [Demo persistente](testing/demo-local.md)
- [Seed demo](testing/demo-seed.md)
- [Recorrido de roles](testing/human-role-walkthrough.md)
- [Cierre técnico](codex/gestudio-release-hardening/23_CIERRE_RELEASE_2026-07-22.md)
