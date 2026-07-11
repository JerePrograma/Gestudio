# Etapa 1 — Seguridad y RBAC mínimo publicable

> - Estado: **IN_PROGRESS**
> - Única tarea activa: **E1-001**
> - Tarea siguiente: **E1-002 — BLOCKED** por **BLK-001 / DEC-RBAC-001**
> - Gate de salida: **GATE-1 — ABIERTO**
> - Baseline de código: **b833f6741cf614c508666e8a121701e8db2fcf9a**
> - Continuación documental: **088a0b33ab49c01f4f506889ac379fc4737c4119**

[Índice](./00_INDEX.md) · [Baseline y hallazgos](./01_BASELINE_Y_HALLAZGOS.md) · [Matriz RBAC](./02_MATRIZ_RBAC.md) · [Etapa 1B](./04_ETAPA_1B_LIQUIDACION_FINANCIERA.md) · [Plan de pruebas](./08_PLAN_DE_PRUEBAS.md) · [Bitácora](./09_BITACORA_IMPLEMENTACION.md) · [Decisiones y bloqueos](./10_DECISIONES_Y_BLOQUEOS.md) · [Checklist release](./11_CHECKLIST_RELEASE.md)

El commit 088a0b33 agrega únicamente documentación sobre el baseline b833f674. La inspección inicial de esta continuación confirmó main alineada con origin/main y árbol limpio; el código productivo de los hallazgos de seguridad no cambió entre ambos commits.

## Objetivo

Dejar un RBAC determinístico desde una base limpia, con catálogo y roles base aprobados, autorización backend granular, semántica 401/403/409 correcta y frontend alineado con la misma matriz. El gate debe demostrar que una URL o llamada forzada no escala privilegios, que SUPERADMIN no depende del seed demo y que Profesor queda limitado por ownership o inactivo.

## Fuera de alcance

- No aprobar ni persistir la matriz propuesta sin confirmación explícita de **DEC-RBAC-001**.
- No crear V6 mientras **E1-001** siga abierta ni reescribir V1–V5.
- No usar scripts/gestudio_demo_seed_full.sql como catálogo productivo o prerrequisito de bootstrap.
- No iniciar Etapa 1B, cambiar fórmulas financieras ni corregir la UX general de Etapa 2.
- No habilitar Profesor sin ownership backend probado con dos profesores.
- No dejar WebSocket/STOMP parcialmente protegido: debe quedar seguro o deshabilitado.
- No introducir un framework de permisos, jerarquía ordinal de roles, microservicios ni dependencias nuevas.
- No desplegar, migrar una base real ni ejecutar acciones externas.

## Dependencias y reglas de entrada

1. GATE-0 figura cerrado; esta continuación repone los documentos faltantes sin reinterpretar sus decisiones.
2. **DEC-RBAC-001** debe confirmar catálogo, matriz y transición de ADMINISTRADOR antes de V6.
3. La cadena activa observada es V1–V5. V5 queda inmutable y la siguiente migración aprobada será forward-only.
4. Docker Engine debe estar disponible para las pruebas PostgreSQL/Testcontainers y el smoke descartable.
5. **DEC-OWNERSHIP-001** debe resolverse durante E1-006; su fallback es Profesor inactivo y no bloquea el resto de la etapa.
6. **DEC-WS-001** debe resolverse antes de E1-009 y GATE-1.
7. Sólo una tarea puede estar **IN_PROGRESS** y toda transición se registra primero en la bitácora.

## Estado actual verificado

