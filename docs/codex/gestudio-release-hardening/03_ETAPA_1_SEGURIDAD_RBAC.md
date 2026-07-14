# Etapa 1 — Seguridad y RBAC mínimo publicable

> - Estado: **DONE_LOCAL / WAITING_REMOTE**
> - Contrato: **E1-001 DONE**; `DEC-RBAC-001` tomada el 2026-07-14
> - Implementación: **E1-002/003/004/005/007/008/009/010 DONE**; **E1-006 DEFERRED SAFE**
> - Gate de salida: **GATE-1 LOCAL CERRADO / INTEGRACIÓN REMOTA PENDIENTE**
> - Baseline de rama: **f6493a3b1b7988a626c0742fe88ce75c2f1c4ee5**
> - `origin/main` al inicio: **644e044b26438516ea093513ca5651ce72fb3fb3**

[Índice](./00_INDEX.md) · [Baseline y hallazgos](./01_BASELINE_Y_HALLAZGOS.md) · [Matriz RBAC](./02_MATRIZ_RBAC.md) · [Etapa 1B](./04_ETAPA_1B_LIQUIDACION_FINANCIERA.md) · [Plan de pruebas](./08_PLAN_DE_PRUEBAS.md) · [Bitácora](./09_BITACORA_IMPLEMENTACION.md) · [Decisiones y bloqueos](./10_DECISIONES_Y_BLOQUEOS.md) · [Checklist release](./11_CHECKLIST_RELEASE.md)

La rama `feat/rbac-production-hardening` nació limpia desde `f6493a3b`, que incluye el baseline frontend/CI del PR #11. La consigna del 2026-07-14 aprobó el catálogo, las matrices, la compatibilidad de `ADMINISTRADOR`, la deshabilitación de Profesor/STOMP/Observaciones y la secuencia de PRs. Todos los comandos locales obligatorios terminaron en exit 0. Falta congelar commits, crear el PR reemplazante, obtener checks remotos verdes y confirmar el merge.

## Objetivo

Dejar un RBAC determinístico desde una base limpia, con catálogo y roles base aprobados, autorización backend granular, semántica 401/403/409 correcta y frontend alineado con la misma matriz. El gate debe demostrar que una URL o llamada forzada no escala privilegios, que SUPERADMIN no depende del seed demo y que Profesor queda limitado por ownership o inactivo.

## Fuera de alcance

- No agregar permisos ni asignaciones fuera del catálogo y las matrices aprobadas.
- No reescribir V1–V5 ni corregir V6 después de aplicada/publicada; cualquier corrección futura es forward-only.
- No usar scripts/gestudio_demo_seed_full.sql como catálogo productivo o prerrequisito de bootstrap.
- No iniciar Etapa 1B, cambiar fórmulas financieras ni corregir la UX general de Etapa 2.
- No habilitar Profesor sin ownership backend probado con dos profesores.
- No dejar WebSocket/STOMP parcialmente protegido: debe quedar seguro o deshabilitado.
- No introducir un framework de permisos, jerarquía ordinal de roles, microservicios ni dependencias nuevas.
- No desplegar, migrar una base real ni ejecutar acciones externas.

## Dependencias y reglas de entrada

1. GATE-0 figura cerrado; esta continuación repone los documentos faltantes sin reinterpretar sus decisiones.
2. **DEC-RBAC-001** está tomada; V6 debe implementar el contrato sin cambiar IDs ni usuarios.
3. La cadena activa observada es V1–V5. V5 queda inmutable y la siguiente migración aprobada será forward-only.
4. Docker Engine debe estar disponible para las pruebas PostgreSQL/Testcontainers y el smoke descartable.
5. **DEC-OWNERSHIP-001** está tomada: Profesor queda inactivo y sin permisos; ownership se difiere.
6. **DEC-WS-001** está tomada: STOMP se retira y REST/email permanece.
7. Sólo una tarea puede estar **IN_PROGRESS** y toda transición se registra primero en la bitácora.

## Baseline y cierre actual verificado

