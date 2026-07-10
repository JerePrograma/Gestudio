# Megaprompt para Codex — Gestudio: documentación, hardening y ejecución por etapas

Copiar desde “INICIO DEL PROMPT” hasta “FIN DEL PROMPT” y pegarlo en Codex abierto en `C:\laburo\Gestudio`.

---

## INICIO DEL PROMPT

Quiero que actúes como responsable técnico principal de **Gestudio** y conduzcas un proceso completo, incremental, verificable y documentado para dejar el producto listo para una demo comercial real y posteriormente para publicación.

No quiero una respuesta teórica ni una lista genérica. Quiero que:

1. verifiques el estado real del repositorio;
2. crees dentro del repo una documentación `.md` ordenada que sea la fuente de verdad del trabajo;
3. conviertas cada hallazgo en tareas pequeñas, con dependencias, archivos, criterios de aceptación y pruebas;
4. trabajes **una etapa por vez**;
5. actualices la documentación y la bitácora mientras implementás;
6. no avances de etapa hasta cerrar su gate y recibir mi autorización explícita.

Dentro de una etapa tenés autonomía para inspeccionar, implementar, probar y corregir. Entre etapas debés detenerte, resumir evidencia y pedirme que confirme la continuación.

## 1. Contexto del repositorio

- Proyecto: `Gestudio`
- Repositorio: `JerePrograma/Gestudio`
- Ruta local: `C:\laburo\Gestudio`
- Branch esperada: `main`
- Commit base auditado: `b833f6741cf614c508666e8a121701e8db2fcf9a`
- Mensaje del commit: `Unifica UX frontend ocultando IDs tecnicos`
- Estado esperado al comenzar: working tree clean y `main` alineada con `origin/main`.

Stack:

- Backend: Java 21, Spring Boot 3.4.x, PostgreSQL, Flyway, JPA/Hibernate, Maven y Testcontainers.
- Frontend: React, TypeScript, Vite y TanStack Query.
- Sistema operativo local: Windows con PowerShell.
- Producto: administración de academias de danza e instituciones presenciales.
- Usuarios objetivo: dirección, secretaría/caja y profesores; no desarrolladores.

Objetivo comercial:

- permitir alta y búsqueda de alumnos;
- inscripciones y condiciones económicas;
- mensualidades, matrículas, cargos, pagos y deudas;
- caja diaria y egresos;
- disciplinas, horarios, profesores y salones;
- asistencia diaria/mensual;
- stock/ventas si el módulo se ofrece;
- reportes;
- usuarios, roles y permisos seguros;
- uso cómodo desde PC y celular.

## 2. Protocolo obligatorio antes de tocar archivos

Ejecutá y registrá:

```powershell
Set-Location C:\laburo\Gestudio
git status --short --branch
git branch --show-current
git rev-parse HEAD
git fetch origin --prune
git rev-parse origin/main
git log -1 --oneline
git diff --exit-code
git diff --cached --exit-code
```

Después:

1. Leé por completo el `AGENTS.md` aplicable y cualquier instrucción más específica en subdirectorios.
2. Inspeccioná la estructura real con `rg --files`.
3. No supongas que los nombres o rutas de esta consigna siguen idénticos si HEAD cambió.
4. Si HEAD no es `b833f674...`, no hagas reset, checkout destructivo ni descartes cambios. Compará el delta desde ese commit, explicá si los hallazgos siguen vigentes y actualizá la documentación.
5. Si el working tree está sucio, no borres ni sobrescribas cambios. Identificá qué archivos son del usuario y si se superponen con la etapa. Si hay superposición material, detenete antes de editar código y pedime dirección.
6. No hagas commit, push, PR, merge, rebase, reset ni cambio de branch sin mi autorización explícita.
7. No ejecutes comandos destructivos sobre bases con datos reales. Testcontainers o bases descartables son el entorno válido para pruebas destructivas.

## 3. Reglas de trabajo no negociables

### 3.1 Alcance y secuencia

- Primero documentación y baseline.
- Después Etapa 1: seguridad/RBAC.
- Después Etapa 1B: liquidación financiera por vigencia.
- Después Etapa 2: UX operativa crítica.
- Después Etapa 3: componentes y contratos reutilizables.
- Después Etapa 4: demo y publicación.
- No mezcles tareas de etapas futuras salvo que sean un prerrequisito técnico indispensable; si ocurre, documentalo.
- Mantené exactamente una tarea marcada `IN_PROGRESS`.
- No avances con tests rojos sin clasificar si son preexistentes, introducidos por la tarea o bloqueo del entorno.

### 3.2 Seguridad

- Ocultar botones en frontend no es autorización.
- Sin autenticación corresponde 401.
- Autenticado sin permiso corresponde 403.
- Conflicto de negocio corresponde 409.
- Usuario, rol o permiso inactivo invalida acceso efectivo.
- Cambios de seguridad deben invalidar sesiones mediante `authVersion` según el diseño existente.
- Nunca confíes permisos enviados por el frontend o almacenados sólo en JWT.
- Todo endpoint mutable debe tener permiso explícito o una decisión documentada que justifique lo contrario.
- Operaciones financieras sensibles deben conservar defensa en profundidad en servicio.
- Si se habilita un rol Profesor, el ownership se controla en backend/query, no sólo en UI.

### 3.3 Base de datos y Flyway

