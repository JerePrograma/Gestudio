# Matriz RBAC y rutas

> Estado: CONFIRMADO  
> Última revisión: 2026-07-24  
> Fuentes principales: `PermissionCodes`, `SecurityConfigurations`, `routes.ts`, pruebas

## Regla base

Salvo login/refresh/logout y perfil autenticado, toda capacidad exige `PERM_APP_ACCESO` y permiso funcional. Roles activos suman permisos activos. El fallback API es `denyAll`.

## Catálogo de 32 permisos

| Grupo | Códigos |
|---|---|
| Base/seguridad | `PERM_APP_ACCESO`, `PERM_USUARIOS_ADMIN`, `PERM_ROLES_ADMIN`, `PERM_AUDITORIA_SEGURIDAD_LEER` |
| Finanzas | `PERM_MENSUALIDADES_GENERAR_MANUAL`, `PERM_PAGOS_REGISTRAR`, `PERM_PAGOS_ANULAR`, `PERM_EGRESOS_ADMIN`, `PERM_CREDITOS_ADMIN`, `PERM_CREDITOS_CONSUMIR`, `PERM_PAGOS_LEER`, `PERM_CAJA_LEER` |
| Stock | `PERM_STOCK_ADMIN`, `PERM_STOCK_VENDER`, `PERM_STOCK_LEER` |
| Tarifas | `PERM_TARIFAS_ADMIN`, `PERM_TARIFAS_HISTORICAS`, `PERM_CONDICIONES_ECONOMICAS_ADMIN` |
| Académico | `PERM_ALUMNOS_LEER`, `PERM_ALUMNOS_ADMIN`, `PERM_INSCRIPCIONES_LEER`, `PERM_INSCRIPCIONES_ADMIN`, `PERM_DISCIPLINAS_LEER`, `PERM_DISCIPLINAS_ADMIN`, `PERM_PROFESORES_LEER`, `PERM_PROFESORES_ADMIN`, `PERM_ASISTENCIAS_LEER`, `PERM_ASISTENCIAS_REGISTRAR` |
| Reportes/config | `PERM_REPORTES_LEER`, `PERM_REPORTES_EXPORTAR`, `PERM_CONFIG_LEER`, `PERM_CONFIG_ADMIN` |

`PERM_AUDITORIA_SEGURIDAD_LEER` y `PERM_TARIFAS_HISTORICAS` no aparecen en matchers funcionales inspeccionados; confirmar uso/reserva antes de eliminarlos.

## API por familia

| Rutas | GET | Escritura/especial |
|---|---|---|
| `/api/usuarios/**` | usuarios admin | usuarios admin |
| `/api/roles/**`, `/api/permisos/**` | roles admin | roles admin |
| `/api/alumnos/**` | alumnos leer | alumnos admin |
| `/api/inscripciones/**` | inscripciones leer | inscripciones admin |
| condiciones económicas | condiciones admin | condiciones admin |
| `/api/disciplinas/**` | disciplinas leer | disciplinas admin |
| tarifas disciplina | tarifas admin | tarifas admin |
| alumnos disciplina PDF | disciplinas leer + reportes exportar | — |
| `/api/profesores/**` | profesores leer | profesores admin |
| asistencias | asistencias leer | asistencias registrar |
| mensualidades | pagos leer | generar manual / pagos anular |
| matrículas | pagos leer | inscripciones admin / pagos anular |
| cargos | pagos leer | pagos registrar |
| pagos | pagos leer | pagos registrar / pagos anular |
| caja | caja leer | — |
| egresos | egresos admin | egresos admin |
| stocks | stock leer | stock admin / vender |
| créditos | pagos leer | crédito consumir/admin |
| reportes | reportes leer | reportes exportar |
| notificaciones | alumnos leer | endpoint GET generativo |
| configuración | config leer | config admin |
| Jere Platform | config admin + reportes exportar | mismos dos |
| observaciones profesores | denegado | denegado |

## Rutas frontend

| Ruta | Permisos |
|---|---|
| `/` | APP |
| `/reportes` | APP + reportes leer |
| `/usuarios` | APP + usuarios admin |
| `/usuarios/formulario` | APP + usuarios admin |
| `/roles` | APP + roles admin |
| `/roles/formulario` | APP + roles admin |
| `/profesores` | APP + profesores leer |
| `/profesores/formulario` | APP + profesores admin |
| `/disciplinas` | APP + disciplinas leer |
| `/disciplinas/formulario` | APP + disciplinas admin |
| `/disciplinas/:id/tarifas` | APP + tarifas admin |
| `/alumnos` | APP + alumnos leer |
| `/alumnos/formulario` | APP + alumnos admin |
| `/salones` | APP + config leer |
| `/salones/formulario` | APP + config admin |
| `/bonificaciones` | APP + config leer |
| `/bonificaciones/formulario` | APP + config admin |
| `/inscripciones` | APP + inscripciones leer |
| `/inscripciones/formulario` | APP + inscripciones admin |
| `/inscripciones/:id/condiciones-economicas` | APP + condiciones admin |
| `/asistencias/alumnos` | APP + asistencias leer |
| `/asistencias-mensuales` | APP + asistencias leer |
| `/pagos` | APP + pagos leer |
| `/pagos/formulario` | APP + pagos registrar |
| `/caja` | APP + caja leer |
| `/egresos` | APP + egresos admin |
| `/stocks` | APP + stock leer |
| `/stocks/formulario` | APP + stock admin |
| `/conceptos` | APP + config leer |
| `/conceptos/formulario-concepto` | APP + config admin |
| `/metodos-pago` | APP + config leer |
| `/metodos-pago/formulario` | APP + config admin |
| `/recargos` | APP + config leer |
| `/recargos/formulario` | APP + config admin |
| `/alumnos-por-disciplina` | APP + reportes leer + disciplinas leer |
| `/subconceptos` | APP + config leer |
| `/subconceptos/formulario` | APP + config admin |

`/login` es pública y `/unauthorized` no exige permiso funcional.

## Roles demostrativos

La matriz exacta está sembrada por migración/seed. El recorrido observado confirma SUPERADMIN, DIRECCION, ADMINISTRADOR, SECRETARIA y CAJA. No codificar comportamiento por nombre de rol en frontend/backend; usar permisos.