| Estado | Evidencia | Consecuencia |
|---|---|---|
| BASELINE `f6493a3b` | V5 crea permisos, rol_permisos y usuario_roles, pero no inserta catálogo ni asignaciones. | Una base limpia no tenía PERM_APP_ACCESO antes de V6. |
| BASELINE `f6493a3b` | PostgreSqlSchemaValidationTest exigía cero permisos y cero permisos para SUPERADMIN. | E1-002 debía cambiar el contrato ejecutable, no sólo SQL. |
| BASELINE `f6493a3b` | SuperadminBootstrapService asignaba el rol SUPERADMIN, pero no verificaba su matriz. | Login podía funcionar mientras la API quedaba inutilizable. |
| BASELINE `f6493a3b` | SecurityConfigurations dejaba la mayoría de /api bajo PERM_APP_ACCESO y contenía un matcher mensual incorrecto. | Los writes no tenían autorización granular completa. |
| BASELINE `f6493a3b` | RbacService usaba OperacionNoPermitidaException para autoridad y se convertía en 409. | La defensa de servicio clasificaba mal una denegación. |
| CORREGIDO 2026-07-11 | UsuariosPagina y RolesPagina usan `PERMISSIONS.USUARIOS_ADMIN` y `PERMISSIONS.ROLES_ADMIN`; hay pruebas positivas y negativas. | El bloque Usuarios/Roles ya no depende de strings inexistentes. |
| CORREGIDO 2026-07-11 | `/unauthorized` no tiene permiso funcional en `routePermissions` y conserva autenticación mediante el guard exterior. | Se elimina la condición de redirección circular sin volver pública la página. |
| CORREGIDO 2026-07-11 | La API de roles rechaza códigos persistidos que comiencen con `ROLE_`; Spring conserva la responsabilidad de agregar el prefijo de authority. | Se evita crear authorities `ROLE_ROLE_*` mediante una llamada directa. |
| VALIDADO | Profesor referencia Usuario, pero los servicios aceptan IDs de profesor/disciplina/asistencia sin ownership del principal. | Profesor no puede habilitarse todavía. |
| RESUELTO 2026-07-14 | En el baseline `/ws` aceptaba origen `*`; configuración, controller, publisher, hook y dependencias STOMP fueron retirados. | DEC-WS-001 implementada; REST/email se conserva. |
| HISTÓRICO 2026-07-11 | La evidencia histórica registró 15/15 tests RBAC frontend y un bloque focalizado posterior. | Sustituida por la suite actual 140/140. |
| VALIDADO LOCAL 2026-07-14 | V6, matriz HTTP 144/144, frontend y smoke 20/20 completaron sus validaciones. | Integración remota pendiente. |

## Orden obligatorio

| Tarea | Estado | Dependencia principal | Hallazgos |
|---|---|---|---|
| E1-001 | **DONE** | GATE-0 | contrato completo aprobado el 2026-07-14 |
| E1-002 | **DONE** | DEC-RBAC-001 | P0-SEC-001 a 005 |
| E1-003 | **DONE** | E1-002 | P0-SEC-003 y 004 |
| E1-004 | **DONE** | E1-003 | P0-SEC-009 |
| E1-005 | **DONE** | E1-004 | P0-SEC-006 a 008 |
| E1-006 | **DEFERRED SAFE** | DEC-OWNERSHIP-001 | Profesor inactivo/sin permisos |
| E1-007 | **DONE** | E1-005 | P0-SEC-010, 011 y 013 |
| E1-008 | **DONE** | E1-007 | P0-SEC-012 |
| E1-009 | **DONE** | DEC-WS-001 | P0-SEC-015 |
| E1-010 | **DONE_LOCAL** | E1-001 a E1-009 | validación integral y smoke verdes; CI/merge pendientes |

No se adelanta la matriz propuesta ni una tarea posterior completa. El avance parcial del 2026-07-11 fue autorizado expresamente y se limitó a corregir inconsistencias del contrato actual, sin permisos, roles o datos nuevos.

## E1-001 — Congelar contrato y constantes

