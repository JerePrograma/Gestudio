# Baseline y hallazgos

Última actualización: 2026-07-10 14:27 -03:00. Estado: `VALIDADO` para Git y comandos ejecutados; `INFERIDO` sólo donde se indica. Este documento se cruza con [matriz RBAC](./02_MATRIZ_RBAC.md), [Etapa 1](./03_ETAPA_1_SEGURIDAD_RBAC.md), [Etapa 1B](./04_ETAPA_1B_LIQUIDACION_FINANCIERA.md), [plan de pruebas](./08_PLAN_DE_PRUEBAS.md), [bitácora](./09_BITACORA_IMPLEMENTACION.md) y [decisiones](./10_DECISIONES_Y_BLOQUEOS.md).

## Baseline Git

| Evidencia | Resultado |
|---|---|
| Rama | `main` (`VALIDADO`) |
| `HEAD` | `b833f6741cf614c508666e8a121701e8db2fcf9a` (`VALIDADO`) |
| `origin/main` | mismo SHA, divergencia `+0/-0` (`VALIDADO`) |
| Commit | `Unifica UX frontend ocultando IDs tecnicos` |
| Árbol inicial | limpio; sin staged, unstaged ni untracked (`VALIDADO`) |
| Delta contra el commit auditado | ninguno: el commit auditado es el `HEAD` actual |

Comandos registrados: `git status --short --branch`, `git branch --show-current`, `git rev-parse HEAD`, `git fetch origin --prune`, `git rev-parse origin/main`, `git log -1 --oneline`, `git diff --exit-code` y `git diff --cached --exit-code`. No se modificaron refs.

Artefactos locales ignorados preservados y fuera de lectura/escritura: `.env.bootstrap.local`, `.env.runtime.local`, `basebackup/`, `.idea/`, `backend/target/`, `frontend/node_modules/` y `frontend/dist/`.

## Stack verificado

| Área | Fuente de evidencia | Estado |
|---|---|---|
| Backend Java 21 / Spring Boot 3.4.1 / Maven Wrapper 3.9.10 | `backend/pom.xml`, `backend/.mvn/wrapper/maven-wrapper.properties` | `VALIDADO` |
| PostgreSQL/Flyway/JPA/Testcontainers | `backend/pom.xml`, `backend/src/main/resources/application.yml`, `backend/src/test/java/gestudio/infra/persistencia/PostgreSqlIntegrationTest.java` | `VALIDADO` |
| React 18 / TypeScript / Vite / TanStack Query | `frontend/package.json`, `frontend/vite.config.ts` | `VALIDADO` |
| Cadena Flyway activa V1-V5 | `backend/src/main/resources/db/migration/`, `README.md`, `scripts/smoke-local.ps1` | `VALIDADO` |
| Validación local | `scripts/codex/setup.ps1`, `scripts/codex/validate.ps1` | `VALIDADO` |