- V5 puede estar aplicada en entornos existentes.
- No reescribas V5 para resolver el catálogo RBAC.
- La próxima migración productiva debe ser forward-only, previsiblemente V6, después de verificar el estado real.
- No uses una migración V900 ni un seed demo como sustituto de configuración productiva.
- Los datos demo deben permanecer separados del catálogo operativo obligatorio.
- Todo cambio de esquema debe probar base limpia y upgrade desde el estado anterior.

### 3.4 UX

- IDs internos sólo para backend, rutas, keys, mutaciones y payloads.
- Nunca mostrar como dato operativo `id`, `alumnoId`, `cargoId`, `inscripcionId`, `pagoId` o equivalentes.
- Búsquedas por nombre, apellido, DNI/documento, descripción o contexto humano.
- Acciones con verbos concretos: Editar, Ver pagos, Registrar pago, Dar de baja, Reactivar, Anular, Condiciones, Descargar recibo.
- No ofrecer acciones que backend rechazará por una invariante conocida.
- No dejar botones sin implementación.
- No usar borrado físico para catálogos referenciados históricamente salvo justificación y prueba explícita.
- Diseñar para una secretaria real: poca carga cognitiva, siguiente paso visible y errores accionables.

### 3.5 Ingeniería

- Usá `rg`/`rg --files` para búsquedas.
- Hacé cambios pequeños y coherentes.
- No introduzcas frameworks nuevos sin necesidad.
- No crees una megatabla ni un CRUD genérico prematuro.
- Extraé un componente sólo cuando el patrón real y su contrato estén claros.
- Eliminá código muerto sólo después de confirmar que no forma parte del alcance.
- No afirmes “validado” si no corriste la prueba correspondiente.
- Si una prueba no puede correr, marcala `NO_VERIFICADO`, explicá el bloqueo y dejá el comando exacto.

## 4. Estado observado que debés verificar y convertir en tareas

Tomá estos puntos como hipótesis de auditoría de alta confianza. Confirmalos en el HEAD real antes de implementarlos.

### 4.1 Aspectos bien encaminados

- El frontend ya tiene una base común útil: `PageHeader`, `SectionCard`, `SearchInput`, `PaginationControls`, `RowActions`, `StatusBadge`, `EmptyState`, `ErrorState` y `LoadingState`.
- Alumnos, Inscripciones, Disciplinas, Profesores y Stock ocultan IDs en sus tablas principales.
- PagosFormulario permite seleccionar alumno y cargos con contexto humano.
- El backend separa access y refresh tokens.
- Refresh usa cookie HttpOnly y existe protección de origen para refresh/logout.
- `SecurityFilter` relee usuario, actividad, `authVersion`, roles y permisos.
- Los permisos no se confían desde claims JWT.
- El frontend refresca sólo frente a 401 y no destruye sesión frente a 403.
- Usuarios/Roles tienen barrera backend específica.
- Pagos, Stock, Egresos, Crédito, Tarifas y Roles tienen controles de servicio parciales que deben conservarse.

### 4.2 P0 de seguridad

1. `V5__base_roles_permissions_seed.sql` crea estructura RBAC pero no siembra permisos ni asignaciones.
2. Los tests de esquema actuales parecen exigir que `permisos` y permisos de SUPERADMIN queden en cero.
3. `SuperadminBootstrapService` crea usuario/rol SUPERADMIN, pero no garantiza permisos.
4. `/api/**` exige `PERM_APP_ACCESO`; por eso una base limpia puede permitir login y bloquear toda operación.
5. `scripts/gestudio_demo_seed_full.sql` agrega manualmente permisos, pero no es seed productivo y omite `PERM_TARIFAS_HISTORICAS`.
6. `SecurityConfigurations` sólo protege granularmente Usuarios, Roles, Permisos y una ruta de auditoría.
7. El matcher `/api/mensualidades/generar-periodo/manual` no coincide con el endpoint real `/api/mensualidades/generar-mensualidades`.
8. La mayoría de los controladores cae en `PERM_APP_ACCESO` para lectura y escritura.
9. `RbacService.exigirPermiso` lanza una excepción que el handler global convierte en 409, no 403.
10. `UsuariosPagina.tsx` consulta `USUARIOS_WRITE` en vez de `PERM_USUARIOS_ADMIN`.
11. `RolesPagina.tsx` consulta `ROLES_WRITE` en vez de `PERM_ROLES_ADMIN`.
12. Fuera de navegación, rutas y esas páginas, casi no hay guards de acciones frontend.
13. `/unauthorized` parece requerir `PERM_APP_ACCESO`, lo que puede provocar redirección circular.
14. Profesor tiene relación con Usuario, pero no se observó ownership para disciplinas/alumnos/asistencias.
15. WebSocket/notificaciones usa o usaba origen `*`, carece de autorización STOMP y el frontend apunta a `ws://localhost:8080/ws`; decidir deshabilitar o terminar de asegurar.

### 4.3 P0 financiero

1. Tarifas por vigencia y condiciones económicas tienen tablas, servicios y pantallas.
2. Mensualidades siguen calculando desde `inscripcion.costoParticular` o `disciplina.valorCuota` y bonificación legacy.
3. Matrículas siguen calculando desde `disciplina.matricula`.
4. `LiquidacionCargoServicio` registra snapshots, pero no se observó integrado al flujo real de cargos.
5. La UI puede confirmar una tarifa futura que luego no modifica el cargo.
6. Existen dos fuentes de verdad: precios legacy y tarifas/condiciones con vigencia.

### 4.4 P1 UX/funcional