- **Estado:** DONE; contrato aprobado y registrado el 2026-07-14.
- **Dependencias:** 02_MATRIZ_RBAC.md y DEC-RBAC-001.
- **Archivos esperados:** docs/codex/gestudio-release-hardening/02_MATRIZ_RBAC.md, este documento, docs/codex/gestudio-release-hardening/10_DECISIONES_Y_BLOQUEOS.md, frontend/src/config/permissions.ts, backend/src/main/java/gestudio/infra/seguridad/SecurityConfigurations.java y los servicios que hoy declaran strings PERM_ locales. Si se aprueba, una única clase de constantes bajo backend/src/main/java/gestudio/infra/seguridad/ reemplazará la duplicación; no se crea antes.
- **Cambio esperado:** confirmar los 15 permisos actuales, los 17 códigos mínimos propuestos, la matriz SUPERADMIN/DIRECCION/SECRETARIA/CAJA/PROFESOR, la compatibilidad de ADMINISTRADOR y las reglas de delegación. Registrar aprobación o corrección exacta antes de tocar código.
- **Riesgo y rollback lógico:** tratar PROPUESTA como decisión puede otorgar privilegios. Antes de V6, el rollback es corregir documentos y constantes; no hay datos que revertir.
- **Aceptación:** respuesta explícita del usuario registrada; matriz sin ambigüedades; ningún permiso fuera de la decisión; constantes backend/frontend coincidentes y tests de contrato definidos.
- **Validación y evidencia:** inventario con rg, revisión cruzada 02/03/10, evidencia histórica frontend 15/15 y bloque actual frontend 8/8 + backend 29/29. Estas pruebas no aprueban la matriz general.

## E1-002 — Migración productiva RBAC

- **Estado:** DONE; V6 limpia y upgrade V5→V6 validados en PostgreSQL.
- **Dependencias:** E1-001 DONE y versión Flyway siguiente reconfirmada.
- **Archivos esperados:** backend/src/main/resources/db/migration/V6__rbac_permission_catalog_and_base_roles.sql como archivo nuevo; V5__base_roles_permissions_seed.sql sólo como referencia inmutable; backend/src/test/java/gestudio/infra/persistencia/PostgreSqlSchemaValidationTest.java; scripts/gestudio_demo_seed_full.sql para retirar su responsabilidad sobre el catálogo, sin mezclar los demás datos demo.
- **Cambio esperado:** insertar/reconciliar el catálogo aprobado, roles base y matriz determinística; conservar roles/usuarios existentes sin renombrado o borrado automático; invalidar sesiones afectadas mediante auth_version; separar por completo el dataset demo.
- **Riesgo y rollback lógico:** una asignación excesiva escala privilegios y una reconciliación destructiva pierde configuración. La migración debe ser idempotente respecto de códigos, detectar conflictos y no sobrescribir roles personalizados. Una V6 aplicada no se edita: se corrige forward-only y, ante un despliegue fallido, se recupera desde backup aislado.
- **Aceptación:** base limpia termina en V6 con conteos exactos; upgrade V5 a V6 conserva usuarios, usuario_roles y roles ajenos; todos los permisos usados existen y están activos; SUPERADMIN recibe la matriz aprobada; el seed demo no es necesario.
- **Validación y evidencia:** PostgreSqlSchemaValidationTest debe cubrir base limpia y upgrade desde V5, consultas de conteo/reconciliación y checksum Flyway. Resultado y conteos se registran en bitácora.

## E1-003 — Bootstrap utilizable

- **Estado:** DONE.
- **Dependencias:** E1-002.
- **Archivos esperados:** backend/src/main/java/gestudio/infra/seguridad/SuperadminBootstrapService.java, SuperadminBootstrapRunner.java, SuperadminBootstrapProperties.java, backend/src/test/java/gestudio/infra/seguridad/SuperadminBootstrapPostgreSqlTest.java y SuperadminBootstrapRunnerTest.java.
- **Cambio esperado:** reutilizar el rol sembrado por V6, verificar que esté activo y tenga el catálogo obligatorio, asignarlo al usuario bootstrap y fallar temprano con diagnóstico seguro si la matriz está incompleta. El bootstrap no se convierte en reconciliador.
- **Riesgo y rollback lógico:** un bootstrap permisivo deja un administrador inutilizable; uno reconciliador puede modificar autorización fuera de Flyway. El rollback es deshabilitar la bandera y corregir catálogo forward-only; no borrar el usuario auditado.
- **Aceptación:** migración → bootstrap → login → perfil → primer GET operativo funciona sin SQL manual ni seed demo; ejecución repetida sigue rechazada; contraseña no se expone ni persiste plana.
- **Validación y evidencia:** tests Runner y PostgreSQL, más el tramo inicial de scripts/smoke-local.ps1 sobre base descartable.

## E1-004 — Semántica de autorización