La cadena observada es forward-only V1-V5. V1 es el baseline canónico; V5 puede estar aplicada y no se reescribe. El siguiente cambio productivo autorizado será V6. Ver [DEC-DB-001](./10_DECISIONES_Y_BLOQUEOS.md#dec-db-001--cadena-flyway-activa-y-dirección-v6).

## Validación inicial

| Alcance | Comando | Resultado exacto | Clasificación |
|---|---|---|---|
| Frontend | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend` | lint `PASS`; tests 33/36; build `PASS` | suite `FAIL`, tres fallos preexistentes |
| Backend | `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend` | `clean verify`, 115/115 tests, PostgreSQL Testcontainers, `BUILD SUCCESS` | `PASS` |

Fallos frontend conocidos y conservados como baseline:

1. `frontend/src/funcionalidades/alumnos/AlumnosPagina.test.tsx`: una expectativa singular no contempla que la vista responsive mantiene representación desktop/mobile en el DOM.
2. `frontend/src/funcionalidades/pagos/PagosPagina.test.tsx`: dos expectativas usan `$ 100.50` mientras el formatter real muestra `$ 100,50`.

No se debilitan esas pruebas durante Etapa 1. Su corrección pertenece a `E2-010` y debe conservar la intención funcional.

## Cierre de Etapa 0

| Tarea | Estado | Evidencia de cierre |
|---|---|---|
| `E0-001` Git y AGENTS | `DONE` | Git exacto y único `AGENTS.md` aplicable leído |
| `E0-002` baseline frontend | `DONE` | lint/build pasan; 33/36 tests y tres fallos clasificados |
| `E0-003` baseline backend | `DONE` | 115/115 con PostgreSQL Testcontainers |
| `E0-004` rutas/endpoints/permisos | `DONE` | inventario en [02_MATRIZ_RBAC.md](./02_MATRIZ_RBAC.md) |
| `E0-005` seeds/bootstrap | `DONE` | V5, schema test y bootstrap inspeccionados; `P0-SEC-001` a `005` |
| `E0-006` cálculo financiero | `DONE` | `P0-FIN-001` a `006` y [Etapa 1B](./04_ETAPA_1B_LIQUIDACION_FINANCIERA.md) |
| `E0-007` IDs/búsquedas/flujos UX | `DONE` | `P1-UX-001` a `022` clasificados |
| `E0-008` documentación cruzada | `DONE` | tablero y doce documentos enlazados |

`GATE-0` queda cerrado. La única tarea `IN_PROGRESS` es `E1-001`; `E1-002` está bloqueada por [DEC-RBAC-001](./10_DECISIONES_Y_BLOQUEOS.md#dec-rbac-001--matriz-base-de-roles-y-permisos).

## Hallazgos P0 de seguridad

| ID | Estado | Hallazgo y evidencia exacta | Tarea |
|---|---|---|---|
| `P0-SEC-001` | `VALIDADO` | V5 crea `permisos`, `rol_permisos` y `usuario_roles`, pero declara y ejecuta cero seed operativo: `backend/src/main/resources/db/migration/V5__base_roles_permissions_seed.sql`. | `E1-002` |
| `P0-SEC-002` | `VALIDADO` | El test exige cero permisos y cero permisos SUPERADMIN: `backend/src/test/java/gestudio/infra/persistencia/PostgreSqlSchemaValidationTest.java`. | `E1-002` |
| `P0-SEC-003` | `VALIDADO` | El bootstrap crea/asigna SUPERADMIN pero no reconcilia catálogo ni matriz: `backend/src/main/java/gestudio/infra/seguridad/SuperadminBootstrapService.java`. | `E1-003` |
| `P0-SEC-004` | `VALIDADO` | `/api/**` exige `PERM_APP_ACCESO`; una base limpia sin catálogo permite autenticar pero no operar: `backend/src/main/java/gestudio/infra/seguridad/SecurityConfigurations.java`, `backend/src/main/resources/db/migration/V5__base_roles_permissions_seed.sql`. | `E1-002`, `E1-003` |
| `P0-SEC-005` | `VALIDADO` | `scripts/gestudio_demo_seed_full.sql` agrega permisos fuera de Flyway y no contiene `PERM_TARIFAS_HISTORICAS`; no es catálogo productivo. | `E1-002` |
| `P0-SEC-006` | `VALIDADO` | Sólo Usuarios, Roles, Permisos, auditoría y generación manual tienen matchers granulares; el resto cae en APP_ACCESS: `backend/src/main/java/gestudio/infra/seguridad/SecurityConfigurations.java`. | `E1-005` |
| `P0-SEC-007` | `VALIDADO` | Matcher inexistente `/api/mensualidades/generar-periodo/manual`; endpoint real `/api/mensualidades/generar-mensualidades`: `SecurityConfigurations.java`, `backend/src/main/java/gestudio/controladores/MensualidadControlador.java`. | `E1-005` |
| `P0-SEC-008` | `VALIDADO` | La mayoría de controllers read/write queda sólo bajo `PERM_APP_ACCESO`: `backend/src/main/java/gestudio/controladores/`, `backend/src/main/java/gestudio/tarifas/api/`. | `E1-005` |
| `P0-SEC-009` | `VALIDADO` | `RbacService.exigirPermiso` usa `OperacionNoPermitidaException`, mapeada a 409; existe handler 403 separado que no recibe esa excepción: `backend/src/main/java/gestudio/infra/seguridad/RbacService.java`, `backend/src/main/java/gestudio/infra/errores/TratadorDeErrores.java`. | `E1-004` |
| `P0-SEC-010` | `VALIDADO` | Usuarios consulta `USUARIOS_WRITE` en lugar de `PERM_USUARIOS_ADMIN`: `frontend/src/funcionalidades/usuarios/UsuariosPagina.tsx`, `frontend/src/config/permissions.ts`. | `E1-007` |
| `P0-SEC-011` | `VALIDADO` | Roles consulta `ROLES_WRITE` en lugar de `PERM_ROLES_ADMIN`: `frontend/src/funcionalidades/roles/RolesPagina.tsx`, `frontend/src/config/permissions.ts`. | `E1-007` |
| `P0-SEC-012` | `VALIDADO` | Fuera de esas páginas casi no hay guards de acciones; inventario `hasPermission` en `frontend/src/` y acciones en páginas operativas. | `E1-008` |
| `P0-SEC-013` | `VALIDADO` | `/unauthorized` exige APP_ACCESS y `ProtectedRoute` redirige allí al faltar permiso: `frontend/src/rutas/routes.ts`, `frontend/src/rutas/ProtectedRoute.tsx`. | `E1-007` |
| `P0-SEC-014` | `INFERIDO` | Profesor referencia Usuario, pero endpoints de disciplinas/alumnos/asistencias aceptan IDs sin ownership demostrado: `backend/src/main/java/gestudio/entidades/Profesor.java`, `ProfesorControlador.java`, `DisciplinaControlador.java`, `AsistenciaDiariaControlador.java`. | `E1-006` |
| `P0-SEC-015` | `VALIDADO` | Backend acepta origen `*`; frontend fija `ws://localhost:8080/ws` y tópico global, sin callers productivos observados: `backend/src/main/java/gestudio/infra/configuracion/WebSocketConfig.java`, `frontend/src/hooks/useNotificacionesWebSocket.tsx`. | `E1-009` |

## Hallazgos P0 financieros

| ID | Estado | Hallazgo y evidencia exacta | Tarea |
|---|---|---|---|
| `P0-FIN-001` | `VALIDADO` | Existen tarifas/condiciones por vigencia y pantallas: V3, `backend/src/main/java/gestudio/tarifas/`, `frontend/src/funcionalidades/disciplinas/TarifasDisciplinaPagina.tsx`, `frontend/src/funcionalidades/inscripciones/CondicionesEconomicasPagina.tsx`. | `E1B-001` |
| `P0-FIN-002` | `VALIDADO` | Mensualidad usa `inscripcion.costoParticular`, `disciplina.valorCuota` y bonificación legacy: `backend/src/main/java/gestudio/servicios/mensualidad/MensualidadServicio.java`. | `E1B-003` |
| `P0-FIN-003` | `VALIDADO` | Matrícula toma el máximo de `disciplina.matricula` legacy: `backend/src/main/java/gestudio/servicios/matricula/MatriculaServicio.java`. | `E1B-004` |
| `P0-FIN-004` | `VALIDADO` | `LiquidacionCargoServicio.registrar` existe, pero no tiene caller productivo: `backend/src/main/java/gestudio/cuotas/application/LiquidacionCargoServicio.java`. | `E1B-002`, `E1B-005` |
| `P0-FIN-005` | `INFERIDO` | Crear una tarifa futura no cambia los cargos porque los flujos reales no consultan repositorios por vigencia: servicios anteriores y `backend/src/main/java/gestudio/tarifas/persistence/*Repositorio.java`. | `E1B-003`, `E1B-004` |
| `P0-FIN-006` | `VALIDADO` | Coexisten campos legacy en V1/entidades y tablas efectivas V3: `V1__canonical_schema.sql`, `V3__effective_dated_pricing.sql`, `Disciplina.java`, `Inscripcion.java`. | `E1B-006` |

## Hallazgos P1 UX/funcionales

| ID | Estado | Hallazgo y evidencia exacta | Tarea |
|---|---|---|---|
| `P1-UX-001` | `VALIDADO` | Pagos muestra columna ID y toast `Pago {id} registrado`: `PagosPagina.tsx`, `PagosFormulario.tsx`. | `E2-003`, `E2-005` |
| `P1-UX-002` | `VALIDADO` | IDs visibles en Usuarios, Métodos, Conceptos, Bonificaciones, Salones, Subconceptos y Recargos: páginas homónimas bajo `frontend/src/funcionalidades/`. | `E2-003` |
| `P1-UX-003` | `VALIDADO` | Caja muestra `Pago {pagoId}` / `Egreso {egresoId}`: `frontend/src/funcionalidades/caja/CajaPagina.tsx`. | `E2-005` |
| `P1-UX-004` | `VALIDADO` | Búsqueda por `idBusqueda` en Profesor, Salón, Bonificación, Subconcepto y Método: formularios homónimos bajo `frontend/src/funcionalidades/`. | `E2-001`, `E2-002` |
| `P1-UX-005` | `VALIDADO` | Búsqueda backend concatena sólo `nombre apellido`, activos, sin documento: `backend/src/main/java/gestudio/repositorios/AlumnoRepositorio.java`. | `E2-001` |
| `P1-UX-006` | `VALIDADO` | UI ofrece Editar; backend obtiene/modifica sólo activos y no hay reactivación: `AlumnosPagina.tsx`, `AlumnoServicio.java`, `AlumnoRepositorio.java`. | `E2-004` |
| `P1-UX-007` | `VALIDADO` | Formulario permite editar alumno/disciplina, servicio conserva la invariante: `InscripcionesFormulario.tsx`, `backend/src/main/java/gestudio/servicios/inscripcion/InscripcionServicio.java`. | `E2-004` |
| `P1-UX-008` | `VALIDADO` | Backend tiene baja/finalización vía DELETE y la página no la expone: `InscripcionControlador.java`, `InscripcionesPagina.tsx`. | `E2-004` |
| `P1-UX-009` | `VALIDADO` | Formulario general edita cantidad; venta/reversión sólo backend: `StocksFormulario.tsx`, `StockControlador.java`, `StockServicio.java`. | `E2-007` |
| `P1-UX-010` | `VALIDADO` | UI de egresos registra datos mínimos y no ofrece anulación existente: `EgresosPagina.tsx`, `EgresoControlador.java`. | `E2-006` |
| `P1-UX-011` | `VALIDADO` | Caja inicia con rango vacío/UTC y poco contexto: `CajaPagina.tsx` usa `toISOString()`. | `E2-005` |
| `P1-UX-012` | `VALIDADO` | Flujo asistencia mantiene fechas UTC/debounce y no cubre de forma coherente todos los estados/guardado: `AsistenciaDiariaFormulario.tsx`, `AsistenciaMensualDetalle.tsx`. | `E2-008` |
| `P1-UX-013` | `VALIDADO` | Usuarios denomina Eliminar a desactivación y omite reactivación/estado: `UsuariosPagina.tsx`, `UsuarioServicio.java`. | `E2-009` |
| `P1-UX-014` | `VALIDADO` | Roles prioriza códigos/reglas UI y el backend posee reglas propias `sistema/editable`: `RolesPagina.tsx`, `RolServicio.java`. | `E2-009` |
| `P1-UX-015` | `VALIDADO` | Headers incluyen Acciones aunque `Tabla` agrega la columna: `SalonesPagina.tsx`, `SubConceptosPagina.tsx`, `RecargosPagina.tsx`, `componentes/comunes/Tabla.tsx`. | `E2-009` |
| `P1-UX-016` | `VALIDADO` | Recargos muestra Eliminar sin acción conectada y omite regla operativa: `RecargosPagina.tsx`. | `E2-009` |
| `P1-UX-017` | `VALIDADO` | Método de pago ofrece hard delete pese a endpoint de baja: `MetodosPagoPagina.tsx`, `MetodoPagoControlador.java`. | `E2-009` |
| `P1-UX-018` | `VALIDADO` | `/reportes` existe bajo APP_ACCESS y exportar carece de permiso propio: `routes.ts`, `Reportes.tsx`, `ReporteControlador.java`. | `E1-008`, `E2-003` |
| `P1-UX-019` | `VALIDADO` | Observaciones tiene API/componentes pero no ruta productiva: `ObservacionProfesorControlador.java`, `ConsultaObservacionesProfesores.tsx`, `routes.ts`. | `E4-003` |
| `P1-UX-020` | `VALIDADO` | Dashboard replica accesos y no muestra señales operativas: `frontend/src/paginas/Dashboard.tsx`, `config/navigation.ts`. | `E4-001` |
| `P1-UX-021` | `VALIDADO` | Selectores/búsquedas de alumnos y disciplinas están duplicados en Pagos, Inscripciones y Asistencia: formularios de esas funcionalidades. | `E2-002` |
| `P1-UX-022` | `VALIDADO` | Formatos/estados/mensajes divergen; los dos tests monetarios rojos son evidencia ejecutable: `frontend/src/utils/money.ts`, tests/páginas operativas. | `E2-010`, `E3-002` |

## Hallazgos P2 operativos

| ID | Estado | Hallazgo | Seguimiento |
|---|---|---|---|
| `P2-OPS-001` | `VALIDADO` | `.codex/environments/environment.toml` autogenerado diverge de `scripts/codex`: exige Maven global, permite fallback `npm install` y omite tests/Compose. | Reconciliar sólo mediante el generador autorizado. |
| `P2-CFG-001` | `VALIDADO` | Compose/docs usan `JWT_*_TOKEN_HOURS`; `JwtProperties` consume `JWT_*_TOKEN_TTL`: `docker-compose*.yml`, `application*.yml`, `JwtProperties.java`. | Etapa 4/configuración antes de staging. |
| `P2-DOC-001` | `VALIDADO` | `AGENTS.md` conserva texto pre-V2 mientras README/smoke operan V1-V5. | DEC-DB-001 evita reescrituras; actualizar instrucciones con autoridad explícita. |
| `P2-TEST-001` | `VALIDADO` | `TESTING.md` y `TESTING_QUICKSTART.md` reflejan conteos y comandos antiguos. | Etapa 4/informe release. |

## Riesgos que bloquean demo o publicación

- `RIESGOSO`: base limpia sin catálogo RBAC determinístico puede autenticar y negar toda la API.
- `RIESGOSO`: writes operativos quedan bajo permiso genérico; 409 oculta denegaciones de autoridad.
- `RIESGOSO`: doble fuente financiera puede cobrar un importe distinto al configurado por vigencia.
- `RIESGOSO`: WebSocket queda abierto/incompleto hasta elegir deshabilitar o asegurar.
- `RIESGOSO`: ownership Profesor no está probado; el rol no debe habilitarse.
- `NO_VERIFICADO`: no hay GATE-1, smoke de seguridad ni GATE-1B cerrados.
- `VALIDADO`: la suite frontend no está verde; los tres fallos están clasificados, no resueltos.

Próximo paso único: resolver [DEC-RBAC-001](./10_DECISIONES_Y_BLOQUEOS.md#dec-rbac-001--matriz-base-de-roles-y-permisos) para completar `E1-001` y habilitar `E1-002`.