| Estado | Evidencia | Consecuencia |
|---|---|---|
| VALIDADO | V5 crea permisos, rol_permisos y usuario_roles, pero no inserta catálogo ni asignaciones. | Una base limpia no tiene PERM_APP_ACCESO. |
| VALIDADO | PostgreSqlSchemaValidationTest exige cero permisos y cero permisos para SUPERADMIN. | E1-002 debe cambiar el contrato ejecutable, no sólo SQL. |
| VALIDADO | SuperadminBootstrapService asigna el rol SUPERADMIN, pero no verifica su matriz. | Login puede funcionar mientras la API queda inutilizable. |
| VALIDADO | SecurityConfigurations deja la mayoría de /api bajo PERM_APP_ACCESO y contiene un matcher que no coincide con POST /api/mensualidades/generar-mensualidades. | Los writes no tienen autorización granular completa. |
| VALIDADO | RbacService usa OperacionNoPermitidaException y TratadorDeErrores la convierte en 409; AccessDeniedException ya tiene handler 403. | La defensa de servicio clasifica mal una denegación. |
| VALIDADO | UsuariosPagina y RolesPagina consultan USUARIOS_WRITE y ROLES_WRITE, códigos inexistentes. | Acciones legítimas pueden ocultarse aunque el usuario tenga el permiso real. |
| VALIDADO | /unauthorized exige PERM_APP_ACCESO en routePermissions. | Un autenticado sin ese permiso puede entrar en redirección circular. |
| VALIDADO | Profesor referencia Usuario, pero los servicios aceptan IDs de profesor/disciplina/asistencia sin ownership del principal. | Profesor no puede habilitarse todavía. |
| VALIDADO | /ws acepta origen *, STOMP no tiene autenticación/autorización y el hook usa ws://localhost:8080/ws; no se observaron consumidores del hook. | DEC-WS-001 sigue pendiente. |
| VALIDADO | La bitácora registra 15/15 tests RBAC frontend focalizados; no hubo cambio productivo. | E1-001 sigue siendo documental hasta recibir autoridad. |
| NO_VERIFICADO | No existen V6, smoke sin seed demo ni matriz HTTP completa. | GATE-1 permanece abierto. |

## Orden obligatorio

| Tarea | Estado | Dependencia principal | Hallazgos |
|---|---|---|---|
| E1-001 | **IN_PROGRESS** | GATE-0 | contrato completo |
| E1-002 | **BLOCKED** | BLK-001 / DEC-RBAC-001 | P0-SEC-001 a 005 |
| E1-003 | **PENDING** | E1-002 | P0-SEC-003 y 004 |
| E1-004 | **PENDING** | E1-003 | P0-SEC-009 |
| E1-005 | **PENDING** | E1-004 | P0-SEC-006 a 008 |
| E1-006 | **PENDING** | E1-005 | P0-SEC-014 |
| E1-007 | **PENDING** | E1-005 | P0-SEC-010, 011 y 013 |
| E1-008 | **PENDING** | E1-006 y E1-007 | P0-SEC-012 |
| E1-009 | **PENDING** | DEC-WS-001 y E1-005 | P0-SEC-015 |
| E1-010 | **PENDING** | E1-001 a E1-009 | gate completo |

No se adelanta código de una tarea posterior para evitar que una matriz no aprobada quede codificada por partes.

## E1-001 — Congelar contrato y constantes

- **Estado:** IN_PROGRESS; única tarea activa.
- **Dependencias:** 02_MATRIZ_RBAC.md y DEC-RBAC-001.
- **Archivos esperados:** docs/codex/gestudio-release-hardening/02_MATRIZ_RBAC.md, este documento, docs/codex/gestudio-release-hardening/10_DECISIONES_Y_BLOQUEOS.md, frontend/src/config/permissions.ts, backend/src/main/java/gestudio/infra/seguridad/SecurityConfigurations.java y los servicios que hoy declaran strings PERM_ locales. Si se aprueba, una única clase de constantes bajo backend/src/main/java/gestudio/infra/seguridad/ reemplazará la duplicación; no se crea antes.
- **Cambio esperado:** confirmar los 15 permisos actuales, los 17 códigos mínimos propuestos, la matriz SUPERADMIN/DIRECCION/SECRETARIA/CAJA/PROFESOR, la compatibilidad de ADMINISTRADOR y las reglas de delegación. Registrar aprobación o corrección exacta antes de tocar código.
- **Riesgo y rollback lógico:** tratar PROPUESTA como decisión puede otorgar privilegios. Antes de V6, el rollback es corregir documentos y constantes; no hay datos que revertir.
- **Aceptación:** respuesta explícita del usuario registrada; matriz sin ambigüedades; ningún permiso fuera de la decisión; constantes backend/frontend coincidentes y tests de contrato definidos.
- **Validación y evidencia:** inventario con rg, revisión cruzada 02/03/10 y suite RBAC frontend focalizada. La evidencia actual 15/15 no aprueba la matriz.

## E1-002 — Migración productiva RBAC

