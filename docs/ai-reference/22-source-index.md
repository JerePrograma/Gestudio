# Índice de fuentes

> Estado: CONFIRMADO  
> Última revisión: 2026-07-26  
> Fuentes principales: trazabilidad de esta base

| Tema | Documento | Fuente/símbolos | Certeza |
|---|---|---|---|
| Identidad | 01 | `README.md`, `AGENTS.md` | CONFIRMADO |
| Estado remoto | 27 | GitHub `main`, commits, PRs e issues `#23`–`#26` | CONFIRMADO |
| Arquitectura | 03 | `AGENTS.md`, paquetes; `.kiro` histórica | CONFIRMADO |
| Stack backend | 06 | `backend/pom.xml` | CONFIRMADO |
| Stack frontend | 07 | `frontend/package.json` | CONFIRMADO |
| Rutas UI | 07, 25 | `routes.ts`, `AppRouter.tsx` | CONFIRMADO |
| API total | 08 | `SecurityHttpIntegrationTest.discoverEndpoints`, `PageResponse` | CONFIRMADO |
| RBAC | 10, 25 | `SecurityConfigurations`, `PermissionCodes` | CONFIRMADO |
| Login/refresh | 05, 10 | `AutenticacionControlador`, `AutenticacionService` | CONFIRMADO |
| Usuarios | 08, 25 | `UsuarioControlador` | CONFIRMADO |
| Roles/permisos | 08, 25 | `RolControlador`, `PermisoControlador` | CONFIRMADO |
| Alumnos | 04, 05, 08 | `AlumnoControlador`, `AlumnoServicio` | CONFIRMADO |
| Inscripciones | 04, 05, 08 | `InscripcionControlador` | CONFIRMADO |
| Disciplinas | 04, 08 | `DisciplinaControlador` | CONFIRMADO |
| Profesores | 04, 08 | `ProfesorControlador` | CONFIRMADO |
| Asistencia | 04, 05, 08 | controladores diaria/mensual | CONFIRMADO |
| Vigencias | 04, 09 | tarifas/condiciones, V4 | CONFIRMADO |
| Liquidación | 04, 05 | `LiquidacionCargoServicio` | CONFIRMADO |
| Pagos | 04, 05, 08 | `PagoControlador`, `PagoServicio` | CONFIRMADO |
| Caja/egresos | 05, 08 | `CajaControlador`, `EgresoControlador` | CONFIRMADO |
| Stock/crédito | 05, 08 | `StockControlador`, `CreditoControlador` | CONFIRMADO |
| Reportes/PDF | 08 | `ReporteControlador`, `PdfService` | CONFIRMADO |
| Notificaciones | 05, 26 | `NotificacionControlador`, `ScheduledTasks` | CONFIRMADO |
| Jobs | 26 | `ScheduledTasks` | CONFIRMADO |
| Errores | 06, 08 | `TratadorDeErrores` | CONFIRMADO |
| Entidades | 04, 09 | clases `@Entity` | PARCIAL |
| Flyway | 09 | migration dir, `AGENTS.md` | CONFIRMADO |
| Jere Platform | 11 | controller, service, integración v1, issue `#25` | CONFIRMADO |
| Email | 11 | `EmailService`, `NoOpEmailService`, issue `#23` | CONFIRMADO |
| CI | 13, 14 | `.github/workflows/*.yml` | CONFIRMADO |
| Release evidence | 13, 27 | `project-status-and-handoff.md` | CONFIRMADO |
| Demo/manual | 28 | scripts y docs | CONFIRMADO |
| Riesgos | 18, 21 | fuentes anteriores e issues `#23`–`#26` | CONFIRMADO/PARCIAL |

## Fecha y alcance

Todas las filas se revisaron el 26-07-2026 contra el `main` remoto. El índice no sustituye una búsqueda de usos antes de editar ni acredita por sí solo el resultado de CI de cada SHA.
