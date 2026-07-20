# Checklist de release

> Decisión actual: **`NO-GO` para staging y producción**  
> Fecha de corte: **2026-07-20**  
> Rama: `main`  
> HEAD remoto revisado: `3f314ba8cc61a71bfa434a46593cd02336ec16e5`  
> Regla: una casilla sólo se marca con evidencia ejecutada, fecha, HEAD y resultado.

[Índice](./00_INDEX.md) · [Estado maestro](./12_ESTADO_ACTUAL_Y_BACKLOG.md) · [Bitácora de continuidad](./13_BITACORA_CONTINUIDAD.md) · [Plan de pruebas](./08_PLAN_DE_PRUEBAS.md)

## 1. Convenciones

- `VALIDADO`: existe evidencia reproducible sobre un commit identificado.
- `INTEGRADO`: el cambio existe en `main`; no implica repetición de pruebas.
- `PARTIAL`: existe avance, pero no cumple el gate completo.
- `READY`: dependencias cerradas; puede comenzar.
- `PENDING`: definido, no iniciado o sin evidencia suficiente.
- `BLOCKED`: falta una condición externa o una evidencia obligatoria.
- `NO_VERIFICADO`: existe código o configuración, pero no se ejecutó el gate.
- Demo interna, demo comercial, staging y producción son autorizaciones distintas.

## 2. Snapshot actual

| Evidencia | Estado | Resultado |
|---|---|---|
| Rama y HEAD remotos | `VALIDADO` | `main` en `3f314ba8` |
| PR abiertos | `VALIDADO` | Ninguno observado el 2026-07-20 |
| Issues abiertos | `VALIDADO` | Ninguno observado el 2026-07-20 |
| Checks del HEAD | `NO_VERIFICADO` | No se publicaron status checks para el HEAD consultado |
| Workflow runs del HEAD | `NO_VERIFICADO` | No se publicaron runs para el HEAD consultado |
| RBAC | `INTEGRADO / VALIDADO HISTÓRICO` | Backend 129, frontend 140, All y smoke 20/20 antes de integración |
| Flyway | `VALIDADO HISTÓRICO` | V1-V6 y matrices exactas |
| Seed demo | `INTEGRADO / NO_VERIFICADO EN HEAD` | Seed, validador y documentación presentes |
| Demo persistente | `INTEGRADO / NO_VERIFICADO` | Lanzador y guía presentes |
| UX | `PARTIAL` | Tabla, foco de búsqueda, continuidad de datos y roles |
| Estrategia comercial | `INTEGRADO / CANÓNICO` | Precios, piloto, mensajes y métricas |
| Backup/restore | `NO_VERIFICADO` | Sin simulacro registrado |
| Rollback | `NO_VERIFICADO` | Sin simulacro registrado |

## 3. Gate de documentación

**Estado: `VALIDADO / ACTUALIZADO`.**

- [x] Índice reconciliado con `main` actual.
- [x] Estado maestro con alcance, progreso, backlog y riesgos.
- [x] Bitácora de continuidad posterior a la histórica.
- [x] Etapa 1B ya no figura bloqueada por el merge RBAC.
- [x] Checklist no confunde integración con validación.
- [x] Estrategia comercial enlazada como fuente normativa.
- [ ] Próximas corridas deben registrar resultados reales sobre el HEAD actual.
- [ ] Informe final de release continúa pendiente.

## 4. GATE-0 — baseline

**Estado: `DONE`.**

- [x] Stack y cadena Flyway identificados.
- [x] Rutas, endpoints y permisos inventariados.
- [x] Hallazgos con IDs y tareas.
- [x] Plan de pruebas y bitácora histórica.
- [x] Decisiones y bloqueos.
- [x] Estado postintegración reconciliado.

## 5. GATE-1 — seguridad y RBAC

**Estado: `DONE / INTEGRADO EN MAIN`.**