- **Estado:** DONE.
- **Dependencias:** E1-003.
- **Archivos esperados:** backend/src/main/java/gestudio/infra/seguridad/RbacService.java, backend/src/main/java/gestudio/infra/errores/TratadorDeErrores.java, backend/src/test/java/gestudio/infra/seguridad/SecurityHttpIntegrationTest.java y tests de los servicios con defensa propia.
- **Cambio esperado:** usar AccessDeniedException de Spring para falta de autoridad en RbacService y reservar OperacionNoPermitidaException para conflictos reales. Mantener respuestas JSON sanitizadas.
- **Riesgo y rollback lógico:** convertir todos los 409 en 403 ocultaría conflictos financieros. Cambiar sólo la ruta de autorización; rollback de código sin impacto persistido.
- **Aceptación:** anónimo = 401; autenticado sin permiso = 403; conflicto de negocio = 409; los tres códigos y cuerpos quedan cubiertos por HTTP y servicio.
- **Validación y evidencia:** SecurityHttpIntegrationTest y tests focalizados de RbacService/servicios; ninguna expectativa cambia un conflicto real para forzar verde.

## E1-005 — Matchers y endpoints granulares

- **Estado:** DONE; 144/144 mappings inventariados y protegidos.
- **Dependencias:** E1-004 y matriz aprobada.
- **Archivos esperados:** backend/src/main/java/gestudio/infra/seguridad/SecurityConfigurations.java; controladores reales bajo backend/src/main/java/gestudio/controladores/ y backend/src/main/java/gestudio/tarifas/api/; PagoServicio.java, EgresoServicio.java, StockServicio.java, CreditoServicio.java, UsuarioServicio.java, RolServicio.java, TarifaDisciplinaServicio.java y CondicionEconomicaServicio.java; SecurityHttpIntegrationTest.java.
- **Cambio esperado:** aplicar la matriz por método/path, corregir el matcher de POST /api/mensualidades/generar-mensualidades, conservar defensas de servicio financieras y eliminar/documentar reglas sin controlador. PERM_APP_ACCESO queda como entrada general, no como permiso suficiente para writes sensibles.
- **Riesgo y rollback lógico:** orden o patrón amplio puede abrir o bloquear rutas. Usar matchers exactos y prueba parametrizada; ante incidente, negar el endpoint afectado, nunca ampliar temporalmente el fallback.
- **Aceptación:** cada endpoint mutable tiene permiso explícito; lecturas usan el permiso de lectura aprobado; acceso directo produce 401/403/permitido según matriz; no quedan matchers huérfanos.
- **Validación y evidencia:** inventario RequestMapping contra SecurityConfigurations y matriz HTTP parametrizada en SecurityHttpIntegrationTest.

## E1-006 — Ownership Profesor

- **Estado:** DEFERRED SAFE; Profesor permanece inactivo, sin permisos y sin superficie.
- **Dependencias:** E1-005 y DEC-OWNERSHIP-001.
- **Archivos esperados:** backend/src/main/java/gestudio/entidades/Profesor.java, repositorios/ProfesorRepositorio.java, repositorios/DisciplinaRepositorio.java, servicios/profesor/ProfesorServicio.java, servicios/disciplina/DisciplinaServicio.java, servicios/asistencia/AsistenciaDiariaServicio.java, servicios/asistencia/AsistenciaMensualServicio.java y sus controladores/tests.
- **Cambio esperado:** resolver principal → Usuario → Profesor en backend y limitar consultas/mutaciones a disciplinas, alumnos y asistencias propios. Dirección/Secretaría mantienen alcance global sólo conforme a la matriz.
- **Riesgo y rollback lógico:** confiar profesorId del request filtra datos cruzados. La query/servicio debe derivar el profesor del principal. Si no puede probarse, no se asigna/habilita Profesor; ese fallback no bloquea el resto de GATE-1.
- **Aceptación:** dos profesores no pueden leer ni modificar recursos cruzados; un actor global autorizado sí; ausencia o duplicidad del vínculo usuario-profesor falla de modo seguro.
- **Validación y evidencia:** test PostgreSQL/HTTP con dos profesores, una disciplina por profesor y acceso propio/cruzado. Registrar la decisión y el estado final del rol.

## E1-007 — Contrato frontend