1. Pagos todavía muestra columna `ID` y toast `Pago {id} registrado`.
2. Usuarios, Métodos de pago, Conceptos, Bonificaciones, Salones, Subconceptos y Recargos muestran IDs.
3. Caja muestra referencias como `Pago {pagoId}` o `Egreso {egresoId}`.
4. Profesor, Salón, Bonificación, Subconcepto y Método de pago tienen búsqueda técnica por ID.
5. La búsqueda de alumnos promete documento, pero backend parece buscar sólo `nombre + apellido` y sólo en ese orden.
6. Alumnos inactivos pueden aparecer con Editar aunque el backend obtenga/edite sólo activos; falta Reactivar.
7. InscripcionesFormulario permite cambiar alumno/disciplina en edición, pero backend lo rechaza.
8. InscripcionesPagina no ofrece finalizar/dar de baja aunque existe operación backend.
9. Stock permite editar cantidad aunque backend exige movimientos; venta/reversión existen en backend pero no en UI.
10. Egresos omite motivo/observaciones relevantes y no permite anular desde UI.
11. Caja inicia vacía, tiene poco contexto humano y usa una fecha derivada de UTC.
12. Asistencia no usa de forma completa JUSTIFICADO, no permite marcar todos, no indica guardado y tiene lógica mensual/debounce frágil.
13. Usuarios llama Eliminar a una desactivación y no muestra estado/reactivación.
14. Roles tiene reglas frontend `sistema/editable` distintas del backend y prioriza códigos técnicos.
15. Salones/Subconceptos/Recargos pueden duplicar el header Acciones porque `Tabla` ya lo agrega.
16. Recargos muestra un botón Eliminar sin acción y oculta datos operativos de la regla.
17. Métodos de pago usa borrado físico aunque existe baja lógica.
18. `/reportes` existe pero no está bien integrado a navegación; exportar no tiene permiso propio.
19. Observaciones de profesores parece tener componente/API pero no ruta productiva.
20. Dashboard duplica navegación y no muestra información operativa.
21. Hay selectores de alumnos y disciplinas duplicados.
22. Estados, fechas, moneda y mensajes de error son inconsistentes.

### 4.5 Estado de validación conocido en el commit auditado

- `npm run lint`: pasaba.
- `npm run build`: pasaba.
- `npm test`: 33/36 tests pasaban; 3 fallaban.
- Un fallo de Alumnos se relacionaba con la duplicación desktop/mobile en DOM.
- Dos fallos de Pagos esperaban `$ 100.50`, pero la UI renderizaba `$ 100,50`.
- Backend no pudo validarse en la auditoría externa por bloqueo de Maven Central; debés ejecutarlo localmente.

No tomes esos resultados como actuales sin correrlos nuevamente.

## 5. Documentación obligatoria que debés crear primero

Creá este directorio, salvo que `AGENTS.md` imponga otro lugar:

`docs/codex/gestudio-release-hardening/`

Creá los siguientes archivos en este orden:

1. `00_INDEX.md`
2. `01_BASELINE_Y_HALLAZGOS.md`
3. `02_MATRIZ_RBAC.md`
4. `03_ETAPA_1_SEGURIDAD_RBAC.md`
5. `04_ETAPA_1B_LIQUIDACION_FINANCIERA.md`
6. `05_ETAPA_2_UX_OPERATIVA.md`
7. `06_ETAPA_3_COMPONENTES_Y_CONTRATOS.md`
8. `07_ETAPA_4_DEMO_Y_PUBLICACION.md`
9. `08_PLAN_DE_PRUEBAS.md`
10. `09_BITACORA_IMPLEMENTACION.md`
11. `10_DECISIONES_Y_BLOQUEOS.md`
12. `11_CHECKLIST_RELEASE.md`

### 5.1 Reglas de los `.md`

- Deben basarse en el código real, no copiar ciegamente esta consigna.
- Usar las etiquetas `VALIDADO`, `INFERIDO`, `NO_VERIFICADO`, `RIESGOSO`, `RECOMENDADO` y `PROPUESTA`.
- Cada hallazgo debe tener ID estable: `P0-SEC-001`, `P0-FIN-001`, `P1-UX-001`, etc.
- Cada tarea debe tener ID estable: `E1-001`, `E1B-001`, `E2-001`, etc.
- Estados válidos: `PENDING`, `IN_PROGRESS`, `BLOCKED`, `DONE`, `DEFERRED`.
- Sólo una tarea puede estar `IN_PROGRESS`.
- Cada tarea debe indicar dependencias, archivos, cambio esperado, riesgo, aceptación, tests y evidencia.
- Cuando una tarea termina, registrar comandos ejecutados y resultado resumido.
- No pegar logs enormes; guardar la causa relevante y conteos.
- Si cambia el alcance, registrar una decisión en `10_DECISIONES_Y_BLOQUEOS.md`.

### 5.2 Contenido específico de cada archivo

#### `00_INDEX.md`

Debe ser el tablero maestro:

- baseline Git;
- etapa actual;
- tarea actual;
- último gate cerrado;
- bloqueos;
- enlaces relativos a todos los documentos;
- tabla de progreso por etapa;
- definición de estados;
- próximo paso exacto.

#### `01_BASELINE_Y_HALLAZGOS.md`

Debe contener:

- SHA/branch/estado real;
- stack verificado;
- comandos baseline;
- validación frontend/backend inicial;
- hallazgos P0/P1/P2 con archivos y evidencia;
- qué cambió respecto de `b833f674` si HEAD es otro;
- riesgos que impiden demo y publicación.