- [x] Catálogo de 32 permisos.
- [x] Matrices base determinísticas.
- [x] SUPERADMIN con 32 permisos.
- [x] DIRECCION y ADMINISTRADOR con 31.
- [x] SECRETARIA con 17.
- [x] CAJA con 8.
- [x] PROFESOR inactivo, sin permisos y no asignable.
- [x] Bootstrap fail-fast.
- [x] Sin autenticación = 401.
- [x] Sin permiso = 403.
- [x] Conflicto de negocio = 409.
- [x] Backend y frontend alineados.
- [x] `/api/**` desconocido fail-closed.
- [x] STOMP retirado.
- [x] Observaciones sin superficie activa.
- [x] Backend 129/129 en evidencia histórica.
- [x] Frontend 140/140, lint y build en evidencia histórica.
- [x] All PASS en evidencia histórica.
- [x] Smoke 20/20 en evidencia histórica.
- [x] Cambios integrados a `main`.

Revalidación requerida antes de demo interna:

- [ ] Repetir suites y smoke sobre `3f314ba8` o HEAD posterior exacto.

## 6. GATE-1B — liquidación financiera

**Estado: `READY_TO_START`.**

### Caracterización

- [ ] Casos de tarifa anterior, exacta y futura.
- [ ] Casos de condición anterior, exacta y futura.
- [ ] Costo particular nulo y no nulo.
- [ ] Descuento porcentual, fijo y combinado.
- [ ] Ausencia de tarifa.
- [ ] Matrícula con cero, una y varias disciplinas.
- [ ] Reintento secuencial y concurrente.

### Implementación

- [ ] Un único servicio resuelve tarifa y condición.
- [ ] Fecha mensual = primer día del período.
- [ ] Fecha matrícula = 1 de enero.
- [ ] Ausencia de tarifa aborta.
- [ ] Costo particular efectivo tiene prioridad.
- [ ] Bonificación usa snapshots efectivos.
- [ ] Matrícula usa máximo efectivo entre disciplinas activas.
- [ ] Cargo y snapshot son atómicos.
- [ ] `formula_version = 1` queda persistida.
- [ ] Reintentos no duplican.
- [ ] Cálculo no lee campos legacy.
- [ ] UI no ofrece fuentes paralelas.

### Validación

- [ ] Tests unitarios de fórmula.
- [ ] Tests PostgreSQL de vigencia.
- [ ] Tests de rollback transaccional.
- [ ] Tests de idempotencia y concurrencia.
- [ ] Backend completo verde.
- [ ] Frontend completo verde.
- [ ] All verde.
- [ ] Base limpia y upgrade si hubo migración.
- [ ] Documentación actualizada.

## 7. GATE-2 — UX crítica

**Estado: `PARTIAL`.**

Hecho:

- [x] Tabla no trata `Acciones` como dato.
- [x] Regresión para no mostrar `undefined`.
- [x] Búsqueda de alumnos conserva foco.
- [x] Alumnos e inscripciones conservan datos previos durante refetch.
- [x] Contrato frontend de roles usa permisos reales.
- [x] API explícita obligatoria en producción.
- [x] HTTPS obligatorio fuera de localhost en producción.

Pendiente:

- [ ] Cero IDs técnicos visibles en flujos comerciales.
- [ ] Búsqueda por nombre, apellido, órdenes y documento.
- [ ] Selectores con referencias humanas.
- [ ] Claves inmutables no editables.
- [ ] Baja, reactivación, finalización y anulación con textos correctos.
- [ ] Pagos, caja, egresos y recibos con ARS consistente.
- [ ] Fecha operativa Buenos Aires.
- [ ] Stock sólo por movimientos.
- [ ] Venta y reversión completas.
- [ ] Asistencia diaria con estado de guardado.
- [ ] Loading, empty y error accionables.
- [ ] PC, móvil y teclado.
- [ ] Recorrido humano por Dirección, Secretaría y Caja.

