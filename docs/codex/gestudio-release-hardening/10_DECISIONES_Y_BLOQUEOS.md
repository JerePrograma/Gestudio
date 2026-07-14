# Decisiones y bloqueos

Última revisión: 2026-07-14 (America/Argentina/Buenos_Aires).

`VALIDADO`: este work partió de `feat/rbac-production-hardening` en `f6493a3b1b7988a626c0742fe88ce75c2f1c4ee5`, derivada de `fix/ci-frontend-baseline`, con árbol limpio y `origin/main` en `644e044b26438516ea093513ca5651ce72fb3fb3`. La consigna del 2026-07-14 resolvió RBAC, ownership, WebSocket, Observaciones y liquidación. GATE-1 está cerrado localmente; commits, PR/checks y merge remotos siguen pendientes. Las etapas siguientes continúan condicionadas al merge verde de cada PR anterior.

Una recomendación o un fallback seguro no equivale a aprobación. `PENDING` significa que no existe decisión confirmada; `TOMADA` sólo se usa cuando la consigna, el repositorio y la evidencia ya fijan el contrato.

## Resumen

| ID | Estado | Confirmación | Efecto inmediato |
|---|---|---|---|
| `DEC-RBAC-001` | `TOMADA` | No | Catálogo cerrado de 32 permisos y matrices base exactas; `BLK-001` queda cerrado. |
| `DEC-DB-001` | `TOMADA` / `VALIDADO` | No, salvo excepción | V1–V5 permanecen inmutables; V6 RBAC es forward-only y una corrección futura exige otra migración. |
| `DEC-OWNERSHIP-001` | `TOMADA` / `DEFERRED` | No | `PROFESOR` queda inactivo, sin permisos, sin UI y no asignable hasta demostrar ownership cruzado. |
| `DEC-WS-001` | `TOMADA` | No | STOMP se deshabilita; la primera release usa REST/email. |
| `DEC-PRICING-001` | `TOMADA`; ejecución condicionada | No | Contrato financiero cerrado; Etapa 1B sólo comienza desde `main` después del merge RBAC verde. |
| `DEC-OBS-001` | `TOMADA` / `DEFERRED` | No para excluir | Observaciones queda sin superficie activa y sus datos históricos se conservan. |
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
- **Decisión tomada / estado:** `TOMADA`. Se conservan los 15 códigos actuales y se agregan exactamente los 17 aprobados, para un total de 32. `SUPERADMIN` recibe 32; `DIRECCION` y el legacy `ADMINISTRADOR` reciben los mismos 31, todos salvo `PERM_ROLES_ADMIN`; `SECRETARIA` recibe exactamente 17; `CAJA`, exactamente 8; `PROFESOR` queda inactivo y sin permisos. No hay bypass por rol, transformación automática de usuarios ni permisos fuera del catálogo.
- **Consecuencias:** V6 puede reconciliar exclusivamente roles base y permisos canónicos por código, preservando IDs, usuarios, roles personalizados y asignaciones no canónicas. Backend y frontend deben exigir `PERM_APP_ACCESO` junto con el permiso funcional y negar cualquier `/api/**` no inventariada.
- **Fecha:** 2026-07-14.
- **Requiere confirmación:** **No**; contrato aprobado por la consigna del 2026-07-14.

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
- **Decisión tomada / estado:** `TOMADA` / `DEFERRED`. Primera release: rol presente, `activo=false`, sin permisos operativos, no asignable desde UI y sin rutas visibles.
- **Consecuencias:** no se concede acceso global. Sólo podrá habilitarse después de probar `principal -> usuario -> profesor -> disciplinas -> alumnos/asistencias` con dos profesores y acceso cruzado denegado.
- **Fecha:** 2026-07-14.
- **Requiere confirmación:** **No** para mantenerlo deshabilitado; habilitarlo exige nueva evidencia y decisión.

### DEC-WS-001 — WebSocket y notificaciones de la primera release

- **ID:** `DEC-WS-001`.
- **Contexto:** `WebSocketConfig` habilita STOMP/SockJS con origen `*`; el backend publica a `/topic/notificaciones`, el controller de marcar leída es un placeholder y no hay autenticación/autorización por handshake, destino o usuario. El hook frontend fija `ws://localhost:8080/ws` y no tiene consumidores productivos observados. La UI activa obtiene cumpleaños por REST, por lo que no depende de ese hook.
- **Opciones:** deshabilitar/ocultar completamente el canal STOMP para la primera release; o conservarlo con URL por entorno/protocolo, origins explícitos, handshake autenticado, autorización por destino y aislamiento por usuario.
- **Recomendación:** deshabilitar STOMP para la primera release y conservar el flujo REST existente. Sólo elegir la segunda opción si existe una necesidad comercial confirmada y se implementa el contrato completo.
- **Decisión tomada / estado:** `TOMADA`: STOMP queda deshabilitado en la primera release; notificaciones se limitan a REST/email.
- **Consecuencias:** se retiran el endpoint productivo, handshake anónimo/origin `*`, publicación STOMP y caller frontend sin uso. No se agrega infraestructura alternativa.
- **Fecha:** 2026-07-14.
- **Requiere confirmación:** **No** para deshabilitarlo; reintroducir tiempo real requiere un contrato de seguridad nuevo.

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
- **Decisión tomada / estado:** `TOMADA`. Fecha efectiva de mensualidad: primer día del `YearMonth`; matrícula: 1 de enero; sin tarifa: rechazo; prioridad: costo particular efectivo no nulo y, si no, tarifa efectiva; bonificación: snapshots de condición efectiva; historia: última fila `vigenteDesde <= fecha`; legacy: sólo compatibilidad física; `formula_version=1`; matrícula multidisciplina: máximo importe efectivo entre disciplinas activas.
- **Consecuencias:** la implementación se difiere hasta que RBAC esté integrado y `feat/financial-integrity-v1` nazca del `main` actualizado. Debe comenzar con caracterización y mantener cargo más `cargo_liquidaciones` atómicos, idempotentes y probados en PostgreSQL.
- **Fecha:** 2026-07-14.
- **Requiere confirmación:** **No** para el contrato; el gate de rama/merge sigue siendo obligatorio.

