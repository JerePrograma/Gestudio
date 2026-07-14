# Checklist de release

> Decisión actual: `NO-GO`
>
> Baseline actual: `feat/rbac-production-hardening` desde `f6493a3b1b7988a626c0742fe88ce75c2f1c4ee5`; `origin/main` inicial `644e044b26438516ea093513ca5651ce72fb3fb3`
>
> Última revisión documental: 2026-07-14
>
> Regla: una casilla sólo se marca con comando/recorrido, fecha y resultado enlazados.

[Índice](./00_INDEX.md) · [Baseline](./01_BASELINE_Y_HALLAZGOS.md) · [Matriz RBAC](./02_MATRIZ_RBAC.md) · [Etapa 1](./03_ETAPA_1_SEGURIDAD_RBAC.md) · [Etapa 1B](./04_ETAPA_1B_LIQUIDACION_FINANCIERA.md) · [Etapa 2](./05_ETAPA_2_UX_OPERATIVA.md) · [Etapa 3](./06_ETAPA_3_COMPONENTES_Y_CONTRATOS.md) · [Etapa 4](./07_ETAPA_4_DEMO_Y_PUBLICACION.md) · [Plan de pruebas](./08_PLAN_DE_PRUEBAS.md) · [Bitácora](./09_BITACORA_IMPLEMENTACION.md) · [Decisiones](./10_DECISIONES_Y_BLOQUEOS.md)

## Cómo usar este checklist

- `VALIDADO`: existe evidencia actual y reproducible.
- `PENDING`: aún no corresponde ejecutar o falta trabajo previo.
- `BLOCKED`: una evidencia roja o decisión impide aprobar el gate.
- `NO_VERIFICADO`: existe código/configuración, pero no se ejecutó la prueba requerida.
- Demo interna, demo comercial, staging y producción son autorizaciones distintas.
- Un build o smoke verde no autoriza despliegue. Toda mutación externa requiere confirmación explícita y alcance definido.
- La evidencia completa se registra en [09_BITACORA_IMPLEMENTACION.md](./09_BITACORA_IMPLEMENTACION.md); aquí sólo se resume y enlaza.

## Evidencia actual

| Evidencia | Estado | Resultado actual |
|---|---|---|
| Branch/HEAD/árbol inicial | `VALIDADO` | Fuente `f6493a3b`, árbol limpio; implementación en `feat/rbac-production-hardening`. El SHA final se registra después de commits. |
| Frontend test/lint/build | `VALIDADO` | 21 archivos/140 tests, lint y build 2337 módulos, exit 0. |
| Backend `clean verify` | `VALIDADO` | 129/129, 0 fallos/errores/skips, jar generado. |
| Políticas HTTP | `VALIDADO` | 144/144 mappings reales contractualizados; ruta desconocida y Observaciones en `denyAll`. |
| Flyway base limpia/upgrade | `VALIDADO` para V1–V6 | Base limpia y V5→V6; 32 permisos y matrices 32/31/31/17/8/0; V1–V5 inmutables. |
| Smoke sin seed demo | `VALIDADO` | 20/20, base limpia, imágenes reconstruidas y limpieza completa. |
| Docker Compose | `VALIDADO` | `docker compose config --quiet` exit 0. |
| Integración remota | `PENDING` | Sólo PR #11 sigue draft con smoke rojo del baseline; falta PR reemplazante/checks/merge. |
| Demo, backup/restore y rollback | `NO_VERIFICADO` | Sin ejecución registrada. |

## Gate: demo interna

**Estado:** `BLOCKED`. Requiere `GATE-1`, `GATE-1B`, `GATE-2` y `GATE-3` cerrados.

- [ ] Todas las suites obligatorias están verdes o cualquier fallo está aceptado explícitamente con alcance y riesgo.
- [ ] Base descartable migra, bootstrap funciona y el primer GET operativo no requiere SQL manual.
- [ ] Dataset demo se carga después del bootstrap y no siembra permisos productivos faltantes.
- [ ] Dirección, Secretaría y Caja completan recorridos con datos ficticios; Profesor permanece inactivo/no asignable y sus accesos son denegados.
- [ ] Recorrido alumno → inscripción → cargo → pago → recibo → caja se completa.
- [ ] Egresos, Stock y Asistencia demuestran el alcance comercial declarado.
- [ ] Intentos sin permiso muestran 403/UX accionable y preservan la sesión.
- [ ] No aparecen IDs técnicos, acciones no-op ni errores internos.
- [ ] PC y celular completan el recorrido con teclado/foco básico.
- [ ] Evidencia y riesgos quedaron en bitácora.

## Gate: demo comercial

**Estado:** `PENDING`. No iniciar antes de aprobar demo interna y recibir autorización.