- **Estado:** DONE; catálogo, sesión, rutas, navegación y acciones alineados.
- **Dependencias:** E1-005.
- **Archivos esperados:** frontend/src/config/permissions.ts, config/navigation.ts, rutas/routes.ts, rutas/AppRouter.tsx, rutas/ProtectedRoute.tsx, hooks/context/auth-context.ts, hooks/context/authContext.tsx, UsuariosPagina.tsx, RolesPagina.tsx y sus tests. Crear PermissionGate mínimo sólo en la ubicación común elegida al implementarlo.
- **Cambio esperado:** completar PERMISSIONS con el catálogo aprobado, tipar consumers con PermissionCode, reemplazar USUARIOS_WRITE/ROLES_WRITE, dejar /unauthorized accesible a todo autenticado y alinear menú/ruta/acción. No crear un router o framework nuevo.
- **Riesgo y rollback lógico:** una metadata divergente produce loops u oculta funciones. Migrar rutas en una tabla pequeña y conservar backend como autoridad; rollback de presentación no cambia permisos reales.
- **Aceptación:** toda ruta protegida tiene política explícita salvo la excepción autenticada /unauthorized; no quedan strings ad hoc; menú y acceso directo coinciden.
- **Validación y evidencia:** auth-context.test.ts, navigation.test.ts, ProtectedRoute.test.tsx, UsuariosPagina.test.tsx, RolesPagina.test.tsx y RolesFormulario.test.tsx verdes.
- **Avance parcial validado:** `UsuariosPagina` y `RolesPagina` consumen las constantes reales; `/unauthorized` queda fuera de `routePermissions`; la suite focalizada modificada terminó 8/8. No se declara completado el contrato de las demás rutas o acciones.

## E1-008 — Acciones sensibles frontend

- **Estado:** DONE.
- **Dependencias:** E1-006 y E1-007.
- **Archivos esperados:** páginas/formularios de pagos, tarifas, condiciones económicas, egresos, stock, usuarios, roles, alumnos, inscripciones, disciplinas, profesores y reportes bajo frontend/src/funcionalidades/ y frontend/src/paginas/Reportes.tsx.
- **Cambio esperado:** mostrar cada alta/edición/baja/anulación/venta/exportación sólo con su permiso aprobado, reutilizando PermissionGate o hasPermission. Lectura de módulo y mutación se evalúan por separado.
- **Riesgo y rollback lógico:** ocultar acciones sin proteger API da falsa seguridad; ocultar demasiado impide operar. Cada guard frontend debe tener prueba HTTP equivalente. Rollback de UI no relaja backend.
- **Aceptación:** pagos registrar/anular, tarifas/condiciones, egresos, stock administrar/vender, seguridad, configuración, reportes/exportación y mutaciones académicas están cubiertos; una llamada forzada sigue devolviendo 403.
- **Validación y evidencia:** tests de página por permitido/denegado más matriz HTTP de E1-005; ninguna prueba se limita a ausencia visual.

## E1-009 — WebSocket y notificaciones

- **Estado:** DONE; STOMP/config/controller/hook/dependencias retirados, REST/email conservados.
- **Dependencias:** E1-005 y DEC-WS-001.
- **Archivos esperados:** backend/src/main/java/gestudio/infra/configuracion/WebSocketConfig.java, controladores/NotificacionWSController.java, servicios/notificaciones/NotificacionService.java y frontend/src/hooks/useNotificacionesWebSocket.tsx.
- **Cambio aplicado:** STOMP se deshabilitó para la primera release retirando configuración, controller, publisher, hook y dependencias; se conservan persistencia, REST y email.
- **Riesgo y rollback lógico:** dejar /ws abierto expone mensajes; retirar todo puede afectar notificaciones no relacionadas. Separar transporte de persistencia/email. Un canal deshabilitado sólo se reactiva cuando sus pruebas de seguridad estén verdes.
- **Aceptación:** no existe canal anónimo/global. Si está deshabilitado, no hay endpoint ni caller activo; si está habilitado, origen, identidad, destino y aislamiento tienen pruebas.
- **Validación y evidencia:** búsqueda de callers, prueba de contexto/HTTP para opción deshabilitada o integración STOMP para opción segura; decisión registrada antes del cambio.

## E1-010 — Suite de seguridad y smoke

