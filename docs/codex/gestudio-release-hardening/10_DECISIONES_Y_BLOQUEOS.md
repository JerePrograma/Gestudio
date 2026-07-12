# Decisiones y bloqueos

Última revisión: 2026-07-11 (America/Argentina/Buenos_Aires).

`VALIDADO`: el baseline de este work es `407e1cbcc277b4b6c385cddface2862259e87036`, alineado con `origin/main` y con árbol limpio al inicio. La consigna del 2026-07-11 autorizó únicamente el primer bloque real sobre el contrato actual de Usuarios/Roles; no aprobó la matriz propuesta, una migración ni una mutación externa. La única tarea `IN_PROGRESS` sigue siendo `E1-001`.

Una recomendación o un fallback seguro no equivale a aprobación. `PENDING` significa que no existe decisión confirmada; `TOMADA` sólo se usa cuando la consigna, el repositorio y la evidencia ya fijan el contrato.

## Resumen

| ID | Estado | Confirmación | Efecto inmediato |
|---|---|---|---|
| `DEC-RBAC-001` | `PENDING`; subconjunto actual validado | Sí | Usuarios/Roles pueden usar los permisos actuales ya definidos; `BLK-001` sigue bloqueando `E1-002` y la matriz comercial. |
| `DEC-DB-001` | `TOMADA` / `VALIDADO` | No, salvo excepción | V1-V5 no se reescriben; el próximo cambio aprobado es forward-only. |
| `DEC-OWNERSHIP-001` | `PENDING` / `NO_VERIFICADO` | Sí | `PROFESOR` permanece inhabilitado; no bloquea el resto de Etapa 1. |
| `DEC-WS-001` | `PENDING` | Sí | Debe resolverse antes de `E1-009`/GATE-1; no bloquea `E1-002`. |
| `DEC-PRICING-001` | `PENDING` / etapa no autorizada | Sí, después de GATE-1 | No se modifica cálculo financiero ni se inicia Etapa 1B. |
| `DEC-OBS-001` | `PENDING` / `DEFERRED` | Sí para incluir la función | Observaciones queda fuera de la release mientras no exista permiso y ownership aprobados. |
| `DEC-ENV-001` | local `TOMADA`; externo `PENDING` | Sí para staging/producción | Setup sin Docker automático; staging y producción siguen sin autorización. |
| `DEC-RELEASE-001` | `TOMADA`: `NO-GO` | Sí para cambiar a `GO` | No se publica ni se muta un ambiente externo. |

## Decisiones

### DEC-RBAC-001 — Matriz base de roles y permisos

- **ID:** `DEC-RBAC-001`.
- **Contexto:** V5 creó `permisos`, `rol_permisos` y `usuario_roles`, pero no sembró catálogo ni asignaciones. El código usa 15 permisos actuales; Flyway siembra cero y el seed demo siembra 14, omitiendo `PERM_TARIFAS_HISTORICAS`. El fallback `/api/**` exige sólo `PERM_APP_ACCESO`, por lo que una base limpia puede autenticar y no operar, mientras writes sensibles carecen de separación suficiente. La propuesta completa está en [02_MATRIZ_RBAC.md](./02_MATRIZ_RBAC.md).
- **Opciones:**
  1. conservar `PERM_APP_ACCESO` y depender del seed demo;
  2. persistir mediante la siguiente migración forward-only el catálogo real más los 17 permisos mínimos propuestos y una matriz determinística para `SUPERADMIN`, `DIRECCION`, `SECRETARIA`, `CAJA` y `PROFESOR`;
  3. otorgar permisos amplios a todos los roles para evitar denegaciones.