- [ ] Guion de 10–15 minutos aprobado con comienzo, datos y cierre reproducibles.
- [ ] Base/demo puede reiniciarse sin intervención SQL improvisada.
- [ ] Se demuestra separación real de roles sin usar SUPERADMIN como cuenta diaria.
- [ ] Dashboard muestra sólo 3–5 señales relevantes por permiso.
- [ ] Reportes/exportaciones respetan permisos y usan referencias humanas.
- [ ] Tarifas/condiciones por vigencia producen importes y snapshots esperados.
- [ ] Mensajes, empty states y siguiente acción son comprensibles para una secretaria.
- [ ] No se ofrecen módulos incompletos como funciones terminadas.
- [ ] Existe responsable de operación y plan si la demo falla.
- [ ] Se registraron observaciones y decisión de avanzar/no avanzar.

## Gate: staging

**Estado:** `PENDING`; requiere autorización externa específica.

- [ ] Ambiente, dominio, responsables, ventana y datos permitidos están identificados.
- [ ] Secretos provienen de variables/gestor externo; no están en repo, imágenes ni logs.
- [ ] TLS, CORS, cookies y URLs frontend/backend usan el ambiente correcto; STOMP continúa ausente y REST/email está configurado.
- [ ] Imagen/backend usa Java 21 y los builds Docker limpios terminan correctamente.
- [ ] Base de staging tiene backup previo y restore probado en un destino aislado.
- [ ] Flyway base limpia y upgrade desde el estado anterior terminan correctamente.
- [ ] Smoke, health checks y recorridos por rol pasan en staging.
- [ ] Logs no exponen tokens, contraseñas, payloads personales o financieros completos.
- [ ] Rollback de aplicación y recovery de datos fueron ensayados.
- [ ] La aprobación de staging quedó fechada en la bitácora.

## Gate: producción

**Estado:** `PENDING` / `NO-GO`; requiere autorización explícita posterior a staging.

- [ ] Commit/artefacto exacto, changelog, migraciones y checksum están congelados.
- [ ] Todos los gates anteriores están aprobados sin evidencia vencida.
- [ ] Ventana, responsables, monitoreo y criterios de abortar están acordados.
- [ ] Backup de producción fue completado y su restaurabilidad fue probada.
- [ ] Migración tiene precondiciones, reconciliación, tiempos y recovery revisados.
- [ ] No se depende de seed demo, credenciales bootstrap temporales ni SQL manual.
- [ ] Smoke post-deploy y verificaciones financieras/de permisos están definidos.
- [ ] Artefacto anterior y runbook de rollback están disponibles.
- [ ] Riesgos residuales fueron aceptados por quien tiene autoridad.
- [ ] Aprobación `GO` quedó registrada antes de ejecutar el despliegue.

## Gate: seguridad

**Estado:** `VALIDADO LOCAL / PENDIENTE CI Y MERGE`.

- [x] Catálogo y roles base son determinísticos desde base limpia.
- [x] SUPERADMIN bootstrap recibe la matriz productiva sin seed demo.
- [x] Todos los permisos canónicos usados existen, están activos y sembrados/asignados.
- [x] Sin autenticación devuelve 401; autenticado sin autoridad devuelve 403; conflicto real devuelve 409.
- [x] Cada write sensible tiene permiso backend explícito y defensa de servicio cuando corresponde.
- [x] Usuario, rol o permiso inactivo y `authVersion` invalidan acceso efectivo.
- [x] Delegación no permite escalamiento ni desactivar el último SUPERADMIN.
- [x] Profesor permanece deshabilitado, sin permisos, no asignable y sin rutas visibles.
- [x] Menú, rutas y acciones frontend usan la misma matriz; `/unauthorized` no entra en loop.
- [x] Usuarios/Roles usan `PERM_USUARIOS_ADMIN` / `PERM_ROLES_ADMIN`, no strings `*_WRITE` — 2026-07-11, UI permitido/denegado y HTTP focalizado verdes.
- [x] `/unauthorized` no exige un permiso funcional y conserva autenticación; códigos de rol `ROLE_*` son rechazados — 2026-07-11, pruebas focalizadas verdes.
- [x] Refresh se mantiene serializado sólo para 401; 403 conserva sesión.
- [x] WebSocket/STOMP está deshabilitado por completo; REST/email permanece.
- [x] Matriz HTTP, contrato frontend y smoke de seguridad están verdes localmente.
- [ ] PR reemplazante, checks remotos y merge a `main` completados.

## Gate: datos y migraciones

**Estado:** `RBAC V6 VALIDADO`; contratos financieros de Parte B `PENDING`.

- [x] Historial Flyway real y versión siguiente fueron confirmados antes de editar V6.
- [x] Base limpia aplica V1–V6 y JPA valida el esquema.
- [x] Upgrade V5→V6 termina sin pérdida y preserva IDs/asignaciones personalizadas.
- [x] Precondiciones V6 fallan ante colisiones incompatibles antes de reconciliar.
- [x] Reconciliación RBAC verifica conteos y matrices exactas.
- [x] V6 no borra historia de pagos, cuotas, inscripciones, asistencia, caja, egresos o usuarios auditables.
- [x] RBAC productivo y dataset demo permanecen separados.
- [ ] Tarifa/condición vigente es la única fuente de cargos y conserva snapshot/versionado.
- [ ] Idempotencia evita cargos, pagos, egresos, ventas o liquidaciones duplicados.
- [x] Pruebas PostgreSQL/Testcontainers de RBAC pasan; H2 no se usa como prueba de Flyway/PostgreSQL.
- [x] Recovery/rollback lógico de V6 está documentado como forward-only/restauración aislada.

