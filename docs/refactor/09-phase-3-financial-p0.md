# Fase 3 - Correcciones financieras P0 (snapshot histórico)

> Caracterización previa al modelo Cargo/Pago/Aplicacion. Las clases, riesgos y
> tipos aquí descritos fueron retirados; consultar 11-20 y el worklog 16.

Fecha de cierre local: 2026-06-29.

Estado: implementación y gates funcionales completos. No se ejecutó commit, push, merge, tag, deploy, migración ni conexión a la instancia PostgreSQL que escucha en 5432.

## Estado inicial

- Rama: `main`, alineada con `origin/main`.
- SHA inicial y SHA final de trabajo: `bbe598f903c3915270adf622996650a6dc860189`; no se crearon commits.
- Árbol inicial limpio; `git diff` y `git diff --cached` vacíos.
- El primer `status.ps1`, `setup.ps1`, `validate.ps1` y `backend\.\mvnw.cmd clean verify` no llegaron a las pruebas porque `JAVA_HOME` apuntaba a `C:\Program Files\Eclipse Adoptium\jdk-21`, ruta inexistente. Se usó el JDK 21 ya instalado en `C:\Program Files\Java\corretto-21.0.7`, sin instalar ni cambiar herramientas.
- Docker Engine estaba inicialmente no disponible; quedó disponible antes de los gates finales. No se iniciaron servicios Compose.
- Frontend inicial: `npm ci` PASS; lint PASS; 3 archivos/8 tests PASS; build PASS con 2295 módulos.
- Backend inicial con el JDK válido: 48 tests, 4 fallos, 0 errores, 0 omitidos.

## Defectos reproducidos y causa raíz

1. `MensualidadServicioTest.recalcularConservaImporteInicialYActualizaSaldoPendiente`: esperaba `importeInicial=100.0` y obtuvo `70.0`. El recálculo escribía el saldo sobre el importe original y nunca actualizaba `importePendiente`.
2. `MensualidadServicioTest.recalcularRechazaSobrepagoSinMutarLaMensualidad`: no se lanzó excepción. El saldo negativo se aceptaba, se escribía parcialmente y se comparaba dinero con `==`.
3. `PagoServicioTest.listarVencidosConsultaSoloPagosActivos`: esperaba `EstadoPago.ACTIVO` y el servicio consultaba `HISTORICO`; luego intentaba corregir parcialmente el resultado en memoria.
4. `PagoServicioTest.registrarPagoNoMutaInscripcionesParaMapearLaRespuesta`: esperaba una inscripción y obtuvo cero. El servicio ejecutaba `clear()` sobre la colección JPA administrada para preparar el DTO.
5. La ruta usada por el frontend, `DELETE /api/alumnos/{id}`, delegaba a una segunda baja que borraba asistencias mediante `orphanRemoval`; el path alternativo usaba otra implementación.
6. La baja individual de inscripción también vaciaba asistencias y podía borrar su historia por `orphanRemoval`.

## Decisiones aplicadas

- `importePendiente = importeInicial - montoAbonado` se calcula con `BigDecimal.valueOf(...)`, escala 2 y `HALF_UP`, sin cambiar los campos `Double` persistidos.
- Se validan importe inicial negativo, monto abonado negativo y sobrepago antes de cualquier mutación.
- Saldo cero marca `PAGADO` y fecha con el `Clock` existente; saldo positivo marca `PENDIENTE` y limpia una `fechaPago` engañosa.
- Vencidos quedó como una única consulta JPQL: `ACTIVO`, vencimiento no nulo y anterior a la fecha de negocio, saldo no nulo y mayor que cero. El servicio sólo mapea; no repite el filtro.
- `registrarPago` ya no muta asociaciones para serializar y exige un alumno activo antes de procesar.
- Ambos paths DELETE de alumno se conservan en un único método controlador y delegan a `darBajaAlumno`.
- La segunda baja de alumno es idempotente: devuelve 204, conserva la fecha original y no vuelve a guardar.
- La baja de alumno no toca inscripciones, asistencias, mensualidades ni matrículas. Pagos, detalles, recibos y caja tampoco son recorridos ni eliminados.
- La baja de inscripción sólo cambia estado y fecha; conserva asistencias.
- `IAlumnoServicio` se eliminó: tenía una sola implementación, ningún consumidor y no era un puerto externo.
- Los logs de `registrarPago` ya no incluyen request, entidades ni DTO de respuesta; queda un resultado por IDs.

## Alternativas rechazadas

- No se creó wrapper, puerto, adapter, factory ni servicio alrededor de `Clock`.
- No se copió ni separó el grafo JPA para mapear una respuesta.
- No se agregó un filtro en memoria que duplique la consulta de vencidos.
- No se eliminó ninguno de los dos paths HTTP de baja.
- No se inició una migración global a `BigDecimal`, una migración Flyway ni reconciliación de datos.
- No se cambiaron cascadas o constraints sin auditoría de datos y compatibilidad.
- No se reemplazaron masivamente los `clear()` restantes.

## Invariantes protegidas