- **Estado:** DONE_LOCAL; backend 129/129, frontend 140/140 y smoke 20/20.
- **Dependencias:** E1-001 a E1-009 terminadas y decisiones cerradas.
- **Archivos esperados:** SecurityHttpIntegrationTest.java, PostgreSqlSchemaValidationTest.java, SuperadminBootstrapPostgreSqlTest.java, UsuarioServicioTest.java, RolServicioTest.java, tests de ownership, tests frontend de auth/navegación/rutas/acciones, scripts/smoke-local.ps1 y 08_PLAN_DE_PRUEBAS.md.
- **Cambio esperado:** consolidar matriz método/path/permiso, 401/403/permitido, authVersion, usuario/rol/permiso inactivo, delegación, último SUPERADMIN, bootstrap, ownership, contrato usados/sembrados, frontend y smoke sin seed demo.
- **Riesgo y rollback lógico:** una suite parcial puede declarar seguro un único happy path. El gate exige PostgreSQL real y smoke aislado; no sustituir por H2, mocks incompletos o SQL manual.
- **Aceptación:** pruebas focalizadas y backend completo verdes; frontend test/lint/build verdes; smoke limpio termina en cero y no carga el seed demo.
- **Validación y evidencia:** comandos, conteos, duración, fallos clasificados y resultado de limpieza en bitácora.

## Estrategia mínima de implementación

1. Aprobar primero el contrato; ninguna autoridad se infiere de etiquetas o roles ordinales.
2. Crear una única V6 forward-only; no tocar V5 ni duplicar catálogo en bootstrap/demo.
3. Reutilizar AccessDeniedException, SecurityConfigurations, RbacService y PermissionCode antes de crear tipos nuevos.
4. Proteger backend por método/path y conservar defensa de servicio sólo donde ya existe una frontera sensible.
5. Implementar ownership en query/servicio usando el principal, nunca un ID del cliente.
6. Migrar frontend en el orden permiso → ruta → navegación → acción, con una prueba por contrato.
7. Mantener WebSocket/STOMP deshabilitado; no reintroducirlo sin contrato completo y pruebas propias.
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

No se agregan clases de ownership o WebSocket en esta release: Profesor y STOMP permanecen deshabilitados por contrato.

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

**Estado actual: ABIERTO / implementación y validación en curso.**

- [x] DEC-RBAC-001 aprobada explícitamente; E1-001 cerrada en bitácora.
- [x] V6 forward-only aplica desde vacío y actualiza desde V5 sin pérdida ni reescritura.
- [x] Catálogo, roles base y asignaciones coinciden exactamente con 02_MATRIZ_RBAC.md.
- [x] Todos los permisos usados existen, están activos y no dependen del seed demo.
- [x] Bootstrap crea un SUPERADMIN utilizable; login, perfil y primer GET pasan.
- [x] Sin token = 401; token válido sin permiso = 403; conflicto real = 409.
- [x] Cada write sensible tiene permiso backend explícito; PERM_APP_ACCESO no basta.
- [x] Usuario, rol o permiso inactivo y authVersion inválida niegan acceso efectivo.
- [x] Delegación no escala privilegios y no puede perderse el último SUPERADMIN.
- [x] Profesor permanece inactivo, sin permisos, no asignable y sin rutas visibles.
- [x] Menú, ruta y acción usan la misma matriz; /unauthorized no entra en loop.
- [x] Usuarios/Roles usan PERM_USUARIOS_ADMIN y PERM_ROLES_ADMIN — 2026-07-11, pruebas UI y HTTP focalizadas verdes.
- [x] Acceso directo a URL/API no evita controles.
- [x] WebSocket está completamente deshabilitado; notificaciones operativas quedan en REST/email.
- [x] Matriz HTTP, contrato frontend y smoke sin seed demo están verdes.
- [x] Backend, Frontend y All terminan en exit 0 sin regresiones.
- [x] 00_INDEX.md, 08_PLAN_DE_PRUEBAS.md, 09_BITACORA_IMPLEMENTACION.md, 10_DECISIONES_Y_BLOQUEOS.md y 11_CHECKLIST_RELEASE.md reflejan la evidencia.
- [ ] PR reemplazante creado, checks remotos verdes y merge confirmado a `main`.

El cierre local no habilita Parte B desde esta rama. Sólo después de un merge RBAC verde confirmado se actualiza `main` y se crea `feat/financial-integrity-v1`; si el merge no puede confirmarse, esta ejecución se detiene en ese gate.