- **Recomendación:** opción 2. Mantener los 15 códigos actuales, sumar sólo los 17 permisos funcionales documentados, conservar `ADMINISTRADOR` como compatibilidad sin renombrarlo ni borrarlo automáticamente, y aplicar estas restricciones: `DIRECCION` con usuarios y auditoría pero sin administración de roles por defecto; `CAJA` sin egresos por defecto; venta de stock de Caja/Secretaría sólo si se confirma; `PROFESOR` sólo con alcance propio después de `DEC-OWNERSHIP-001`; Observaciones sin permiso inventado y fuera de alcance según `DEC-OBS-001`.
- **Decisión tomada / estado:** `PENDING` para la matriz base. La consigna del 2026-07-11 sí autorizó el subconjunto que conserva los códigos actuales `PERM_USUARIOS_ADMIN` y `PERM_ROLES_ADMIN`, mantiene `ADMINISTRADOR` sin mutación y no agrega roles ni asignaciones. No hay aprobación de la transición de `ADMINISTRADOR`, del alcance de seguridad de `DIRECCION`, de egresos/venta de stock para `CAJA`/`SECRETARIA` ni de la habilitación de `PROFESOR`. `E1-001` permanece `IN_PROGRESS` y [BLK-001](#blk-001--falta-de-autoridad-para-la-matriz-rbac) impide iniciar `E1-002`.
- **Consecuencias:** se permiten correcciones y pruebas que alineen frontend/backend con los 15 códigos ya existentes sin cambiar autoridad persistida. No crear V6, permisos, roles, asignaciones, bootstrap o matchers de la matriz propuesta hasta confirmar o corregirla. Una aprobación habilita cerrar `E1-001`, marcar sólo `E1-002` como `IN_PROGRESS`, sembrar/reconciliar de forma determinística y probar base limpia + upgrade desde V5.
- **Fecha:** 2026-07-11 (alcance parcial); propuesta general pendiente desde 2026-07-10.
- **Requiere confirmación:** **Sí**, explícita del usuario; silencio o aprobación de este documento no cuentan.

### DEC-DB-001 — Cadena Flyway activa y dirección V6

- **ID:** `DEC-DB-001`.
- **Contexto:** el directorio activo contiene V1 a V5; V1 es el baseline canónico y V5 puede estar aplicada. El código y los scripts operan esa cadena, aunque `AGENTS.md` conserva texto anterior a V2. V5 es estructural y declara expresamente que no siembra catálogo RBAC.
- **Opciones:** reescribir V5; usar una versión artificial como V900 o el seed demo; o continuar desde la siguiente versión libre después de verificar el historial real.
- **Recomendación:** continuar forward-only. Para RBAC la siguiente versión prevista es V6; debe volver a verificarse inmediatamente antes de crearla. Una corrección posterior a una migración aplicada también se hace con otra versión forward-only.
- **Decisión tomada / estado:** `TOMADA` / `VALIDADO`: V1-V5 forman la cadena activa, V1 y V5 no se reescriben y `scripts/gestudio_demo_seed_full.sql` no sustituye configuración productiva.
- **Consecuencias:** todo cambio de esquema debe incluir precondiciones, reconciliación, verificación, base PostgreSQL limpia y upgrade desde el estado anterior. Etapa 1B usaría la siguiente versión libre posterior a la de RBAC, previsiblemente V7, sólo si realmente cambia esquema. Los datos históricos ambiguos se reportan y bloquean; no se normalizan ni borran automáticamente.
- **Fecha:** 2026-07-10.
- **Requiere confirmación:** **No** para cumplir este contrato ya impuesto; cualquier excepción sí requiere una nueva confirmación explícita.

### DEC-OWNERSHIP-001 — Ownership del rol Profesor

- **ID:** `DEC-OWNERSHIP-001`.
- **Contexto:** V1 y `Profesor.java` modelan una relación uno-a-uno opcional `profesores.usuario_id -> usuarios.id`, y las disciplinas referencian profesor. Sin embargo, los controladores y servicios de profesores, disciplinas, alumnos y asistencias aceptan IDs del request y no derivan el profesor desde el principal autenticado. No hay prueba de dos profesores con acceso cruzado denegado.
- **Opciones:** acceso global para `PROFESOR`; ownership backend derivado de `principal.id -> profesores.usuario_id -> disciplinas -> inscripciones/asistencias`; o mantener el rol sin habilitar.
- **Recomendación:** si el rol se ofrece, usar la relación persistida como raíz de ownership, filtrar consultas en repositorio/servicio y negar IDs ajenos; Dirección/Secretaría conservan el alcance global que apruebe `DEC-RBAC-001`. Si alguna relación o regla de alumnos compartidos no puede expresarse y probarse, mantener `PROFESOR` inactivo.
- **Decisión tomada / estado:** `PENDING` / `NO_VERIFICADO`. El fallback seguro vigente es no habilitar el rol. Esto bloquea únicamente su habilitación, no `E1-002` ni el resto de Etapa 1.
- **Consecuencias:** `E1-006` debe caracterizar usuario-profesor, disciplinas, alumnos y asistencia; agregar pruebas con dos profesores y acceso directo/API cruzado. No se concede acceso global para evitar implementar ownership.
- **Fecha:** 2026-07-10.
- **Requiere confirmación:** **Sí**, sobre el alcance funcional; la implementación además debe quedar demostrada por tests antes de habilitar el rol.

### DEC-WS-001 — WebSocket y notificaciones de la primera release

- **ID:** `DEC-WS-001`.
- **Contexto:** `WebSocketConfig` habilita STOMP/SockJS con origen `*`; el backend publica a `/topic/notificaciones`, el controller de marcar leída es un placeholder y no hay autenticación/autorización por handshake, destino o usuario. El hook frontend fija `ws://localhost:8080/ws` y no tiene consumidores productivos observados. La UI activa obtiene cumpleaños por REST, por lo que no depende de ese hook.
- **Opciones:** deshabilitar/ocultar completamente el canal STOMP para la primera release; o conservarlo con URL por entorno/protocolo, origins explícitos, handshake autenticado, autorización por destino y aislamiento por usuario.
- **Recomendación:** deshabilitar STOMP para la primera release y conservar el flujo REST existente. Sólo elegir la segunda opción si existe una necesidad comercial confirmada y se implementa el contrato completo.
- **Decisión tomada / estado:** `PENDING`; no hay aprobación para retirar ni para terminar tiempo real. El estado actual no es publicable y no se acepta como opción intermedia.
- **Consecuencias:** `E1-009` y GATE-1 no cierran hasta elegir, implementar y probar una opción. La decisión no bloquea `E1-002` y no autoriza agregar infraestructura.
- **Fecha:** 2026-07-10.
- **Requiere confirmación:** **Sí**, antes de ejecutar `E1-009`.

### DEC-PRICING-001 — Contrato de liquidación por vigencia

- **ID:** `DEC-PRICING-001`.
- **Contexto:** tarifas y condiciones efectivas existen, pero mensualidades y matrículas siguen leyendo valores legacy; `LiquidacionCargoServicio` guarda snapshots pero no tiene caller productivo. Cambiar este contrato altera importes y no está autorizado antes de cerrar GATE-1 y habilitar Etapa 1B.
- **Opciones:**

  | Tema | Opciones | Recomendación pendiente |
  |---|---|---|
  | Fecha mensual | inicio del período / generación / vencimiento | primer día del `YearMonth` |
  | Fecha matrícula | 1 de enero / emisión / vencimiento | 1 de enero del año |
  | Sin tarifa | fallback legacy / cero / rechazar | rechazar con error de historia faltante |
  | Prioridad | tarifa / particular / condición y luego tarifa | `costoParticular` efectivo no nulo; si no, tarifa efectiva |
  | Bonificación | legacy / snapshot / combinación | sólo snapshots de la condición efectiva |
  | Historia | última fila `<= fecha` / rango explícito / actual | última fila `<= fecha` |
  | Campos legacy | borrar / seguir calculando / sólo compatibilidad | conservar físicamente, retirar de cálculo y edición operativa |
  | Fórmula | sin versión / entero / motor configurable | `formula_version = 1` hasta cambiar semántica |
  | Varias disciplinas en matrícula | máximo / suma / una por disciplina / política institucional | requiere definición institucional; el máximo actual no prueba intención |

- **Recomendación:** aprobar o corregir el conjunto completo como un solo contrato antes de código; no aceptar fallbacks parciales.
- **Decisión tomada / estado:** `PENDING`. Etapa 1B y `E1B-001` no están autorizadas; no se tomó ninguna decisión de importe, prioridad, fecha ni matrícula multidisciplina.
- **Consecuencias:** no cambiar `MensualidadServicio`, `MatriculaServicio`, campos legacy ni snapshots. Después de GATE-1 se requiere primero autorización de Etapa 1B, caracterización ejecutable y confirmación de esta decisión; recién entonces puede existir una única ruta transaccional de cálculo.
- **Fecha:** 2026-07-10.
- **Requiere confirmación:** **Sí**, explícita y posterior a GATE-1.

### DEC-OBS-001 — Alcance de Observaciones de profesores

- **ID:** `DEC-OBS-001`.
- **Contexto:** existen tabla, entidad, controller, servicio, API y componente frontend, pero no hay ruta productiva ni permiso/ownership dedicado. El controller permite altas, bajas y lecturas globales bajo el fallback general; la API frontend ofrece un `PUT` que el controller no publica. Integrar sólo la pantalla expondría notas potencialmente privadas con un contrato incompleto.
- **Opciones:** completar ruta, permiso, ownership, contratos y tests; excluir/deshabilitar la función en la primera release; o eliminar datos/código.
- **Recomendación:** excluirla de la primera release y negar/ocultar su superficie hasta que exista necesidad comercial. No inventar un permiso ni borrar datos/código durante Etapa 1; `E4-003` puede reabrir la decisión.
- **Decisión tomada / estado:** `PENDING` / `DEFERRED`. No existe aprobación para ofrecer Observaciones; la matriz RBAC la deja fuera y no crea un código de permiso.
- **Consecuencias:** ningún menú o recorrido comercial debe prometerla. La protección de Etapa 1 no puede considerar autorizado el endpoint por el solo `PERM_APP_ACCESO`; para incluirla se exige ownership propio/global explícito y tests 401/403/permitido.
- **Fecha:** 2026-07-10.
- **Requiere confirmación:** **Sí** para incluirla en la release; mientras no exista, aplica la exclusión segura.

### DEC-ENV-001 — Contrato de entorno y mutaciones externas

- **ID:** `DEC-ENV-001`.
- **Contexto:** `scripts/codex/setup.ps1` usa Maven Wrapper, exige lockfile y `npm ci`, resuelve dependencias y no inicia Docker; `scripts/codex/validate.ps1` concentra validaciones. `.codex/environments/environment.toml` es autogenerado y diverge: exige Maven global, admite fallback `npm install` y omite tests en algunas acciones. El Compose actual usa puertos configurables y no fija `container_name`, pero Compose/perfil prod aún publican `JWT_*_TOKEN_HOURS` mientras `JwtProperties` consume `JWT_*_TOKEN_TTL`. No se definieron ambiente, dominio, TLS, responsables, datos, ventana, backup ni rollback externos.
- **Opciones:** editar manualmente el archivo autogenerado y usarlo como fuente; mantener `scripts/codex` como contrato y regenerar `.codex` sólo por el mecanismo autorizado; o iniciar Docker/servicios automáticamente durante setup.
- **Recomendación:** usar los scripts versionados como fuente de verdad, no editar manualmente `.codex`, mantener Docker como acción consciente y corregir/probar la configuración de JWT/URLs antes de staging. Cada entorno externo requiere autoridad y datos propios.
- **Decisión tomada / estado:** local `TOMADA`; staging/producción `PENDING` / `NO-GO`. No hay autorización de despliegue ni de acceso a datos reales.
- **Consecuencias:** el setup no demuestra salud del repositorio y no levanta servicios. `E4-009` debe reconciliar configuración, ejecutar Docker limpio, backup/restore y rollback; no se usa `localhost:5432` para pruebas destructivas.
- **Fecha:** 2026-07-10.
- **Requiere confirmación:** **No** para el contrato local ya vigente; **sí** para regenerar configuración administrada si exige autoridad externa y para cualquier staging/producción.

### DEC-RELEASE-001 — Estado de salida

- **ID:** `DEC-RELEASE-001`.
- **Contexto:** GATE-1 sigue abierto, Etapas 1B-4 no están autorizadas, la suite frontend completa está roja y no existe evidencia de smoke limpio, demo por rol, backup/restore ni rollback.
- **Opciones:** declarar `GO`; aceptar un `GO` condicionado sin cerrar gates; o conservar `NO-GO` hasta evidencia y autoridad completas.
- **Recomendación:** conservar `NO-GO`.
- **Decisión tomada / estado:** `TOMADA`: demo interna, demo comercial, staging y producción están en `NO-GO`; son cuatro decisiones distintas y secuenciales.
- **Consecuencias:** un build, test o smoke aislado no autoriza publicar. Cambiar el estado exige actualizar [00_INDEX.md](./00_INDEX.md), [09_BITACORA_IMPLEMENTACION.md](./09_BITACORA_IMPLEMENTACION.md) y [11_CHECKLIST_RELEASE.md](./11_CHECKLIST_RELEASE.md) con evidencia fechada.
- **Fecha:** 2026-07-10.
- **Requiere confirmación:** **No** para mantener `NO-GO`; **sí** para cada avance y mutación externa.

## Bloqueos

### BLK-001 — Falta de autoridad para la matriz RBAC

- **ID:** `BLK-001`.
- **Síntoma:** `E1-001` no puede cerrarse y `E1-002` no puede comenzar; una base limpia continúa sin catálogo operativo determinístico.
- **Causa:** `DEC-RBAC-001` define una propuesta que cambia autoridad persistida, pero el usuario aún no confirmó la matriz ni sus puntos sensibles.
- **Intentos seguros / evidencia:** se inventariaron permisos usados/sembrados, matchers, rutas, guards, roles y huecos; V5, schema tests, bootstrap y seed demo fueron leídos. El subconjunto autorizado corrigió Usuarios/Roles, `/unauthorized` y el prefijo reservado `ROLE_`; sus suites focalizadas terminaron frontend 8/8 y backend 29/29. No se creó migración, permiso, rol ni asignación.
- **Autoridad o dato necesario:** respuesta explícita que apruebe o corrija `DEC-RBAC-001`, incluyendo `ADMINISTRADOR`, seguridad de `DIRECCION`, egresos/venta de stock y la condición de habilitación de `PROFESOR`.
- **Tarea afectada:** bloquea `E1-002`; mantiene `E1-001` como única tarea `IN_PROGRESS`.
- **Condición de cierre:** registrar la respuesta en esta decisión y en la bitácora, actualizar primero [02_MATRIZ_RBAC.md](./02_MATRIZ_RBAC.md) si hubo correcciones, cerrar `E1-001` y recién entonces marcar sólo `E1-002` como `IN_PROGRESS`.

### BLK-002 — Suite frontend completa roja

- **ID:** `BLK-002`.
- **Síntoma:** `npm test` terminó 33/36 en el baseline y 36/39 después de agregar tres pruebas RBAC verdes; GATE-2 y la salida de release no pueden considerarse verdes.
- **Causa:** una expectativa singular de Alumnos no contempla las representaciones desktop/mobile simultáneas del DOM y dos expectativas de Pagos usan `$ 100.50` en vez del formatter real `$ 100,50`. Son fallos preexistentes clasificados, no introducidos por este bloque RBAC.
- **Intentos seguros / evidencia:** se ejecutó la validación Frontend; lint y build pasaron, se aislaron los tres casos y no se debilitaron las pruebas.
- **Autoridad o dato necesario:** no falta información para reproducirlos; su corrección pertenece a `E2-010` y requiere respetar la secuencia/autorización de Etapa 2.
- **Tarea afectada:** `E2-010`, GATE-2, demo y release; no bloquea la tarea actual `E1-001`.
- **Condición de cierre:** corregir queries/expectativas conservando intención, ejecutar `npm test`, `npm run lint`, `npm run build` y registrar resultados completos verdes.

### BLK-003 — Ambiente externo y operación de release no definidos

- **ID:** `BLK-003`.
- **Síntoma:** staging y producción permanecen `NO-GO`; no se pueden ejecutar de forma segura despliegue, migración, backup/restore o rollback externos.
- **Causa:** faltan ambiente, dominio/TLS, responsables, datos permitidos, ventana, secretos, política de backup, artefacto anterior y criterio de abortar; además existe drift de variables JWT entre Compose/perfil prod y `JwtProperties`.
- **Intentos seguros / evidencia:** se inspeccionaron Compose, perfiles, scripts, configuración frontend y checklist. No se iniciaron contenedores, no se leyeron secretos y no se tocó una base real.
- **Autoridad o dato necesario:** responsable autorizado debe identificar el ambiente y entregar por canal externo los valores/secretos, ventana y autorización; operaciones debe aceptar backup, restore y rollback.
- **Tarea afectada:** `E4-009` y gates de staging/producción; no bloquea Etapa 1.
- **Condición de cierre:** configuración reconciliada y validada, Docker/health/smoke verdes, backup restaurado en destino aislado, rollback ensayado y autorización fechada en bitácora.

## Próxima acción única

Solicitar confirmación o corrección de `DEC-RBAC-001`. El bloque actual Usuarios/Roles queda cerrado sin ampliar autoridad, pero no habilita `E1-002`, Etapa 1B ni ninguna decisión diferida. Al cambiar un estado, mantener exactamente una tarea `IN_PROGRESS` y sincronizar índice, matriz, bitácora y checklist.