- **Estado:** BLOCKED por BLK-001 / DEC-RBAC-001.
- **Dependencias:** E1-001 DONE y versión Flyway siguiente reconfirmada.
- **Archivos esperados:** backend/src/main/resources/db/migration/V6__rbac_permission_catalog_and_base_roles.sql como archivo nuevo; V5__base_roles_permissions_seed.sql sólo como referencia inmutable; backend/src/test/java/gestudio/infra/persistencia/PostgreSqlSchemaValidationTest.java; scripts/gestudio_demo_seed_full.sql para retirar su responsabilidad sobre el catálogo, sin mezclar los demás datos demo.
- **Cambio esperado:** insertar/reconciliar el catálogo aprobado, roles base y matriz determinística; conservar roles/usuarios existentes sin renombrado o borrado automático; invalidar sesiones afectadas mediante auth_version; separar por completo el dataset demo.
- **Riesgo y rollback lógico:** una asignación excesiva escala privilegios y una reconciliación destructiva pierde configuración. La migración debe ser idempotente respecto de códigos, detectar conflictos y no sobrescribir roles personalizados. Una V6 aplicada no se edita: se corrige forward-only y, ante un despliegue fallido, se recupera desde backup aislado.
- **Aceptación:** base limpia termina en V6 con conteos exactos; upgrade V5 a V6 conserva usuarios, usuario_roles y roles ajenos; todos los permisos usados existen y están activos; SUPERADMIN recibe la matriz aprobada; el seed demo no es necesario.
- **Validación y evidencia:** PostgreSqlSchemaValidationTest debe cubrir base limpia y upgrade desde V5, consultas de conteo/reconciliación y checksum Flyway. Resultado y conteos se registran en bitácora.

## E1-003 — Bootstrap utilizable

- **Estado:** PENDING.
- **Dependencias:** E1-002.
- **Archivos esperados:** backend/src/main/java/gestudio/infra/seguridad/SuperadminBootstrapService.java, SuperadminBootstrapRunner.java, SuperadminBootstrapProperties.java, backend/src/test/java/gestudio/infra/seguridad/SuperadminBootstrapPostgreSqlTest.java y SuperadminBootstrapRunnerTest.java.
- **Cambio esperado:** reutilizar el rol sembrado por V6, verificar que esté activo y tenga el catálogo obligatorio, asignarlo al usuario bootstrap y fallar temprano con diagnóstico seguro si la matriz está incompleta. El bootstrap no se convierte en reconciliador.
- **Riesgo y rollback lógico:** un bootstrap permisivo deja un administrador inutilizable; uno reconciliador puede modificar autorización fuera de Flyway. El rollback es deshabilitar la bandera y corregir catálogo forward-only; no borrar el usuario auditado.
- **Aceptación:** migración → bootstrap → login → perfil → primer GET operativo funciona sin SQL manual ni seed demo; ejecución repetida sigue rechazada; contraseña no se expone ni persiste plana.
- **Validación y evidencia:** tests Runner y PostgreSQL, más el tramo inicial de scripts/smoke-local.ps1 sobre base descartable.

## E1-004 — Semántica de autorización

- **Estado:** PENDING.
- **Dependencias:** E1-003.
- **Archivos esperados:** backend/src/main/java/gestudio/infra/seguridad/RbacService.java, backend/src/main/java/gestudio/infra/errores/TratadorDeErrores.java, backend/src/test/java/gestudio/infra/seguridad/SecurityHttpIntegrationTest.java y tests de los servicios con defensa propia.
- **Cambio esperado:** usar AccessDeniedException de Spring para falta de autoridad en RbacService y reservar OperacionNoPermitidaException para conflictos reales. Mantener respuestas JSON sanitizadas.
- **Riesgo y rollback lógico:** convertir todos los 409 en 403 ocultaría conflictos financieros. Cambiar sólo la ruta de autorización; rollback de código sin impacto persistido.
- **Aceptación:** anónimo = 401; autenticado sin permiso = 403; conflicto de negocio = 409; los tres códigos y cuerpos quedan cubiertos por HTTP y servicio.
- **Validación y evidencia:** SecurityHttpIntegrationTest y tests focalizados de RbacService/servicios; ninguna expectativa cambia un conflicto real para forzar verde.

## E1-005 — Matchers y endpoints granulares