### DEC-OBS-001 — Alcance de Observaciones de profesores

- **ID:** `DEC-OBS-001`.
- **Contexto:** existen tabla, entidad, controller, servicio, API y componente frontend, pero no hay ruta productiva ni permiso/ownership dedicado. El controller permite altas, bajas y lecturas globales bajo el fallback general; la API frontend ofrece un `PUT` que el controller no publica. Integrar sólo la pantalla expondría notas potencialmente privadas con un contrato incompleto.
- **Opciones:** completar ruta, permiso, ownership, contratos y tests; excluir/deshabilitar la función en la primera release; o eliminar datos/código.
- **Recomendación:** excluirla de la primera release y negar/ocultar su superficie hasta que exista necesidad comercial. No inventar un permiso ni borrar datos/código durante Etapa 1; `E4-003` puede reabrir la decisión.
- **Decisión tomada / estado:** `TOMADA` / `DEFERRED`. Observaciones queda fuera de alcance y sin superficie activa.
- **Consecuencias:** se niegan endpoints, rutas y botones; se retira el caller frontend muerto y se conservan tabla, entidad y datos históricos. Incluirla luego exige permiso y ownership explícitos con pruebas.
- **Fecha:** 2026-07-14.
- **Requiere confirmación:** **No** para excluirla; **sí** para reactivarla.

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
- **Contexto:** GATE-1 está verde localmente, pero faltan PR/checks/merge. Partes B, C y D no comenzaron y no existe evidencia de staging, recorridos finales por rol, backup/restore ni rollback.
- **Opciones:** declarar `GO`; aceptar un `GO` condicionado sin cerrar gates; o conservar `NO-GO` hasta evidencia y autoridad completas.
- **Recomendación:** conservar `NO-GO`.
- **Decisión tomada / estado:** `TOMADA`: demo interna, demo comercial, staging y producción están en `NO-GO`; son cuatro decisiones distintas y secuenciales.
- **Consecuencias:** un build, test o smoke aislado no autoriza publicar. Cambiar el estado exige actualizar [00_INDEX.md](./00_INDEX.md), [09_BITACORA_IMPLEMENTACION.md](./09_BITACORA_IMPLEMENTACION.md) y [11_CHECKLIST_RELEASE.md](./11_CHECKLIST_RELEASE.md) con evidencia fechada.
- **Fecha:** 2026-07-10.
- **Requiere confirmación:** **No** para mantener `NO-GO`; **sí** para cada avance y mutación externa.

## Bloqueos

### BLK-001 — Falta de autoridad para la matriz RBAC — CERRADO

- **ID:** `BLK-001`.
- **Cierre:** la consigna del 2026-07-14 aprobó catálogo, matrices, compatibilidad de `ADMINISTRADOR`, límites de `DIRECCION`/`SECRETARIA`/`CAJA` y deshabilitación de `PROFESOR`.
- **Evidencia:** contrato exacto registrado en `DEC-RBAC-001`; la implementación y las pruebas de V6 quedan sujetas al gate técnico, no a otra decisión funcional.
- **Fecha de cierre:** 2026-07-14.

### BLK-002 — Suite frontend completa roja — CERRADO

- **ID:** `BLK-002`.
- **Síntoma histórico:** `npm test` terminó 33/36 en el baseline y 36/39 después de agregar tres pruebas RBAC verdes.
- **Causa:** una expectativa singular de Alumnos no contempla las representaciones desktop/mobile simultáneas del DOM y dos expectativas de Pagos usan `$ 100.50` en vez del formatter real `$ 100,50`. Son fallos preexistentes clasificados, no introducidos por este bloque RBAC.
- **Cierre / evidencia:** la suite actual terminó 21 archivos/140 tests, lint y build en exit 0 el 2026-07-14; las expectativas se corrigieron conservando intención.
- **Efecto:** deja de bloquear GATE-1. Parte C sigue pendiente por alcance funcional, no por una suite roja.

### BLK-003 — Ambiente externo y operación de release no definidos

- **ID:** `BLK-003`.
- **Síntoma:** staging y producción permanecen `NO-GO`; no se pueden ejecutar de forma segura despliegue, migración, backup/restore o rollback externos.
- **Causa:** faltan ambiente, dominio/TLS, responsables, datos permitidos, ventana, secretos, política de backup, artefacto anterior y criterio de abortar; además existe drift de variables JWT entre Compose/perfil prod y `JwtProperties`.
- **Intentos seguros / evidencia:** se inspeccionaron Compose, perfiles, scripts, configuración frontend y checklist. No se iniciaron contenedores, no se leyeron secretos y no se tocó una base real.
- **Autoridad o dato necesario:** responsable autorizado debe identificar el ambiente y entregar por canal externo los valores/secretos, ventana y autorización; operaciones debe aceptar backup, restore y rollback.
- **Tarea afectada:** `E4-009` y gates de staging/producción; no bloquea Etapa 1.
- **Condición de cierre:** configuración reconciliada y validada, Docker/health/smoke verdes, backup restaurado en destino aislado, rollback ensayado y autorización fechada en bitácora.

## Próxima acción única

Crear commits temáticos y el PR reemplazante desde `feat/rbac-production-hardening`; cerrar #11 sólo después de que el nuevo PR exista y esperar checks remotos. No iniciar Etapa 1B hasta confirmar el merge verde a `main`.