#### `02_MATRIZ_RBAC.md`

Para cada módulo:

- ruta frontend;
- acción visible;
- método y endpoint backend;
- permiso esperado;
- permiso actual;
- si existe en código;
- si está sembrado;
- si lo exige frontend;
- si lo exige backend;
- ownership;
- estado;
- cambio;
- test 401/403/permitido.

Incluir también:

- catálogo actual real;
- catálogo propuesto;
- matriz de roles base;
- reglas de delegación/escalamiento;
- permisos usados pero no sembrados;
- permisos sembrados pero no usados;
- endpoints sin permiso granular.

#### Documentos de etapa

Cada documento de etapa debe contener:

- objetivo;
- fuera de alcance;
- dependencias;
- orden de tareas;
- checklist con IDs;
- archivos esperados;
- estrategia de implementación;
- riesgo y rollback lógico;
- criterios de aceptación;
- validación por tarea;
- gate final;
- estado actual.

#### `08_PLAN_DE_PRUEBAS.md`

Separar:

- unitarios frontend;
- integración frontend;
- unitarios backend;
- MockMvc/HTTP;
- PostgreSQL/Testcontainers;
- Flyway base limpia y upgrade;
- contratos de permisos/rutas;
- E2E por rol;
- smoke local;
- checklist responsive/accesibilidad;
- comandos PowerShell exactos.

#### `09_BITACORA_IMPLEMENTACION.md`

Entrada cronológica por tarea:

- fecha/hora;
- tarea;
- archivos;
- decisión;
- pruebas;
- resultado;
- deuda o seguimiento.

#### `10_DECISIONES_Y_BLOQUEOS.md`

Cada decisión:

- ID `DEC-xxx`;
- contexto;
- opciones;
- recomendación;
- decisión tomada;
- consecuencias;
- fecha;
- si requiere mi confirmación.

Cada bloqueo:

- ID `BLK-xxx`;
- síntoma;
- causa;
- intentos seguros;
- autoridad o dato necesario;
- tarea afectada.

#### `11_CHECKLIST_RELEASE.md`

Separar gates:

- demo interna;
- demo comercial;
- staging;
- producción;
- seguridad;
- datos/migraciones;
- observabilidad/backup;
- rollback;
- UX crítica;
- documentación.

## 6. Catálogo de permisos: punto de partida

Primero verificá en código principal los permisos actuales. En `b833f674` se observaron:

- `PERM_APP_ACCESO`
- `PERM_USUARIOS_ADMIN`
- `PERM_ROLES_ADMIN`
- `PERM_AUDITORIA_SEGURIDAD_LEER`
- `PERM_MENSUALIDADES_GENERAR_MANUAL`
- `PERM_PAGOS_REGISTRAR`
- `PERM_PAGOS_ANULAR`
- `PERM_EGRESOS_ADMIN`
- `PERM_STOCK_ADMIN`
- `PERM_STOCK_VENDER`
- `PERM_CREDITOS_ADMIN`
- `PERM_CREDITOS_CONSUMIR`
- `PERM_TARIFAS_ADMIN`
- `PERM_TARIFAS_HISTORICAS`
- `PERM_CONDICIONES_ECONOMICAS_ADMIN`

No renombres esos permisos sin una migración y una razón concreta.

Evaluá como **PROPUESTA**, no como hecho existente:

- `PERM_ALUMNOS_LEER`
- `PERM_ALUMNOS_ADMIN`
- `PERM_INSCRIPCIONES_LEER`
- `PERM_INSCRIPCIONES_ADMIN`
- `PERM_DISCIPLINAS_LEER`
- `PERM_DISCIPLINAS_ADMIN`
- `PERM_PROFESORES_LEER`
- `PERM_PROFESORES_ADMIN`
- `PERM_ASISTENCIAS_LEER`
- `PERM_ASISTENCIAS_REGISTRAR`
- `PERM_PAGOS_LEER`
- `PERM_CAJA_LEER`
- `PERM_STOCK_LEER`
- `PERM_REPORTES_LEER`
- `PERM_REPORTES_EXPORTAR`
- `PERM_CONFIG_LEER`
- `PERM_CONFIG_ADMIN`

No agregues permisos más finos sin demostrar una necesidad de negocio. Si Matrículas/Cargos u Observaciones requieren una decisión propia, registrala antes de inventar un código.

### Roles base a evaluar

- `SUPERADMIN`: capacidades técnicas completas y recuperación; no cuenta diaria.
- `DIRECCION`: negocio, configuración y reportes; seguridad sólo según decisión explícita.
- `SECRETARIA`: alumnos, inscripciones, pagos de registro/lectura, caja de lectura y operación académica; sin anular pagos ni administrar seguridad por defecto.
- `CAJA`: lectura de alumnos/pagos, registrar pagos y consultar caja; egresos sólo si se decide.
- `PROFESOR`: disciplinas, alumnos y asistencia propios; sin finanzas ni acceso global.

La matriz final debe ser explícita y convertirse en tests.

## 7. Etapa 0 — Baseline y documentación

### Objetivo

Crear los 12 `.md`, confirmar hallazgos y dejar el backlog ejecutable antes de modificar código productivo.

### Tareas mínimas