- **Estado:** PENDING.
- **Dependencias:** E1-004 y matriz aprobada.
- **Archivos esperados:** backend/src/main/java/gestudio/infra/seguridad/SecurityConfigurations.java; controladores reales bajo backend/src/main/java/gestudio/controladores/ y backend/src/main/java/gestudio/tarifas/api/; PagoServicio.java, EgresoServicio.java, StockServicio.java, CreditoServicio.java, UsuarioServicio.java, RolServicio.java, TarifaDisciplinaServicio.java y CondicionEconomicaServicio.java; SecurityHttpIntegrationTest.java.
- **Cambio esperado:** aplicar la matriz por método/path, corregir el matcher de POST /api/mensualidades/generar-mensualidades, conservar defensas de servicio financieras y eliminar/documentar reglas sin controlador. PERM_APP_ACCESO queda como entrada general, no como permiso suficiente para writes sensibles.
- **Riesgo y rollback lógico:** orden o patrón amplio puede abrir o bloquear rutas. Usar matchers exactos y prueba parametrizada; ante incidente, negar el endpoint afectado, nunca ampliar temporalmente el fallback.
- **Aceptación:** cada endpoint mutable tiene permiso explícito; lecturas usan el permiso de lectura aprobado; acceso directo produce 401/403/permitido según matriz; no quedan matchers huérfanos.
- **Validación y evidencia:** inventario RequestMapping contra SecurityConfigurations y matriz HTTP parametrizada en SecurityHttpIntegrationTest.

## E1-006 — Ownership Profesor

- **Estado:** PENDING.
- **Dependencias:** E1-005 y DEC-OWNERSHIP-001.
- **Archivos esperados:** backend/src/main/java/gestudio/entidades/Profesor.java, repositorios/ProfesorRepositorio.java, repositorios/DisciplinaRepositorio.java, servicios/profesor/ProfesorServicio.java, servicios/disciplina/DisciplinaServicio.java, servicios/asistencia/AsistenciaDiariaServicio.java, servicios/asistencia/AsistenciaMensualServicio.java y sus controladores/tests.
- **Cambio esperado:** resolver principal → Usuario → Profesor en backend y limitar consultas/mutaciones a disciplinas, alumnos y asistencias propios. Dirección/Secretaría mantienen alcance global sólo conforme a la matriz.
- **Riesgo y rollback lógico:** confiar profesorId del request filtra datos cruzados. La query/servicio debe derivar el profesor del principal. Si no puede probarse, no se asigna/habilita Profesor; ese fallback no bloquea el resto de GATE-1.
- **Aceptación:** dos profesores no pueden leer ni modificar recursos cruzados; un actor global autorizado sí; ausencia o duplicidad del vínculo usuario-profesor falla de modo seguro.
- **Validación y evidencia:** test PostgreSQL/HTTP con dos profesores, una disciplina por profesor y acceso propio/cruzado. Registrar la decisión y el estado final del rol.

## E1-007 — Contrato frontend

- **Estado:** PENDING.
- **Dependencias:** E1-005.
- **Archivos esperados:** frontend/src/config/permissions.ts, config/navigation.ts, rutas/routes.ts, rutas/AppRouter.tsx, rutas/ProtectedRoute.tsx, hooks/context/auth-context.ts, hooks/context/authContext.tsx, UsuariosPagina.tsx, RolesPagina.tsx y sus tests. Crear PermissionGate mínimo sólo en la ubicación común elegida al implementarlo.
- **Cambio esperado:** completar PERMISSIONS con el catálogo aprobado, tipar consumers con PermissionCode, reemplazar USUARIOS_WRITE/ROLES_WRITE, dejar /unauthorized accesible a todo autenticado y alinear menú/ruta/acción. No crear un router o framework nuevo.
- **Riesgo y rollback lógico:** una metadata divergente produce loops u oculta funciones. Migrar rutas en una tabla pequeña y conservar backend como autoridad; rollback de presentación no cambia permisos reales.
- **Aceptación:** toda ruta protegida tiene política explícita salvo la excepción autenticada /unauthorized; no quedan strings ad hoc; menú y acceso directo coinciden.
- **Validación y evidencia:** auth-context.test.ts, navigation.test.ts, ProtectedRoute.test.tsx, UsuariosPagina.test.tsx, RolesPagina.test.tsx y RolesFormulario.test.tsx verdes.