## Gate: observabilidad y backup

**Estado:** `NO_VERIFICADO`.

- [ ] Health/readiness permite distinguir aplicación, DB y dependencia externa.
- [ ] Logs registran operación, ID, estado y resultado sin secretos ni datos completos.
- [ ] Errores 500 no exponen detalles internos y conservan correlación diagnóstica.
- [ ] Métricas/alertas mínimas cubren disponibilidad, errores, latencia y fallos de jobs críticos.
- [ ] Zona horaria de negocio y timestamps operativos están documentados.
- [ ] Política de backup define frecuencia, retención, cifrado, destino y responsable.
- [ ] Backup fue restaurado en ambiente aislado y validado con consultas/smoke.
- [ ] Fallos de email/recibo después de commit son observables y reintentables sin duplicar negocio.
- [ ] Runbook indica dónde mirar y cuándo escalar.

## Gate: rollback

**Estado:** `NO_VERIFICADO`.

- [ ] Artefacto anterior compatible está identificado y disponible.
- [ ] Se definió qué cambios admiten rollback de aplicación y cuáles requieren recovery forward-only.
- [ ] Backup previo tiene restore probado y tiempo conocido.
- [ ] Migraciones destructivas o ambiguas están prohibidas o tienen reconciliación/recuperación explícita.
- [ ] Pagos, egresos, stock, caja e inscripciones se revierten por registros/estados, nunca por borrado histórico.
- [ ] Criterios de abortar, responsable y comandos exactos están en runbook.
- [ ] Smoke posterior al rollback verifica login, permisos y circuito financiero mínimo.
- [ ] El simulacro fue ejecutado en staging y su evidencia quedó registrada.

## Gate: UX crítica

**Estado:** `PENDING`; la suite actual está verde, pero Parte C no comenzó.

- [ ] Cero IDs técnicos visibles en tablas, formularios, toasts, labels y filenames operativos.
- [ ] Búsqueda de alumnos funciona por nombre, apellido, ambos órdenes y DNI/documento.
- [ ] Selectores controlados son accesibles y muestran contexto humano.
- [ ] No se puede editar una clave que backend considera inmutable.
- [ ] Baja, reactivación, finalización y anulación se nombran según su efecto real.
- [ ] Pagos, recibos, Caja y Egresos muestran referencias humanas y ARS consistente.
- [ ] Fecha operativa usa Buenos Aires y Caja abre en Hoy.
- [ ] Stock cambia cantidad mediante movimientos; venta/reversión es completa o queda fuera del alcance comercial.
- [ ] Asistencia diaria cubre PRESENTE/AUSENTE/JUSTIFICADO y estado de guardado.
- [ ] Estados empty/loading/error ofrecen feedback y siguiente paso autorizado.
- [ ] Flujos críticos funcionan en PC, celular y teclado.
- [x] Suite frontend, lint y build están verdes para el alcance RBAC actual.

## Gate: documentación

**Estado:** `VALIDADO` para GATE-0; el informe final de release permanece `PENDING` hasta Etapa 4.

- [x] Los 12 documentos existen y están enlazados desde [00_INDEX.md](./00_INDEX.md).
- [x] Baseline contiene SHA, branch, estado, comandos y fallos clasificados.
- [x] Cada hallazgo tiene ID estable, evidencia y tarea asociada.
- [x] Matriz RBAC cubre frontend, endpoint, permiso, seed, ownership y tests.
- [x] Cada etapa registra objetivo, alcance, dependencias, tareas, riesgos, rollback, aceptación, validación y gate.
- [x] [08_PLAN_DE_PRUEBAS.md](./08_PLAN_DE_PRUEBAS.md) contiene comandos PowerShell exactos y todos los niveles requeridos.
- [x] [09_BITACORA_IMPLEMENTACION.md](./09_BITACORA_IMPLEMENTACION.md) registra cada tarea, archivos, decisión, pruebas y resultado.
- [x] [10_DECISIONES_Y_BLOQUEOS.md](./10_DECISIONES_Y_BLOQUEOS.md) contiene decisiones/autoridad y bloqueos reales.
- [x] Este checklist refleja evidencia actual y no conserva casillas verdes obsoletas.
- [ ] Informe final enlaza commit, migraciones, resultados, demo, riesgos y rollback.

## Decisión de salida

| Decisión | Condición | Estado actual |
|---|---|---|
| Demo interna | Gates funcionales + suites + smoke + recorrido | `NO-GO` |
| Demo comercial | Demo interna aprobada + autorización | `NO-GO` |
| Staging | Demo comercial aprobada + ambiente/backup/rollback | `NO-GO` |
| Producción | Staging aprobado + autorización explícita | `NO-GO` |

El próximo cambio de estado debe actualizar [00_INDEX.md](./00_INDEX.md), este checklist y una entrada fechada en [09_BITACORA_IMPLEMENTACION.md](./09_BITACORA_IMPLEMENTACION.md).