- `E0-001`: verificar Git y AGENTS.
- `E0-002`: ejecutar baseline frontend.
- `E0-003`: ejecutar baseline backend.
- `E0-004`: inventariar rutas, endpoints y permisos.
- `E0-005`: confirmar seeds/bootstrap.
- `E0-006`: confirmar cálculo financiero real.
- `E0-007`: confirmar IDs/búsquedas técnicas y flujos UX.
- `E0-008`: crear y cruzar documentos.

### Comandos mínimos

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend
```

Además:

```powershell
rg -n '@RequestMapping|@(Get|Post|Put|Patch|Delete)Mapping' .\backend\src\main\java\gestudio\controladores .\backend\src\main\java\gestudio\tarifas\api
rg -n 'requestMatchers|hasAuthority|@PreAuthorize|exigirPermiso|PERM_[A-Z0-9_]+' .\backend\src\main\java
rg -n 'path:|routePermissions|requiredPermission|hasPermission|PERMISSIONS\.' .\frontend\src
rg -n -i --glob '*.tsx' --glob '!*.test.tsx' '>\s*ID\s*<|headers=\{\[[^\]]*"ID"|Alumno\s*ID|Cargo\s*ID|Inscripci[oó]n\s*ID|idBusqueda' .\frontend\src
rg -n 'TarifaDisciplinaServicio|CondicionEconomicaServicio|LiquidacionCargoServicio|getValorCuota|getMatricula|costoParticular' .\backend\src\main\java
```

### GATE-0

No se cierra hasta que:

- los 12 documentos existan y estén cruzados;
- baseline esté clasificado;
- matriz RBAC cubra todos los módulos;
- cada P0 tenga tarea y prueba;
- decisiones financieras abiertas estén identificadas;
- `00_INDEX.md` indique `Etapa actual: 1` y `Próxima tarea: E1-001`.

Después de GATE-0, si no hay un bloqueo que requiera decisión, empezá automáticamente Etapa 1. No esperes confirmación entre Etapa 0 y Etapa 1.

## 8. Etapa 1 — Seguridad y RBAC mínimo publicable

### Objetivo

Conseguir un RBAC determinístico desde base limpia, autorización backend granular, semántica 401/403/409 correcta y frontend coherente con la misma matriz.

### Orden obligatorio de tareas

#### `E1-001` — Congelar contrato y constantes

- Confirmar catálogo actual.
- Definir catálogo propuesto mínimo.
- Definir matriz SUPERADMIN/DIRECCION/SECRETARIA/CAJA/PROFESOR.
- Crear constantes backend centralizadas.
- No editar migración hasta que la matriz esté escrita en `02_MATRIZ_RBAC.md`.

#### `E1-002` — Migración productiva RBAC

- Crear una migración forward-only posterior a V5, previsiblemente `V6__rbac_permission_catalog_and_base_roles.sql`.
- Insertar/reconciliar catálogo de permisos.
- Crear o reconciliar roles base.
- Asignar matriz determinística.
- Mantener datos demo fuera de la migración.
- Actualizar tests que hoy exigen cero permisos.
- Probar base limpia y upgrade desde V5.

#### `E1-003` — Bootstrap utilizable

- Asegurar que SUPERADMIN bootstrap tenga rol/matriz válidos.
- Fallar temprano con diagnóstico claro si el catálogo obligatorio está incompleto.
- Probar bootstrap -> login -> perfil -> primer GET operativo.
- Nunca depender de `gestudio_demo_seed_full.sql`.

#### `E1-004` — Semántica de autorización

- Separar excepción de autorización de conflicto de negocio.
- Garantizar 401 sin autenticación.
- Garantizar 403 sin autoridad.
- Mantener 409 para invariantes de negocio.
- Agregar tests de handler y HTTP.

#### `E1-005` — Matchers/endpoints granulares

- Corregir endpoint real de generación manual.
- Proteger por método/path todos los módulos de la matriz.
- Usar `@PreAuthorize` o matchers exactos de forma consistente.
- Mantener controles de servicio en operaciones financieras.
- Eliminar o documentar matchers sin controlador.
- Ningún write sensible debe quedar sólo con `PERM_APP_ACCESO`.

#### `E1-006` — Ownership Profesor

- Determinar usuario -> profesor.
- Limitar consulta/edición a disciplinas y asistencias propias.
- Dirección/Secretaría conservan acceso global según matriz.
- Probar dos profesores y acceso cruzado.
- Si el dominio no permite resolverlo sin decisión, registrar `DEC-OWNERSHIP-001` y bloquear únicamente la habilitación del rol Profesor, no el resto de Etapa 1.

#### `E1-007` — Contrato frontend

- Completar `permissions.ts` con catálogo confirmado.
- Reemplazar strings ad hoc por `PERMISSIONS.*`.
- Corregir Usuarios/Roles.
- Hacer `/unauthorized` accesible a cualquier autenticado.
- Crear `PermissionGate`/`Can` pequeño.
- Filtrar menú, ruta y acción.
- Centralizar metadata ruta/permiso si puede hacerse sin refactor masivo.
- Agregar test que detecte rutas protegidas sin permiso explícito.

#### `E1-008` — Acciones sensibles frontend

Cubrir al menos:

- pagos registrar/anular;
- tarifas/condiciones;
- egresos;
- stock administrar/vender;
- usuarios/roles;
- configuración;
- reportes/exportación;
- altas/ediciones/bajas académicas.

El backend debe seguir negando aunque se fuerce la URL o llamada.

#### `E1-009` — WebSocket/notificaciones

Elegir una sola opción:

1. deshabilitar/ocultar limpiamente para la primera release; o
2. URL por entorno/protocolo, origins explícitos, autenticación de handshake, autorización por destino y aislamiento por usuario.

No dejar un canal a medio abrir.

#### `E1-010` — Suite de seguridad y smoke

- Matriz HTTP parametrizada método/path/permiso.
- 401/403/permitido.
- `authVersion` y roles/permisos inactivos.
- escalamiento/delegación;
- último SUPERADMIN;
- bootstrap limpio;
- ownership;
- contrato de permisos usados/sembrados;
- tests frontend de menú/ruta/acción;
- smoke sin seed demo.

### Archivos esperados de Etapa 1

Revisá nombres reales antes de editar:

- `backend/src/main/resources/db/migration/V6__*.sql`
- `SecurityConfigurations.java`
- `SecurityFilter.java`
- `RbacService.java`
- `TratadorDeErrores.java`
- `SuperadminBootstrapService.java`
- controladores y servicios de todos los módulos
- tests de seguridad, esquema, bootstrap y servicios
- `frontend/src/config/permissions.ts`
- `frontend/src/config/navigation.ts`
- `frontend/src/rutas/routes.ts`
- `frontend/src/rutas/ProtectedRoute.tsx`
- auth context
- páginas con acciones
- tests de rutas, navegación y permisos
- scripts smoke/demo si corresponde

### GATE-1

No cierres Etapa 1 hasta que:

- base limpia migre y bootstrap permita usar la app;
- catálogo y roles sean determinísticos;
- permisos usados existan y estén sembrados;
- endpoint sin token = 401;
- con token sin permiso = 403;
- conflicto real = 409;
- todos los writes tengan permiso explícito;
- menú, ruta y acciones coincidan con backend;
- acceso directo a URL/API no escale privilegios;
- Profesor esté limitado por ownership o no esté habilitado;
- WebSocket esté seguro o deshabilitado;
- validación Backend, Frontend y All estén clasificadas;
- documentos y bitácora estén actualizados.

Al cerrar GATE-1:

1. detenete;
2. no empieces Etapa 1B;
3. mostrame resumen de archivos, migración, permisos, roles, tests y riesgos residuales;
4. pedime exactamente: `¿Autorizás continuar con Etapa 1B — liquidación financiera por vigencia?`.

## 9. Etapa 1B — Liquidación financiera por vigencia

No comenzar sin mi autorización posterior a GATE-1.

### Objetivo

Eliminar la doble fuente de precios y garantizar que tarifas/condiciones vigentes produzcan el cargo correcto y un snapshot auditable.

### Decisiones que deben documentarse antes de implementar

- fecha efectiva para resolver tarifa mensual;
- fecha efectiva para matrícula;
- comportamiento ante ausencia de tarifa;
- prioridad entre tarifa estándar y costo particular;
- reglas de bonificación/condición;
- tratamiento de condiciones históricas;
- compatibilidad/migración de campos legacy;
- versión de fórmula.

Si estas decisiones no están respaldadas por tests o dominio existente, creá `DEC-PRICING-001`, presentá opciones concretas y esperá mi respuesta antes de modificar el cálculo.

### Tareas

- `E1B-001`: mapear cálculo actual y decisiones.
- `E1B-002`: crear/resolver servicio único de liquidación.
- `E1B-003`: integrar mensualidades.
- `E1B-004`: integrar matrículas.
- `E1B-005`: persistir `cargo_liquidaciones` y snapshots en la misma transacción.
- `E1B-006`: retirar o convertir campos legacy/UI duplicada.
- `E1B-007`: probar vigencias, huecos, solapamientos, límites, idempotencia y exactitud monetaria.

### GATE-1B

- tarifa futura no afecta período anterior;
- sí afecta período correspondiente;
- condición vigente aplica sólo en rango;
- cargo conserva snapshot aunque cambie configuración;
- no se duplica liquidación;
- no existe otra ruta de cálculo desde precio legacy;
- UI no muestra dos fuentes de verdad;
- tests PostgreSQL exactos pasan;
- docs actualizados.

Al cerrar, detenerse y solicitar autorización para Etapa 2.

## 10. Etapa 2 — UX operativa crítica

No comenzar sin autorización posterior a GATE-1B.

### Objetivo

Permitir que una secretaria complete los flujos cotidianos sin IDs, contradicciones ni acciones incompletas.

### Orden de tareas

#### `E2-001` — Búsqueda humana de alumnos

- nombre;
- apellido;
- ambos órdenes;
- documento/DNI;
- normalización de mayúsculas/acentos según capacidades actuales;
- sólo los estados que el contexto necesite;
- endpoint de resultado resumido;
- debounce y selección accesible.

#### `E2-002` — Selectores reutilizables

- `AlumnoCombobox`;
- `DisciplinaCombobox`;
- loading/error/empty;
- teclado;
- valor controlado;
- resultado humano;
- IDs sólo internos.

Adoptarlos primero en Pagos, Inscripciones y Asistencias/Reportes.

#### `E2-003` — Eliminar IDs visibles

Revisar:

- Pagos;
- Usuarios;
- Métodos de pago;
- Conceptos;
- Bonificaciones;
- Salones;
- Subconceptos;
- Recargos;
- Caja;
- toasts;
- aria-labels orientadas al operador;
- filenames de exportación.

Cuando haga falta referencia, agregar DTO humano: número de recibo, alumno, concepto, método, fecha u operador.

#### `E2-004` — Alumnos e Inscripciones

- filtros Activos/Inactivos/Todos;
- Dar de baja/Reactivar;
- no ofrecer Editar inválido;
- alumno y disciplina de sólo lectura al editar inscripción;
- explicar invariante;
- Finalizar inscripción con confirmación/fecha;
- acceso rápido Registrar pago/Ver pagos/Condiciones.

#### `E2-005` — Pagos y Caja

- referencia humana de recibo;
- formato ARS consistente;
- estados humanos;
- Anular por permiso;
- origen humano en Caja;
- fecha local Buenos Aires, no `toISOString()` para día operativo;
- Caja abre en Hoy;
- método, alumno/concepto y operador cuando estén disponibles.

#### `E2-006` — Egresos

- motivo/categoría/observación útil;
- método de pago humano;
- estado;
- operador;
- Anular con permiso, motivo e idempotencia;
- historial auditable.

#### `E2-007` — Stock

- Cantidad no editable por formulario general;
- movimientos/ajuste con motivo si el dominio lo permite;
- venta guiada alumno/producto/cantidad/cargo/confirmación;
- reversión e historial;
- permisos `STOCK_ADMIN` y `STOCK_VENDER`.

Si no se completa venta, renombrar alcance a Inventario y no vender la función como terminada.

#### `E2-008` — Asistencias

- Diario como flujo primario;
- PRESENTE/AUSENTE/JUSTIFICADO;
- Marcar todos presentes;
- guardado por lote o autosave confiable;
- indicador Guardando/Guardado/Error;
- debounce real cancelable para observaciones;
- consulta de años/meses pasados;
- navegación Diario/Mensual coherente;
- ownership Profesor.

#### `E2-009` — Usuarios, Roles y Catálogos

- estado visible;
- Desactivar/Reactivar, no “Eliminar” engañoso;
- reglas `sistema/editable` alineadas;
- permisos humanos agrupados por módulo;
- sólo roles/permisos delegables;
- corregir headers Acciones duplicados;
- implementar Recargo o retirar acción;
- reemplazar hard delete por baja lógica donde haya historia.

#### `E2-010` — Tests UX y flujo Secretaría

- corregir los tests preexistentes sin debilitar intención;
- evitar queries singulares cuando desktop/mobile duplican el dato intencionalmente;
- usar el formatter monetario real;
- probar flujo alumno -> inscripción -> cargo -> pago -> caja;
- probar errores y estados vacíos.

### GATE-2

- cero IDs técnicos visibles en flujos operativos;
- búsqueda por nombre/apellido/DNI real;
- ninguna acción conocida termina en rechazo por formulario contradictorio;
- Caja y recibos son humanos;
- Stock/Egresos/Asistencia tienen flujo completo o alcance explícitamente reducido;
- tests frontend verdes;
- backend afectado validado;
- recorrido Secretaría completado;
- docs actualizados.

Al cerrar, detenerse y solicitar autorización para Etapa 3.

## 11. Etapa 3 — Componentes y contratos reutilizables

No comenzar sin autorización posterior a GATE-2.

### Objetivo

Reducir duplicación sin sobrediseñar.

### Candidatos permitidos

- `PermissionGate`/`Can`;
- `AlumnoCombobox`;
- `DisciplinaCombobox`;
- `ConfirmActionDialog`;
- `formatMoney`;
- `formatLocalDate`;
- etiquetas de estado;
- `getApiErrorMessage`;
- metadata única de ruta/permiso/navegación;
- helpers de test para tabla responsive.

### No hacer

- CRUD universal;
- formulario universal;
- megatabla con reglas de todos los módulos;
- framework propio de permisos;
- refactor visual completo sin beneficio operativo.

### Tareas

- `E3-001`: medir duplicación restante.
- `E3-002`: consolidar formatters y mensajes.
- `E3-003`: consolidar confirmaciones accesibles.
- `E3-004`: consolidar rutas/permisos/navegación.
- `E3-005`: remover implementaciones duplicadas ya migradas.
- `E3-006`: contrato automatizado de rutas y permisos.
- `E3-007`: limpiar código muerto confirmado y logs de datos.

### GATE-3

- no hay strings de permisos ad hoc;
- rutas y navegación no divergen;
- selectores no están triplicados;
- formatos consistentes;
- componentes accesibles y testeados;
- no se introdujo abstracción sin consumidores reales;
- suite completa pasa;
- docs actualizados.

Al cerrar, detenerse y solicitar autorización para Etapa 4.

## 12. Etapa 4 — Refinamiento, demo comercial y publicación

No comenzar sin autorización posterior a GATE-3.

### Objetivo

Hacer que el producto explique por sí mismo qué requiere atención y completar un recorrido comercial confiable.

### Tareas

- `E4-001`: Dashboard operativo con 3–5 señales relevantes por permiso.
- `E4-002`: hub único de Reportes y exportación por permiso.
- `E4-003`: decidir/integrar o retirar Observaciones.
- `E4-004`: empty states con siguiente acción.
- `E4-005`: responsive PC/celular y accesibilidad teclado/foco.
- `E4-006`: dataset demo separado de RBAC productivo.
- `E4-007`: E2E Dirección, Secretaría, Caja y Profesor si está habilitado.
- `E4-008`: smoke base limpia.
- `E4-009`: checklist staging/producción, backup, observabilidad y rollback.
- `E4-010`: informe final de release.

### Dashboard esperado

Priorizar:

- clases de hoy;
- pagos/deuda que requieren atención;
- caja de hoy;
- cumpleaños;
- accesos rápidos según permiso.

No convertirlo en un sistema de widgets configurable en esta etapa.

### GATE-4

- demo de 10–15 minutos sin SQL manual;
- sin IDs técnicos;
- sin acciones no-op;
- sin permisos sorpresa;
- tarifas/cargos exactos;
- roles demuestran separación real;
- uso correcto en PC y celular;
- base limpia y upgrade probados;
- validación All verde;
- checklist de release completo;
- riesgos residuales explícitos.

## 13. Validación obligatoria

### Antes de cambios

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend
```