## E1-008 — Acciones sensibles frontend

- **Estado:** PENDING.
- **Dependencias:** E1-006 y E1-007.
- **Archivos esperados:** páginas/formularios de pagos, tarifas, condiciones económicas, egresos, stock, usuarios, roles, alumnos, inscripciones, disciplinas, profesores y reportes bajo frontend/src/funcionalidades/ y frontend/src/paginas/Reportes.tsx.
- **Cambio esperado:** mostrar cada alta/edición/baja/anulación/venta/exportación sólo con su permiso aprobado, reutilizando PermissionGate o hasPermission. Lectura de módulo y mutación se evalúan por separado.
- **Riesgo y rollback lógico:** ocultar acciones sin proteger API da falsa seguridad; ocultar demasiado impide operar. Cada guard frontend debe tener prueba HTTP equivalente. Rollback de UI no relaja backend.
- **Aceptación:** pagos registrar/anular, tarifas/condiciones, egresos, stock administrar/vender, seguridad, configuración, reportes/exportación y mutaciones académicas están cubiertos; una llamada forzada sigue devolviendo 403.
- **Validación y evidencia:** tests de página por permitido/denegado más matriz HTTP de E1-005; ninguna prueba se limita a ausencia visual.

## E1-009 — WebSocket y notificaciones

- **Estado:** PENDING.
- **Dependencias:** E1-005 y DEC-WS-001.
- **Archivos esperados:** backend/src/main/java/gestudio/infra/configuracion/WebSocketConfig.java, controladores/NotificacionWSController.java, servicios/notificaciones/NotificacionService.java y frontend/src/hooks/useNotificacionesWebSocket.tsx.
- **Cambio esperado:** ejecutar una sola decisión. Opción mínima recomendada pendiente de aprobación: deshabilitar/ocultar STOMP para la primera release conservando persistencia, REST y email de cumpleaños. Si se exige tiempo real: URL/protocolo por entorno, origins explícitos, autenticación de handshake, autorización por destino y aislamiento por usuario.
- **Riesgo y rollback lógico:** dejar /ws abierto expone mensajes; retirar todo puede afectar notificaciones no relacionadas. Separar transporte de persistencia/email. Un canal deshabilitado sólo se reactiva cuando sus pruebas de seguridad estén verdes.
- **Aceptación:** no existe canal anónimo/global. Si está deshabilitado, no hay endpoint ni caller activo; si está habilitado, origen, identidad, destino y aislamiento tienen pruebas.
- **Validación y evidencia:** búsqueda de callers, prueba de contexto/HTTP para opción deshabilitada o integración STOMP para opción segura; decisión registrada antes del cambio.

## E1-010 — Suite de seguridad y smoke

- **Estado:** PENDING.
- **Dependencias:** E1-001 a E1-009 terminadas y decisiones cerradas.
- **Archivos esperados:** SecurityHttpIntegrationTest.java, PostgreSqlSchemaValidationTest.java, SuperadminBootstrapPostgreSqlTest.java, UsuarioServicioTest.java, RolServicioTest.java, tests de ownership, tests frontend de auth/navegación/rutas/acciones, scripts/smoke-local.ps1 y 08_PLAN_DE_PRUEBAS.md.
- **Cambio esperado:** consolidar matriz método/path/permiso, 401/403/permitido, authVersion, usuario/rol/permiso inactivo, delegación, último SUPERADMIN, bootstrap, ownership, contrato usados/sembrados, frontend y smoke sin seed demo.
- **Riesgo y rollback lógico:** una suite parcial puede declarar seguro un único happy path. El gate exige PostgreSQL real y smoke aislado; no sustituir por H2, mocks incompletos o SQL manual.
- **Aceptación:** pruebas focalizadas y backend completo verdes; lint/build verdes; no hay regresiones frontend nuevas; los tres fallos UX baseline sólo pueden permanecer clasificados para E2-010; smoke limpio termina en cero y no carga el seed demo.
- **Validación y evidencia:** comandos, conteos, duración, fallos clasificados y resultado de limpieza en bitácora.

## Estrategia mínima de implementación

