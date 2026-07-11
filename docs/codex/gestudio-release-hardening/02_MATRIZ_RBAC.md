# Matriz RBAC

Estado: `PROPUESTA` / `E1-001 IN_PROGRESS`. Esta matriz describe el código observado y la opción mínima recomendada, pero no autoriza cambios. [DEC-RBAC-001](./10_DECISIONES_Y_BLOQUEOS.md#dec-rbac-001--matriz-base-de-roles-y-permisos) sigue `PENDING` y [BLK-001](./10_DECISIONES_Y_BLOQUEOS.md#blk-001--falta-de-autoridad-para-la-matriz-rbac) impide iniciar `E1-002`.

Baseline de código: `b833f6741cf614c508666e8a121701e8db2fcf9a`. Continuación documental: `088a0b33ab49c01f4f506889ac379fc4737c4119`; ese commit no modifica código productivo. Referencias: [baseline](./01_BASELINE_Y_HALLAZGOS.md), [Etapa 1](./03_ETAPA_1_SEGURIDAD_RBAC.md), [plan de pruebas](./08_PLAN_DE_PRUEBAS.md), [bitácora](./09_BITACORA_IMPLEMENTACION.md) y [checklist de release](./11_CHECKLIST_RELEASE.md).

## Leyenda y contrato general

- `ACTUAL`: el código existe y se usa en el `HEAD` auditado.
- `PROPUESTA`: todavía no existe en código ni Flyway; requiere aprobación.
- `PROPIO`: sólo recursos derivados en backend desde el usuario autenticado; nunca desde un ID confiado al cliente.
- `✓`: asignación recomendada, todavía no aprobada.
- `?`: punto que el usuario debe confirmar dentro de `DEC-RBAC-001`.
- `—`: el rol no recibe ese permiso.
- Toda ruta operativa exige además `PERM_APP_ACCESO`; ese permiso abre la aplicación, pero no sustituye lectura, escritura ni ownership.
- Sin token = 401; token válido sin autoridad = 403; conflicto real de negocio = 409.
- Menú y guards frontend son presentación. El matcher/controller y, cuando corresponde, el servicio son la autoridad.

Clasificación: `VALIDADO` para los 15 códigos, matchers, rutas, servicios y seeds observados; `INFERIDO` para el alcance de Profesor hasta probar ownership; `NO_VERIFICADO` para V6, roles base y matriz HTTP futura; `RIESGOSO` para el fallback actual y el canal STOMP incompleto; `RECOMENDADO` para la distribución mínima siguiente; `PROPUESTA` hasta que el usuario confirme `DEC-RBAC-001`.

## Catálogo actual real

V5 crea las tablas RBAC, pero el seed productivo contiene **cero permisos y cero asignaciones**. El seed demo inserta 14 de los 15 códigos actuales y omite `PERM_TARIFAS_HISTORICAS`; por lo tanto no es una fuente válida del catálogo.

| Código actual | Módulo / uso observado | Backend | Frontend | Seed productivo | Seed demo | Estado |
|---|---|---|---|---|---|---|
| `PERM_APP_ACCESO` | entrada general a `/api/**` | matcher fallback | rutas/módulos generales | No | Sí | `ACTUAL`, insuficiente solo |
| `PERM_USUARIOS_ADMIN` | CRUD de usuarios | matcher + servicio | menú/ruta; acción usa código erróneo | No | Sí | `ACTUAL` |
| `PERM_ROLES_ADMIN` | roles y lectura de permisos | matcher + servicio | menú/ruta; acción usa código erróneo | No | Sí | `ACTUAL` |
| `PERM_AUDITORIA_SEGURIDAD_LEER` | auditoría de seguridad | matcher | constante sin ruta visible auditada | No | Sí | `ACTUAL` |
| `PERM_MENSUALIDADES_GENERAR_MANUAL` | generación manual | matcher con path incorrecto | constante | No | Sí | `ACTUAL`, matcher roto |
| `PERM_PAGOS_REGISTRAR` | pago y cargo por concepto | servicio | ruta Cobranza/formulario | No | Sí | `ACTUAL` |
| `PERM_PAGOS_ANULAR` | anulación de pago | servicio | constante; acción sin guard | No | Sí | `ACTUAL` |
| `PERM_EGRESOS_ADMIN` | alta/anulación de egresos | servicio | menú/ruta completa | No | Sí | `ACTUAL` |
| `PERM_STOCK_ADMIN` | CRUD/reversión de stock | servicio | ruta formulario | No | Sí | `ACTUAL` |
| `PERM_STOCK_VENDER` | venta de stock | servicio | constante; flujo no expuesto completo | No | Sí | `ACTUAL` |
| `PERM_CREDITOS_ADMIN` | ajuste/reversión de crédito | servicio | constante | No | Sí | `ACTUAL` |
| `PERM_CREDITOS_CONSUMIR` | consumir crédito | servicio | constante | No | Sí | `ACTUAL` |
| `PERM_TARIFAS_ADMIN` | crear tarifas y alternativa para condiciones | servicio | ruta de tarifas | No | Sí | `ACTUAL` |
| `PERM_TARIFAS_HISTORICAS` | programar vigencias pasadas | servicio | constante | No | **No** | `ACTUAL`, no sembrado en demo |
| `PERM_CONDICIONES_ECONOMICAS_ADMIN` | condiciones de inscripción | servicio | ruta de condiciones | No | Sí | `ACTUAL` |

Conteo: 15 códigos actuales; 0 sembrados por Flyway; 14 presentes sólo en el seed demo.

## Catálogo mínimo propuesto

Estos son los **17 códigos exactos** propuestos por el megaprompt. No se agregan permisos específicos para Matrículas, Cargos, Observaciones o Notificaciones sin una decisión adicional; la matriz de endpoints reutiliza códigos existentes donde el significado es suficiente y deja fuera la función cuando no lo es.

| Código propuesto | Alcance mínimo | Razón |
|---|---|---|
| `PERM_ALUMNOS_LEER` | listar, buscar y ver alumnos | separar lectura de mutación y servir búsquedas humanas |
| `PERM_ALUMNOS_ADMIN` | alta, edición, baja y reactivación | proteger datos personales y estados |
| `PERM_INSCRIPCIONES_LEER` | consultas de inscripciones/matrículas | lectura académica contextual |
| `PERM_INSCRIPCIONES_ADMIN` | alta, edición, finalización y generación de matrícula | operación académica mutable |
| `PERM_DISCIPLINAS_LEER` | disciplinas, horarios y relaciones visibles | catálogo académico de lectura |
| `PERM_DISCIPLINAS_ADMIN` | alta, edición y baja | configuración académica mutable |
| `PERM_PROFESORES_LEER` | ver/buscar profesores | lectura separada del mantenimiento |
| `PERM_PROFESORES_ADMIN` | alta, edición y baja | mantenimiento de profesores |
| `PERM_ASISTENCIAS_LEER` | diario/mensual e historia | consulta académica |
| `PERM_ASISTENCIAS_REGISTRAR` | registrar, corregir o retirar asistencia | mutación con ownership |
| `PERM_PAGOS_LEER` | pagos, cargos, recibos, mensualidades y matrículas | lectura financiera operativa |
| `PERM_CAJA_LEER` | resumen y movimientos de caja | visibilidad financiera separada de egresos |
| `PERM_STOCK_LEER` | inventario e historial visible | lectura separada de administrar/vender |
| `PERM_REPORTES_LEER` | consultar reportes | acceso al hub y resultados |
| `PERM_REPORTES_EXPORTAR` | descargar/exportar | extracción de datos más sensible que lectura |
| `PERM_CONFIG_LEER` | métodos, conceptos, subconceptos, salones, bonificaciones y recargos | catálogos necesarios para operar |
| `PERM_CONFIG_ADMIN` | alta, edición y baja lógica de esos catálogos | configuración mutable agrupada sin permisos especulativos |

Conteo propuesto: 17. Catálogo objetivo si se aprueba: 15 actuales + 17 nuevos = **32 códigos únicos**.

## Matriz propuesta de roles base

Las marcas son una recomendación pendiente. Los `?` deben resolverse expresamente antes de V6.

| Permiso | SUPERADMIN | DIRECCION | SECRETARIA | CAJA | PROFESOR |
|---|---:|---:|---:|---:|---:|
| `PERM_APP_ACCESO` | ✓ | ✓ | ✓ | ✓ | ✓ |
| `PERM_USUARIOS_ADMIN` | ✓ | ? | — | — | — |
| `PERM_ROLES_ADMIN` | ✓ | — | — | — | — |
| `PERM_AUDITORIA_SEGURIDAD_LEER` | ✓ | ? | — | — | — |
| `PERM_MENSUALIDADES_GENERAR_MANUAL` | ✓ | ✓ | — | — | — |
| `PERM_PAGOS_REGISTRAR` | ✓ | ✓ | ✓ | ✓ | — |
| `PERM_PAGOS_ANULAR` | ✓ | ✓ | — | — | — |
| `PERM_EGRESOS_ADMIN` | ✓ | ✓ | ? | ? | — |
| `PERM_STOCK_ADMIN` | ✓ | ✓ | — | — | — |
| `PERM_STOCK_VENDER` | ✓ | ✓ | ? | ? | — |
| `PERM_CREDITOS_ADMIN` | ✓ | ✓ | — | — | — |
| `PERM_CREDITOS_CONSUMIR` | ✓ | ✓ | ✓ | ✓ | — |
| `PERM_TARIFAS_ADMIN` | ✓ | ✓ | — | — | — |
| `PERM_TARIFAS_HISTORICAS` | ✓ | ✓ | — | — | — |
| `PERM_CONDICIONES_ECONOMICAS_ADMIN` | ✓ | ✓ | ✓ | — | — |
| `PERM_ALUMNOS_LEER` | ✓ | ✓ | ✓ | ✓ | `PROPIO` |
| `PERM_ALUMNOS_ADMIN` | ✓ | ✓ | ✓ | — | — |
| `PERM_INSCRIPCIONES_LEER` | ✓ | ✓ | ✓ | — | — |
| `PERM_INSCRIPCIONES_ADMIN` | ✓ | ✓ | ✓ | — | — |
| `PERM_DISCIPLINAS_LEER` | ✓ | ✓ | ✓ | — | `PROPIO` |
| `PERM_DISCIPLINAS_ADMIN` | ✓ | ✓ | — | — | — |
| `PERM_PROFESORES_LEER` | ✓ | ✓ | ✓ | — | `PROPIO` |
| `PERM_PROFESORES_ADMIN` | ✓ | ✓ | — | — | — |
| `PERM_ASISTENCIAS_LEER` | ✓ | ✓ | ✓ | — | `PROPIO` |
| `PERM_ASISTENCIAS_REGISTRAR` | ✓ | ✓ | ✓ | — | `PROPIO` |
| `PERM_PAGOS_LEER` | ✓ | ✓ | ✓ | ✓ | — |
| `PERM_CAJA_LEER` | ✓ | ✓ | ✓ | ✓ | — |
| `PERM_STOCK_LEER` | ✓ | ✓ | ✓ | ✓ | — |
| `PERM_REPORTES_LEER` | ✓ | ✓ | ✓ | — | — |
| `PERM_REPORTES_EXPORTAR` | ✓ | ✓ | — | — | — |
| `PERM_CONFIG_LEER` | ✓ | ✓ | ✓ | ✓ | — |
| `PERM_CONFIG_ADMIN` | ✓ | ✓ | — | — | — |

### Propósito de cada rol

- `SUPERADMIN`: recuperación y administración técnica completa; no es cuenta diaria.
- `DIRECCION`: negocio, configuración, reportes y operaciones financieras sensibles. Usuarios/auditoría requieren confirmación; roles permanecen reservados a SUPERADMIN en la propuesta.
- `SECRETARIA`: alumnos, inscripciones, condiciones económicas, asistencia, lectura/registro de pagos y caja. No anula pagos ni administra seguridad. Egresos y venta de stock requieren confirmación.
- `CAJA`: lectura de alumnos/pagos/caja/stock/configuración, registro de pagos y consumo de crédito. Egresos y venta de stock requieren confirmación.
- `PROFESOR`: sólo lectura/registro académico `PROPIO`. Permanece inactivo hasta cerrar `DEC-OWNERSHIP-001` con pruebas de acceso cruzado.
- `ADMINISTRADOR`: rol legacy observado; no se borra, renombra ni convierte automáticamente. Su equivalencia/asignaciones se resuelven dentro de `DEC-RBAC-001` y la migración debe preservar datos existentes.

## Matriz módulo, ruta, endpoint y control

`Existe/seed`: `A` = código actual, `P` = propuesto; todos tienen seed productivo actual `No`. `FE / BE actual` describe lo que hoy exige el frontend y backend, no la solución deseada.

| Módulo / ruta y acción visible | Método y endpoint backend | Permiso esperado | Permiso actual | Existe/seed | FE / BE actual | Ownership | Estado y cambio | Prueba mínima |
|---|---|---|---|---|---|---|---|---|
| Login `/login` | `POST /api/login`, `/refresh`, `/logout` | público con controles de origen/cookie | público | n/a | público / `permitAll` | sesión propia | conservar; access/refresh no intercambiables | inválido 401; refresh/origen; permitido 200 |
| Perfil autenticado | `GET /api/usuarios/perfil` | autenticado | autenticado | n/a | guard auth / `authenticated` | usuario actual | conservar sin exigir APP | anónimo 401; autenticado 200 |
| Error de autorización `/unauthorized` | sin endpoint propio | cualquier autenticado; sin permiso funcional | `PERM_APP_ACCESO` en `routePermissions` | n/a | redirige al faltar permiso y vuelve a exigir APP / n/a | sesión actual | retirar sólo este permiso de ruta para evitar loop | autenticado sin APP ve la página una vez |
| Dashboard `/` | endpoints de señales según módulo | permisos de cada señal | `PERM_APP_ACCESO` | A/No | ruta APP / fallback APP | según señal | no crear endpoint que agregue datos no autorizados | cada rol ve sólo señales permitidas |
| Alumnos `/alumnos`: listar/buscar/ver | `GET /api/alumnos/**` | `PERM_ALUMNOS_LEER` | `PERM_APP_ACCESO` | P/No | ruta APP / fallback APP | global; Profesor `PROPIO` | matcher GET + filtro Profesor | 401/403/200 y dos profesores |
| Alumnos: alta/editar/baja/reactivar | `POST`, `PUT`, `DELETE /api/alumnos/**` | `PERM_ALUMNOS_ADMIN` | `PERM_APP_ACCESO` | P/No | acciones sin guard / fallback APP | global | matcher por método; reactivación explícita | 401/403/status funcional |
| Inscripciones `/inscripciones`: consultar | `GET /api/inscripciones/**` | `PERM_INSCRIPCIONES_LEER` | `PERM_APP_ACCESO` | P/No | ruta APP / fallback APP | global | matcher GET | 401/403/200 |
| Inscripciones: alta/editar/finalizar | `POST`, `PUT`, `DELETE /api/inscripciones/**` | `PERM_INSCRIPCIONES_ADMIN` | `PERM_APP_ACCESO` | P/No | acciones sin guard / fallback APP | global | matcher por método; frontend respeta invariantes | 401/403/permitido |
| Disciplinas `/disciplinas`: consultar, horarios, alumnos/PDF | `GET /api/disciplinas/**` | `PERM_DISCIPLINAS_LEER`; PDF además `PERM_REPORTES_EXPORTAR` | `PERM_APP_ACCESO` | P/No | ruta APP / fallback APP | global; Profesor `PROPIO` | separar lectura/exportación y ownership | 401/403/200; propio/cruzado |
| Disciplinas: alta/editar/baja | `POST`, `PUT`, `DELETE /api/disciplinas/**` | `PERM_DISCIPLINAS_ADMIN` | `PERM_APP_ACCESO` | P/No | acciones sin guard / fallback APP | global | matcher por método | 401/403/permitido |
| Profesores `/profesores`: listar/buscar/ver | `GET /api/profesores/**` | `PERM_PROFESORES_LEER` | `PERM_APP_ACCESO` | P/No | ruta APP / fallback APP | global; Profesor `PROPIO` | derivar propio desde principal | 401/403/200; propio/cruzado |
| Profesores: alta/editar/baja | `POST`, `PUT`, `DELETE /api/profesores/**` | `PERM_PROFESORES_ADMIN` | `PERM_APP_ACCESO` | P/No | acciones sin guard / fallback APP | global | matcher por método | 401/403/permitido |
| Asistencias diario/mensual: consultar | `GET /api/asistencias-diarias/**`, `/api/asistencias-mensuales/**` | `PERM_ASISTENCIAS_LEER` | `PERM_APP_ACCESO` | P/No | rutas APP / fallback APP | Profesor `PROPIO` | matcher GET + query ownership | 401/403/200; propio/cruzado |
| Asistencias: registrar/corregir/eliminar/generar | `PUT`/`DELETE /api/asistencias-diarias/**`; `POST`/`PUT /api/asistencias-mensuales/**` | `PERM_ASISTENCIAS_REGISTRAR` | `PERM_APP_ACCESO` | P/No | acciones sin guard / fallback APP | Profesor `PROPIO` | matcher + servicio/query ownership | 401/403/permitido; cruzado 403 |
| Mensualidades: consultar | `GET /api/mensualidades/**` | `PERM_PAGOS_LEER` | `PERM_APP_ACCESO` | P/No | sin ruta exclusiva / fallback APP | global | matcher GET | 401/403/200 |
| Mensualidades: crear/generar manual | `POST /api/mensualidades`; `POST /api/mensualidades/generar-mensualidades` | `PERM_MENSUALIDADES_GENERAR_MANUAL` | APP; matcher apunta a path inexistente | A/No | sin guard de acción / matcher roto | global | corregir path y cubrir ambos casos conforme decisión | 401/403/permitido |
| Mensualidades: anular/eliminar | `DELETE /api/mensualidades/{id}` | `PERM_PAGOS_ANULAR` | `PERM_APP_ACCESO` | A/No | sin guard / fallback APP | global | tratar como reversión; confirmar dentro de `DEC-RBAC-001` | 401/403/409/permitido |
| Matrículas: consultar | `GET /api/matriculas/alumno/{id}` | `PERM_PAGOS_LEER` | `PERM_APP_ACCESO` | P/No | consumo interno / fallback APP | global | matcher GET | 401/403/200 |
| Matrículas: generar/anular | `POST /api/matriculas/alumno/{id}`; `POST /api/matriculas/{id}/anulacion` | generar `PERM_INSCRIPCIONES_ADMIN`; anular `PERM_PAGOS_ANULAR` | `PERM_APP_ACCESO` | P+A/No | sin guards / fallback APP | global | confirmar reutilización; no inventar códigos | 401/403/409/permitido |
| Cargos: consultar pendientes/vencidos | `GET /api/cargos/**` | `PERM_PAGOS_LEER` | `PERM_APP_ACCESO` | P/No | Pagos usa datos / fallback APP | global | matcher GET | 401/403/200 |
| Cargos: crear por concepto | `POST /api/cargos/concepto` | `PERM_PAGOS_REGISTRAR` | APP + defensa de servicio | A/No | formulario/ruta parcial / servicio exige permiso | global | agregar matcher; conservar servicio | 401/403/201; conflicto 409 |
| Pagos `/pagos`: listar/ver/recibo | `GET /api/pagos/**` | `PERM_PAGOS_LEER`; descarga de recibo incluida | `PERM_APP_ACCESO` | P/No | ruta APP / fallback APP | global | matcher GET | 401/403/200 |
| Cobranza `/pagos/formulario`: registrar | `POST /api/pagos` | `PERM_PAGOS_REGISTRAR` | APP + defensa de servicio | A/No | ruta/menu sí / fallback + servicio | global | matcher explícito; conservar servicio | 401/403/201; idempotencia 409 |
| Pagos: Anular | `POST /api/pagos/{id}/anulacion` | `PERM_PAGOS_ANULAR` | APP + defensa de servicio | A/No | acción sin permiso / fallback + servicio | global | guard acción + matcher + servicio | 401/403/200; conflicto 409 |
| Caja `/caja`: resumen | `GET /api/caja/resumen` | `PERM_CAJA_LEER` | `PERM_APP_ACCESO` | P/No | ruta APP / fallback APP | global | matcher GET | 401/403/200 |
| Egresos `/egresos`: listar/ver | `GET /api/egresos/**` | `PERM_EGRESOS_ADMIN` hasta decidir lectura separada | APP en backend | A/No | menú/ruta EGRESOS / fallback APP | global | alinear backend; no crear `EGRESOS_LEER` ahora | 401/403/200 |
| Egresos: registrar/anular | `POST /api/egresos`; `POST /api/egresos/{id}/anulacion` | `PERM_EGRESOS_ADMIN` | APP + defensa de servicio | A/No | ruta sí / fallback + servicio | global | matcher explícito; conservar idempotencia | 401/403/200; retry/conflicto |
| Stock `/stocks`: listar/ver | `GET /api/stocks/**` | `PERM_STOCK_LEER` | `PERM_APP_ACCESO` | P/No | ruta APP / fallback APP | global | matcher GET | 401/403/200 |
| Stock: crear/editar/baja/revertir | `POST`, `PUT`, `DELETE /api/stocks/**`; reversion de venta | `PERM_STOCK_ADMIN` | APP + defensa parcial de servicio | A/No | formulario STOCK_ADMIN, acciones sin guard / fallback + servicio | global | matchers exactos y guards | 401/403/permitido |
| Stock: vender | `POST /api/stocks/ventas` | `PERM_STOCK_VENDER` | APP + defensa de servicio | A/No | sin flujo completo / fallback + servicio | global | matcher y flujo sólo si alcance aprobado | 401/403/200; idempotencia |
| Créditos: saldo | `GET /api/creditos/alumno/{id}/saldo` | `PERM_PAGOS_LEER` | `PERM_APP_ACCESO` | P/No | sin ruta visible / fallback APP | global | matcher GET | 401/403/200 |
| Créditos: consumir | `POST /api/creditos/consumos` | `PERM_CREDITOS_CONSUMIR` | APP + servicio | A/No | sin guard visible / fallback + servicio | global | matcher + servicio | 401/403/permitido |
| Créditos: ajustar/revertir | `POST /api/creditos/ajustes`, `/consumos/{id}/reversion` | `PERM_CREDITOS_ADMIN` | APP + servicio | A/No | sin guard visible / fallback + servicio | global | matcher + servicio | 401/403/permitido |
| Tarifas `/disciplinas/:id/tarifas`: leer | `GET /api/disciplinas/{id}/tarifas` | `PERM_TARIFAS_ADMIN`; histórico pasado además `PERM_TARIFAS_HISTORICAS` según servicio | APP + servicio ad hoc | A/No | ruta TARIFAS_ADMIN / fallback + servicio | global | matcher y semántica 403 | 401/403/200 |
| Tarifas: crear/programar | `POST /api/disciplinas/{id}/tarifas` | `PERM_TARIFAS_ADMIN`; pasado requiere `PERM_TARIFAS_HISTORICAS` | APP + servicio ad hoc | A/No | ruta sí / fallback + servicio | global | matcher; AccessDenied, no 409 | 401/403/201; conflicto 409 |
| Condiciones `/inscripciones/:id/condiciones-economicas` | `GET`, `POST /api/inscripciones/{id}/condiciones-economicas` | `PERM_CONDICIONES_ECONOMICAS_ADMIN` o TARIFAS según contrato actual; histórico requiere `PERM_TARIFAS_HISTORICAS` | APP + servicio ad hoc | A/No | ruta CONDICIONES / fallback + servicio | global | matcher; alinear alternativa aprobada | 401/403/200-201 |
| Reportes `/reportes`, `/alumnos-por-disciplina`: consultar | `GET /api/reportes/mensualidades`; GET/PDF de disciplinas | `PERM_REPORTES_LEER` | `PERM_APP_ACCESO` | P/No | rutas APP / fallback APP | global; datos internos filtrados | matcher y navegación única | 401/403/200 |
| Reportes: exportar | `POST /api/reportes/mensualidades/exportar`; PDFs | `PERM_REPORTES_EXPORTAR` | `PERM_APP_ACCESO` | P/No | acciones sin guard / fallback APP | global | matcher + guard; contenido humano | 401/403/200 |
| Usuarios `/usuarios`: toda administración | `/api/usuarios/**`, salvo perfil | `PERM_USUARIOS_ADMIN` | mismo | A/No | ruta correcta, acciones usan `USUARIOS_WRITE` / matcher + servicio | global | usar constante real; probar positivo/negativo | 401/403/permitido |
| Roles `/roles` y permisos | `/api/roles/**`, `GET /api/permisos` | `PERM_ROLES_ADMIN` | mismo | A/No | ruta correcta, acciones usan `ROLES_WRITE` / matcher + servicio | delegación | usar constante; anti-escalamiento | 401/403/permitido |
| Auditoría de seguridad | matcher `/api/auditoria/seguridad/**`; no se observó controller | `PERM_AUDITORIA_SEGURIDAD_LEER` si se publica | mismo | A/No | sin ruta visible / matcher huérfano | global autorizado | eliminar o documentar/implementar según alcance; no simular cobertura con 404 | controller real: 401/403/200; si no existe, cero matcher huérfano |
| Configuración `/metodos-pago`, `/conceptos`, `/subconceptos`, `/salones`, `/bonificaciones`, `/recargos`: consultar | `GET /api/metodos-pago/**`, `/api/conceptos/**`, `/api/sub-conceptos/**`, `/api/salones/**`, `/api/bonificaciones/**`, `/api/recargos/**` | `PERM_CONFIG_LEER` | `PERM_APP_ACCESO` | P/No | rutas APP / fallback APP | global | matchers GET sobre cada path real | 401/403/200 |
| Configuración: altas/ediciones/bajas desde sus formularios | `POST`, `PUT`, `DELETE` sobre `/api/metodos-pago/**`, `/api/conceptos/**`, `/api/sub-conceptos/**`, `/api/salones/**`, `/api/bonificaciones/**`, `/api/recargos/**` | `PERM_CONFIG_ADMIN` | `PERM_APP_ACCESO` | P/No | rutas/acciones APP; Concepto form usa PAGOS_REGISTRAR / fallback APP | global | matcher por método + guards; baja lógica cuando aplique | 401/403/permitido |
| Notificaciones REST: cumpleaños | `GET /api/notificaciones/cumpleaneros` | `PERM_ALUMNOS_LEER` | `PERM_APP_ACCESO` | P/No | modal REST / fallback APP | datos según alcance | reutilizar lectura de alumnos | 401/403/200 |
| Observaciones de profesores | `/api/observaciones-profesores/**` | sin código aprobado; fuera de release | `PERM_APP_ACCESO` | n/a | sin ruta productiva / fallback APP | pendiente propio/global | negar/ocultar hasta `DEC-OBS-001`; no inventar permiso | 401/403 y cero superficie activa |
| WebSocket/STOMP `/ws` | handshake, `/topic`, `/queue` | deshabilitado o contrato completo según `DEC-WS-001` | origen `*`, sin autorización STOMP; HTTP termina en deny | n/a | hook sin callers / canal incompleto | por usuario si se habilita | resolver `E1-009`; no estado intermedio | handshake anónimo negado; aislamiento |

## Reglas de delegación y escalamiento

1. No existe jerarquía ordinal implícita: un rol sólo concede permisos activos asignados explícitamente.
2. `SUPERADMIN` es rol de sistema, no delegable por un rol ordinario y no puede quedar sin al menos un usuario activo utilizable.
3. `PERM_ROLES_ADMIN` no permite otorgar un permiso que el actor no posee ni modificar un rol de sistema fuera de la regla aprobada.
4. `PERM_USUARIOS_ADMIN` no permite asignar roles/permisos superiores al conjunto delegable del actor.
5. Crear, clonar, modificar o desactivar roles; cambiar permisos; asignar roles; activar/desactivar usuarios o cambiar contraseña incrementa `authVersion` de los usuarios afectados conforme al diseño existente.
6. Rol o permiso inactivo no produce authority; usuario inactivo no conserva acceso por un JWT estructuralmente válido.
7. Los códigos técnicos de roles/permisos son inmutables. Cambiar nombres humanos no cambia el contrato.
8. `PROFESOR` nunca recibe acceso global por conveniencia: `PROPIO` debe derivarse en backend/query y probarse con dos profesores.
9. La UI sólo muestra capacidades; una URL, request o ID manipulados siguen siendo rechazados por backend.
10. Toda denegación de autoridad registra un evento mínimo sin secretos ni payload personal completo y responde 403, no 409.

## Diferencias de catálogo y cobertura

### Usados pero no sembrados productivamente

- Los 15 permisos actuales: Flyway V5 crea estructura y siembra cero filas.
- Especialmente `PERM_APP_ACCESO`: su ausencia vuelve inutilizable el primer GET operativo de una base limpia.
- `PERM_TARIFAS_HISTORICAS`: además falta en `scripts/gestudio_demo_seed_full.sql`.
- Los 17 propuestos todavía no existen ni se usan; se agregan sólo después de aprobar `DEC-RBAC-001`.

### Sembrados pero no usados

- Productivo: ninguno, porque no hay seed.
- Seed demo: no se identificó un código huérfano; el problema es que ese script no es productivo, está incompleto y mezcla configuración obligatoria con datos demo.

### Endpoints sin permiso granular actual

Quedan sólo bajo `PERM_APP_ACCESO` las familias de Alumnos, Inscripciones, Disciplinas, Profesores, Asistencias, Mensualidades, Matrículas, Cargos, Caja, Reportes, Notificaciones, Observaciones y catálogos de configuración. Pagos, Egresos, Stock, Crédito y Tarifas/Condiciones conservan defensas parciales de servicio, pero sus matchers HTTP siguen cayendo en el fallback. El matcher de generación manual de mensualidades no coincide con ningún endpoint real.

Usuarios y Roles/Permisos son las únicas familias reales separadas por matcher de módulo. Auditoría tiene un matcher específico, pero no se observó controller; debe retirarse o respaldarse con un endpoint y prueba reales. Aun en Usuarios/Roles faltan las correcciones frontend y las pruebas completas de delegación.

## Contrato automatizado requerido

Antes de cerrar GATE-1 debe existir una prueba que compare:

- constantes backend efectivamente usadas;
- catálogo y asignaciones de la migración aprobada;
- `frontend/src/config/permissions.ts`;
- rutas, navegación y acciones;
- tabla parametrizada método/path/permiso en HTTP.

Cada fila operativa prueba 401, 403 y permitido; los writes agregan conflicto 409 cuando exista una invariante. La prueba debe montar el controller real: un 404 no cuenta como permitido. Profesor agrega propio/cruzado; WebSocket agrega handshake/origen/destino o demuestra que el canal no existe.

## Condición para cerrar E1-001

El usuario debe aprobar o corregir explícitamente:

1. los 15 códigos actuales y 17 propuestos;
2. los `?` de la matriz de roles;
3. la transición de `ADMINISTRADOR`;
4. la reutilización de permisos para Mensualidades, Matrículas y Cargos;
5. el fallback `PROFESOR` inactivo hasta probar ownership;
6. la decisión separada de WebSocket.

Después se actualiza primero este documento y [10_DECISIONES_Y_BLOQUEOS.md](./10_DECISIONES_Y_BLOQUEOS.md), se registra la respuesta en la bitácora, se cierra `E1-001` y recién entonces `E1-002` pasa a ser la única tarea `IN_PROGRESS`. Mientras eso no ocurra, no se crea V6 ni se modifica autoridad persistida.