## 8. GATE-3 — componentes y contratos

**Estado: `PENDING`.**

- [ ] No existe refactor general sin necesidad de release.
- [ ] El resultado de liquidación es inmutable y testeable.
- [ ] Mensualidad y matrícula comparten resolución.
- [ ] Contratos frontend evitan modelos divergentes.
- [ ] Componentes comunes tienen regresiones propias.
- [ ] No se crean capas ceremoniales ni adaptadores sin consumidor.

## 9. Gate del seed demo

**Estado: `INTEGRADO / NO_VERIFICADO EN HEAD`.**

### Contrato estático

- [x] Seed separado de Flyway.
- [x] Sin migración demo.
- [x] Sin DML sobre roles, permisos o matrices.
- [x] Sin activación de PROFESOR.
- [x] Sin credenciales fijas.
- [x] Precondiciones de V6.
- [x] Conteos esperados de 914 filas.
- [x] Conciliaciones financieras y de stock documentadas.

### Ejecución requerida

- [ ] Parser PowerShell.
- [ ] Build backend usado por el validador.
- [ ] PostgreSQL aislado.
- [ ] Flyway V1-V6 desde vacío.
- [ ] Hibernate validate.
- [ ] Primera aplicación del seed.
- [ ] Conteos exactos.
- [ ] Integridad financiera.
- [ ] Integridad de stock.
- [ ] RBAC inmutable.
- [ ] Cinco logins.
- [ ] Casos 200/400/401/403.
- [ ] Segunda aplicación idéntica.
- [ ] IDs y hashes estables.
- [ ] Reinicio y nuevo login.
- [ ] Sin secretos en temporales.
- [ ] Sin recursos Docker residuales.
- [ ] Resultado registrado con HEAD y exit code.

## 10. Gate de demo persistente

**Estado: `INTEGRADO / NO_VERIFICADO`.**

- [x] Acciones Start, Status, Stop, Reset y SeedNative documentadas.
- [x] Puertos fijos y detección de conflicto.
- [x] Credenciales no persistidas en archivos/logs.
- [x] Cookie local aislada.
- [ ] Reset desde cero exitoso.
- [ ] Status muestra servicios saludables.
- [ ] Cinco usuarios pueden iniciar sesión.
- [ ] Separación real de roles demostrada.
- [ ] Dirección completa su circuito.
- [ ] Secretaría completa su circuito.
- [ ] Caja completa su circuito.
- [ ] Denegaciones preservan sesión y muestran feedback.
- [ ] Stop conserva datos.
- [ ] Reset elimina datos y recrea.
- [ ] Evidencia y tiempos registrados.

## 11. Gate de demo interna

**Estado: `BLOCKED`.**

- [ ] Todas las suites obligatorias están verdes sobre el HEAD exacto.
- [ ] Seed demo está verde e idempotente.
- [ ] Demo persistente arranca sin SQL improvisado.
- [ ] Circuito alumno → inscripción → cargo → pago → recibo → caja.
- [ ] Egresos, stock y asistencia funcionan según oferta.
- [ ] Dirección, Secretaría y Caja completan recorridos.
- [ ] PROFESOR permanece denegado.
- [ ] No aparecen IDs técnicos, `undefined` ni acciones no-op.
- [ ] PC y móvil completan el recorrido.
- [ ] Foco y teclado básico verificados.
- [ ] Fallo de demo tiene procedimiento de recuperación.
- [ ] Decisión `GO/NO-GO` registrada.

## 12. Gate de demo comercial

**Estado: `PENDING`.**

- [ ] Demo interna aprobada.
- [ ] Guion de 10-15 minutos.
- [ ] Capturas definitivas.
- [ ] Datos y usuarios reiniciables.
- [ ] Dashboard con 3-5 señales relevantes.
- [ ] Separación de roles visible.
- [ ] Mensajes alineados con estrategia canónica.
- [ ] Precios resueltos desde documento comercial.
- [ ] Limitaciones actuales explícitas.
- [ ] Responsable y plan de contingencia.
- [ ] Aprobación comercial registrada.