1. Aprobar primero el contrato; ninguna autoridad se infiere de etiquetas o roles ordinales.
2. Crear una única V6 forward-only; no tocar V5 ni duplicar catálogo en bootstrap/demo.
3. Reutilizar AccessDeniedException, SecurityConfigurations, RbacService y PermissionCode antes de crear tipos nuevos.
4. Proteger backend por método/path y conservar defensa de servicio sólo donde ya existe una frontera sensible.
5. Implementar ownership en query/servicio usando el principal, nunca un ID del cliente.
6. Migrar frontend en el orden permiso → ruta → navegación → acción, con una prueba por contrato.
7. Elegir deshabilitar o asegurar WebSocket; no sostener dos modos incompletos.
8. Ejecutar test focalizado por tarea y suite amplia sólo cuando la tarea quede verde.

## Validaciones PowerShell exactas

### Migración, bootstrap y seguridad backend

    Push-Location .\backend
    try {
        .\mvnw.cmd "-Dtest=PostgreSqlSchemaValidationTest" test
        .\mvnw.cmd "-Dtest=SuperadminBootstrapPostgreSqlTest,SuperadminBootstrapRunnerTest" test
        .\mvnw.cmd "-Dtest=SecurityHttpIntegrationTest,UsuarioServicioTest,RolServicioTest" test
    }
    finally {
        Pop-Location
    }

Las clases nuevas de ownership o WebSocket deben agregarse al comando focalizado cuando existan; no se registran como ejecutadas antes de crearlas.

### Contrato frontend

    Push-Location .\frontend
    try {
        npm test -- src/hooks/context/auth-context.test.ts src/config/navigation.test.ts src/rutas/ProtectedRoute.test.tsx src/funcionalidades/usuarios/UsuariosPagina.test.tsx src/funcionalidades/roles/RolesPagina.test.tsx src/funcionalidades/roles/RolesFormulario.test.tsx
        npm run lint
        npm run build
    }
    finally {
        Pop-Location
    }

### Cierre de etapa

    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
    git diff --check
    git status --short --branch

El smoke debe crear su stack aislado, migrar desde vacío, ejecutar bootstrap y operar sin scripts/gestudio_demo_seed_full.sql. No usar localhost:5432 ni conservar el stack salvo diagnóstico explícito.

## GATE-1 — checklist accionable

**Estado actual: ABIERTO / BLOCKED por BLK-001.**

- [ ] DEC-RBAC-001 aprobada o corregida explícitamente; E1-001 cerrada en bitácora.
- [ ] V6 forward-only aplica desde vacío y actualiza desde V5 sin pérdida ni reescritura.
- [ ] Catálogo, roles base y asignaciones coinciden exactamente con 02_MATRIZ_RBAC.md.
- [ ] Todos los permisos usados existen, están activos y no dependen del seed demo.
- [ ] Bootstrap crea un SUPERADMIN utilizable; login, perfil y primer GET pasan.
- [ ] Sin token = 401; token válido sin permiso = 403; conflicto real = 409.
- [ ] Cada write sensible tiene permiso backend explícito; PERM_APP_ACCESO no basta.
- [ ] Usuario, rol o permiso inactivo y authVersion inválida niegan acceso efectivo.
- [ ] Delegación no escala privilegios y no puede perderse el último SUPERADMIN.
- [ ] Profesor tiene ownership probado con dos profesores o permanece inactivo.
- [ ] Menú, ruta y acción usan la misma matriz; /unauthorized no entra en loop.
- [ ] Usuarios/Roles usan PERM_USUARIOS_ADMIN y PERM_ROLES_ADMIN.
- [ ] Acceso directo a URL/API no evita controles.
- [ ] WebSocket está autenticado/autorizado/aislado o completamente deshabilitado.
- [ ] Matriz HTTP, contrato frontend y smoke sin seed demo están verdes.
- [ ] Backend finaliza PASS; Frontend y All quedan ejecutados y clasificados sin regresiones nuevas.
- [ ] 00_INDEX.md, 08_PLAN_DE_PRUEBAS.md, 09_BITACORA_IMPLEMENTACION.md, 10_DECISIONES_Y_BLOQUEOS.md y 11_CHECKLIST_RELEASE.md reflejan la evidencia.

GATE-1 sólo se cierra cuando cada casilla tiene comando, fecha y resultado en la bitácora. Al cerrarlo, detenerse y pedir exactamente: **¿Autorizás continuar con Etapa 1B — liquidación financiera por vigencia?** No iniciar E1B por cuenta propia.