- `importeInicial` permanece inmutable durante el recálculo.
- `importePendiente` contiene el saldo redondeado a dos decimales.
- Un valor negativo o un sobrepago falla antes de mutar saldo, estado o fecha.
- `PAGADO` y `PENDIENTE` mantienen una `fechaPago` coherente con el estado.
- Vencido significa simultáneamente ACTIVO, fecha anterior y saldo positivo no nulo.
- Mapear un pago no cambia las inscripciones del alumno.
- Dar de baja alumno o inscripción no borra colecciones históricas.
- Un alumno inactivo no puede iniciar un nuevo registro de pago.

## Compatibilidad de endpoints

El frontend usa `alumnosApi.eliminar(id)`, que llama `DELETE /api/alumnos/{id}`. Ese path se conserva. También se conserva `DELETE /api/alumnos/dar-baja/{id}`. Ambos producen 204 y ejecutan la misma operación canónica idempotente.

## Inventario controlado de `clear()` productivos

Inventario inicial: nueve llamadas. Se eliminaron tres; quedan seis.

| Archivo y método | Clase | Efecto con el mapping actual | Decisión / fase |
| --- | --- | --- | --- |
| `PagoServicio.registrarPago` | A - mutación para serializar | Vaciaba `Alumno.inscripciones`; `cascade=ALL` y `orphanRemoval=true` podían borrar inscripciones y descendientes | Corregido en Fase 3: llamada y helper eliminados; el mapper recibe el grafo intacto |
| `AlumnoServicio.eliminarAlumno` | B - baja peligrosa | Vaciaba `Inscripcion.asistenciasAlumnoMensual`; `orphanRemoval=true` borraba asistencias mensuales y podía propagar a diarias | Corregido en Fase 3: implementación duplicada eliminada |
| `InscripcionServicio.eliminarInscripcion` | B - baja peligrosa | Vaciaba `asistenciasAlumnoMensual`; se eliminaban filas históricas y sus hijas | Corregido en Fase 3: queda baja lógica por estado/fecha |
| `DisciplinaServicio.crearDisciplina` | C - reemplazo intencional | Tras persistir/guardar horarios, vacía la colección administrada; `Disciplina.horarios` tiene `cascade=ALL` y `orphanRemoval=true`, por lo que puede borrar filas de `disciplina_horarios` | No modificado; caracterizar duplicación `save/deleteBy/clear` en fase de disciplinas |
| `DisciplinaServicio.actualizarDisciplina` | C - reemplazo intencional | Un request sin horarios vacía todos los horarios y elimina sus filas por `orphanRemoval` | No modificado; confirmar semántica de lista vacía y agregar regresión antes de simplificar |
| `DisciplinaHorarioServicio.actualizarHorarios` | C - reemplazo intencional | Elimina ausentes explícitamente y luego hace `clear/addAll`; la colección usa `orphanRemoval` | No modificado; caracterizar filas retenidas/eliminadas y retirar redundancia sólo con prueba |
| `DisciplinaHorarioServicio.guardarHorarios` | C - reemplazo intencional | Ejecuta `deleteByDisciplinaId` y además `clear/addAll`; puede duplicar la eliminación de `disciplina_horarios` | No modificado; fase de disciplinas, con prueba de reemplazo |
| `PagoServicio.actualizarDetallesPago` | E - ambiguo | `Pago.detallePagos` tiene `cascade=ALL` y `orphanRemoval=true`; omitir un detalle del request puede borrarlo físicamente | No modificado; riesgo financiero, caracterización y política explícita de reversión antes de tocar |
| `PaymentProcessor.processDetallesPago` | E - ambiguo | Vacía la misma colección antes de crear detalles; sobre una entidad administrada puede borrar `detalle_pagos` históricos | No modificado; fase financiera posterior con caracterización y reconciliación |

No se hallaron casos categoría D. Los cuatro casos C no tienen una regresión específica que pruebe exactamente qué filas conserva y elimina el reemplazo. Los dos casos E permanecen abiertos por su impacto financiero.

## Pruebas agregadas o ampliadas

- `MensualidadServicioTest`: seis casos para pago parcial, pago total, sobrepago, monto abonado negativo, importe inicial negativo, fecha determinista y recálculo repetido.
- `PagoServicioTest`: fecha de negocio fija y estado ACTIVO, preservación de la misma colección/inscripción al mapear y rechazo temprano de alumno inactivo.
- `AlumnoServicioTest`: baja idempotente, fecha de negocio y preservación de inscripciones, asistencias, mensualidades y matrículas.
- `InscripcionServicioTest`: baja lógica con fecha de negocio y preservación de asistencias.

La exclusión de vencimiento de hoy/futuro, saldo cero/negativo/nulo e históricos/anulados está expresada en una sola query del repositorio. La prueba unitaria fija la fecha y verifica que el servicio consulta `ACTIVO`; no se añadió una segunda copia en memoria de ese predicado.

## Archivos productivos modificados