### Durante cada tarea

Ejecutá el test más cercano al cambio. Ejemplos:

```powershell
Push-Location .\frontend
npm test
npm run lint
npm run build
Pop-Location
```

```powershell
Push-Location .\backend
.\mvnw.cmd test
Pop-Location
```

Usá `-Dtest=...` para aislar mientras desarrollás, pero el gate exige suite amplia.

### Al cerrar cada etapa

```powershell
git status --short --branch
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
```

Después de Etapa 1:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
```

Debe probarse con una base descartable recién migrada y sin seed demo previo.

## 14. Formato de cada actualización hacia mí

Cada vez que informes progreso usá este formato breve:

### Estado

- Etapa:
- Tarea:
- Resultado:
- Gate:

### Cambios

- archivos modificados;
- comportamiento anterior;
- comportamiento nuevo.

### Evidencia

- comandos;
- tests pasados/fallidos;
- qué quedó no verificado.

### Riesgos/bloqueos

- riesgos nuevos;
- decisiones pendientes;
- cambios del usuario preservados.

### Próximo paso

- una única tarea concreta.

No uses “todo está bien” sin evidencia. No vuelques logs extensos en la respuesta.

## 15. Política ante fallos

- Si un test que pasaba comienza a fallar por tu cambio, corregilo antes de continuar.
- Si un test ya fallaba, documentalo como baseline y corregilo en la etapa correspondiente.
- Si la prueba revela un defecto de diseño, no adaptes el test para ocultarlo.
- Si Docker, Java, Node, Maven o red bloquean una validación, agotá comprobaciones seguras, documentá `NO_VERIFICADO` y dejá el comando exacto para repetir.
- Si una decisión cambia importes, permisos, ownership o borrado de datos, no la supongas: registrá opciones y pedime confirmación.
- Si un archivo tiene cambios ajenos, no lo reemplaces entero ni lo reviertas.

## 16. Definición global de terminado

Gestudio no está terminado sólo porque compila.

Debe cumplirse:

1. Base limpia usable sin SQL manual.
2. Roles y permisos determinísticos.
3. 401/403/409 correctos.
4. Backend granular y frontend coherente.
5. Ownership de Profesor o rol no habilitado.
6. Tarifa/condición vigente gobierna cargos con snapshot.
7. Secretaría completa el circuito sin IDs.
8. Caja, pagos y egresos son auditables humanamente.
9. Acciones visibles funcionan y respetan permisos.
10. Tests, build, lint, Flyway, Testcontainers y smoke pasan.
11. Demo PC/celular completada.
12. Documentación y bitácora reflejan exactamente el estado real.

## 17. Qué hacer en esta primera ejecución

Procedé ahora en este orden:

1. verificá Git, AGENTS y baseline;
2. inspeccioná el HEAD real;
3. creá los 12 `.md` completos;
4. ejecutá y cerrá Etapa 0;
5. si no hay bloqueo material, comenzá Etapa 1 automáticamente;
6. trabajá Etapa 1 hasta cerrar GATE-1 o encontrar una decisión que realmente requiera mi autoridad;
7. actualizá los `.md` después de cada tarea;
8. detenete al cerrar GATE-1;
9. no comiences Etapa 1B sin mi autorización.

Tu primera actualización debe informar baseline y documentos que vas a crear. Tu última actualización de esta ejecución debe dejar claro si GATE-1 quedó cerrado, qué evidencia existe y cuál es la única autorización necesaria para continuar.

## FIN DEL PROMPT

---

## Mensajes cortos para continuar después

Una vez que Codex cierre cada gate, usar uno de estos mensajes:

### Continuar con liquidación financiera

```text
Autorizo continuar con Etapa 1B — liquidación financiera por vigencia. Leé primero los documentos de docs/codex/gestudio-release-hardening, verificá que GATE-1 siga cerrado y trabajá únicamente Etapa 1B. No avances a Etapa 2 sin cerrar GATE-1B y pedirme autorización.
```

### Continuar con UX operativa

```text
Autorizo continuar con Etapa 2 — UX operativa crítica. Leé la documentación y bitácora, verificá que GATE-1B siga cerrado y trabajá únicamente Etapa 2. No avances a Etapa 3 sin cerrar GATE-2 y pedirme autorización.
```

### Continuar con componentes y contratos

```text
Autorizo continuar con Etapa 3 — componentes y contratos reutilizables. Verificá el gate anterior, evitá abstracciones prematuras y no avances a Etapa 4 sin cerrar GATE-3 y pedirme autorización.
```

### Continuar con demo/publicación

```text
Autorizo continuar con Etapa 4 — demo comercial y publicación. Verificá GATE-3, completá el checklist de release y no declares listo el producto sin evidencia de la secuencia de demo, validación All, migración limpia/upgrade y matriz de permisos.
```