## 13. Gate de staging

**Estado: `PENDING / NO AUTORIZADO`.**

- [ ] Host y dominio identificados.
- [ ] Responsables y ventana definidos.
- [ ] Datos permitidos definidos.
- [ ] Secretos fuera de repo, imágenes y logs.
- [ ] TLS válido.
- [ ] CORS por ambiente.
- [ ] Cookies correctas.
- [ ] URLs frontend/backend correctas.
- [ ] Imágenes reproducibles con Java 21.
- [ ] Flyway base limpia y upgrade.
- [ ] Backup previo.
- [ ] Restore probado en destino aislado.
- [ ] Smoke y recorridos por rol.
- [ ] Health/readiness.
- [ ] Logs sin secretos ni payloads completos.
- [ ] Métricas y alertas mínimas.
- [ ] Rollback ensayado.
- [ ] Aprobación explícita.

## 14. Gate de producción

**Estado: `NO-GO`.**

- [ ] Todos los gates anteriores aprobados.
- [ ] Commit y artefactos congelados.
- [ ] Changelog y migraciones revisados.
- [ ] Backup restaurable.
- [ ] Ventana y responsables.
- [ ] Monitoreo en tiempo real.
- [ ] Criterios de abortar.
- [ ] Artefacto anterior disponible.
- [ ] Runbook de rollback.
- [ ] Smoke post-deploy.
- [ ] Verificación financiera y RBAC.
- [ ] Riesgos residuales aceptados.
- [ ] Autorización `GO` antes de desplegar.

## 15. Observabilidad y backup

**Estado: `NO_VERIFICADO`.**

- [ ] Health de aplicación.
- [ ] Readiness de DB y dependencias.
- [ ] Correlation ID para errores.
- [ ] 500 sin detalles internos.
- [ ] Métricas de disponibilidad, latencia y errores.
- [ ] Alertas por jobs críticos.
- [ ] Zona horaria documentada en operación.
- [ ] Frecuencia de backup.
- [ ] Retención.
- [ ] Cifrado.
- [ ] Destino externo.
- [ ] Responsable.
- [ ] Restore probado.
- [ ] Fallos de email/recibo observables y reintentables.
- [ ] Runbook operativo.

## 16. Rollback

**Estado: `NO_VERIFICADO`.**

- [ ] Artefacto anterior identificado.
- [ ] Compatibilidad DB revisada.
- [ ] Cambios forward-only clasificados.
- [ ] Backup previo restaurable.
- [ ] Tiempo de restore medido.
- [ ] No hay borrado histórico como rollback.
- [ ] Criterios de abortar.
- [ ] Responsable.
- [ ] Comandos exactos.
- [ ] Smoke posterior al rollback.
- [ ] Simulacro ejecutado en staging.

## 17. Decisión de salida

| Salida | Estado | Condición inmediata |
|---|---|---|
| Continuar desarrollo local | `GO` | Mantener evidencia y no romper gates cerrados |
| Iniciar GATE-1B | `GO` | Comenzar por `E1B-001` |
| Usar demo interna | `NO-GO` | Ejecutar validaciones y recorridos |
| Usar demo comercial | `NO-GO` | Aprobar demo interna |
| Desplegar staging | `NO-GO` | Ambiente, restore, rollback y autorización |
| Desplegar producción | `NO-GO` | Todos los gates y autorización final |

El próximo cambio de estado debe actualizar este checklist,
[12_ESTADO_ACTUAL_Y_BACKLOG.md](./12_ESTADO_ACTUAL_Y_BACKLOG.md) y
[13_BITACORA_CONTINUIDAD.md](./13_BITACORA_CONTINUIDAD.md).