- `backend/src/main/java/gestudio/controladores/AlumnoControlador.java`
- `backend/src/main/java/gestudio/repositorios/PagoRepositorio.java`
- `backend/src/main/java/gestudio/servicios/alumno/AlumnoServicio.java`
- `backend/src/main/java/gestudio/servicios/inscripcion/InscripcionServicio.java`
- `backend/src/main/java/gestudio/servicios/mensualidad/MensualidadServicio.java`
- `backend/src/main/java/gestudio/servicios/pago/PagoServicio.java`

Eliminado: `backend/src/main/java/gestudio/servicios/alumno/IAlumnoServicio.java`.

Pruebas modificadas/creadas: `MensualidadServicioTest`, `PagoServicioTest`, `AlumnoServicioTest` e `InscripcionServicioTest`.

Documentación: este archivo y `05-risk-register.md`.

## Comandos y resultados

| Comando | Resultado |
| --- | --- |
| `git status --short --branch`, `git rev-parse HEAD`, `git log -5 --oneline`, `git diff`, `git diff --cached` | PASS; SHA esperado y árbol inicial limpio |
| `scripts/codex/status.ps1` inicial | FAIL; `JAVA_HOME` inexistente y Docker Engine no disponible |
| `scripts/codex/setup.ps1` inicial | FAIL; `JAVA_HOME` no apuntaba a un JDK completo |
| `scripts/codex/validate.ps1` inicial | FAIL; faltaba `bin/javac.exe` en el `JAVA_HOME` heredado |
| `backend\.\mvnw.cmd clean verify` inicial | FAIL antes de Maven por `JAVA_HOME` inválido |
| `backend\.\mvnw.cmd clean verify` baseline con Corretto 21 | FAIL; 48 tests, 4 fallos, 0 errores, 0 omitidos; los cuatro defectos P0 listados arriba |
| `frontend\npm ci` baseline | PASS; 560 paquetes |
| `frontend\npm run lint` baseline y final | PASS |
| `frontend\npm test -- --run` baseline y final | PASS; 3 archivos, 8 tests |
| `frontend\npm run build` baseline y final | PASS; 2295 módulos |
| suite dirigida sin citar el argumento `-Dtest=...,...` | FAIL de invocación; PowerShell interpretó las comas y produjo `ParserError` antes de Maven |
| suite dirigida final `MensualidadServicioTest,PagoServicioTest,AlumnoServicioTest,InscripcionServicioTest` | PASS; 11 tests, 0 fallos, 0 errores, 0 omitidos |
| `backend\.\mvnw.cmd clean verify` final | PASS; 55 tests, 0 fallos, 0 errores, 0 omitidos; JAR generado |
| `docker compose config` | PASS |
| Compose local + productivo sin variables obligatorias | FAIL esperado; rechazó `POSTGRES_PASSWORD` ausente |
| Compose local + productivo con placeholders efímeros y `config --quiet` | PASS |
| `docker build --pull -t gestudio-backend:phase3-test .\backend` final | PASS; 55 tests dentro de la imagen; imagen creada |
| `scripts/codex/status.ps1` con Corretto 21 y Docker disponible | PASS |
| `scripts/codex/setup.ps1` con Corretto 21 | PASS; dependencias backend/frontend preparadas, sin servicios iniciados |
| `scripts/codex/validate.ps1` final con Corretto 21 | PASS; backend clean verify, frontend lint/test/build y Compose local |

No se construyó la imagen frontend porque no se modificó frontend, Docker compartido ni configuración de su artefacto.

## Riesgos pendientes

- R10 queda abierto sólo por `Double`; la mutación de `importeInicial` quedó cerrada.
- R11 queda cerrado para el contrato implementado de vencidos.
- R12 queda parcialmente abierto por los seis `clear()` C/E documentados.
- R13 sigue abierto por cascadas, `orphanRemoval`, FKs y posibles rutas físicas no auditadas globalmente.
- R16 sigue abierto hasta una migración integral y reconciliada a `BigDecimal`/tipos DB consistentes.
- Los warnings preexistentes de MapStruct, Lombok, APIs deprecated y Mockito continúan visibles; no fueron silenciados.
- No se ejecutó una prueba de repositorio contra PostgreSQL para la query JPQL: no se tocó la instancia desconocida en 5432 ni se agregó infraestructura/dependencias para este alcance.

## Cambios deliberadamente no realizados

- Auditoría o corrección de datos existentes.
- Nuevo modelo financiero, aplicaciones de pago o política global de reversión.
- Migración global a `BigDecimal`.
- Migraciones Flyway, cambios de esquema, cascadas o constraints.
- Modularización, optimización de consultas o rediseño frontend.
- Refactor de los seis `clear()` C/E pendientes.
- Corrección masiva de logs, comentarios, `LocalDate.now()` o interfaces fuera de los caminos tocados.
- Commit, push, merge, tag o deploy.

## Gate de fase

La Fase 3 estabiliza los defectos P0 comprobados y preserva historial en las bajas tocadas. No implica que el modelo financiero completo, los datos reales o todas las rutas destructivas estén saneados.
