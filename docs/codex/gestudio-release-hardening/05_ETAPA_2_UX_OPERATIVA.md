# Etapa 2 — UX operativa crítica

> Estado: `PENDING`  
> Gate previo requerido: `GATE-1B` cerrado y autorización explícita  
> Gate de salida: `GATE-2`  
> Baseline documental: `main` en `b833f6741cf614c508666e8a121701e8db2fcf9a`

[Índice](./00_INDEX.md) · [Baseline y hallazgos](./01_BASELINE_Y_HALLAZGOS.md) · [Matriz RBAC](./02_MATRIZ_RBAC.md) · [Etapa 1B](./04_ETAPA_1B_LIQUIDACION_FINANCIERA.md) · [Etapa 3](./06_ETAPA_3_COMPONENTES_Y_CONTRATOS.md) · [Plan de pruebas](./08_PLAN_DE_PRUEBAS.md) · [Bitácora](./09_BITACORA_IMPLEMENTACION.md) · [Decisiones](./10_DECISIONES_Y_BLOQUEOS.md) · [Checklist release](./11_CHECKLIST_RELEASE.md)

## Objetivo

Permitir que Secretaría complete los flujos cotidianos sin conocer IDs internos, sin formularios que contradigan al backend y con acciones, estados y errores comprensibles. La autoridad sobre reglas financieras y de negocio sigue en backend.

## Fuera de alcance

- Reabrir el catálogo RBAC o el ownership de Profesor ya cerrados en Etapa 1.
- Cambiar la fórmula financiera o la resolución por vigencia cerradas en Etapa 1B.
- Hacer un rediseño visual global o crear componentes universales.
- Introducir nuevas librerías de estado, formularios, tablas o selectores.
- Preparar staging, producción o el dataset comercial de Etapa 4.

## Dependencias y condiciones de entrada

- [ ] `GATE-1` y `GATE-1B` constan como cerrados en [00_INDEX.md](./00_INDEX.md).
- [ ] El usuario autorizó explícitamente comenzar Etapa 2 y la autorización quedó en [09_BITACORA_IMPLEMENTACION.md](./09_BITACORA_IMPLEMENTACION.md).
- [ ] La matriz de permisos efectiva está congelada en [02_MATRIZ_RBAC.md](./02_MATRIZ_RBAC.md); ninguna acción se oculta con strings ad hoc.
- [ ] La fuente única de importes y snapshots quedó probada antes de cambiar su presentación.
- [ ] Los fallos baseline están clasificados y no hay una tarea ajena marcada `IN_PROGRESS`.

## Estado actual verificado

- `VALIDADO`: el baseline Git inicial era limpio y coincidía con `b833f6741cf614c508666e8a121701e8db2fcf9a`.
- `VALIDADO`: `npm test` ejecutado en este HEAD terminó con 33/36 tests; falla una prueba de Alumnos por duplicación desktop/mobile y dos de Pagos por esperar `$ 100.50` cuando la UI usa `$ 100,50`.
- `VALIDADO`: Pagos, Usuarios y varios catálogos conservan IDs o referencias técnicas visibles; Caja construye referencias técnicas y las exportaciones incluyen identificadores internos.
- `VALIDADO`: existen mutaciones académicas, de configuración, pagos y stock sin una presentación de acciones completamente alineada con permisos y estados.
- `INFERIDO`: hay selectores de alumnos y disciplinas repetidos; E2-002 debe medir y confirmar el contrato común antes de extraerlo.
- `NO_VERIFICADO`: ningún recorrido completo de Secretaría, responsive real, accesibilidad manual ni backend afectado de Etapa 2 fue ejecutado todavía.
- `PENDING`: no se inició ninguna tarea E2; `GATE-2` permanece abierto.

## Orden obligatorio de tareas

Sólo una tarea puede pasar a `IN_PROGRESS`. Toda finalización debe registrar comandos y resultados en la bitácora.

### E2-001 — Búsqueda humana de alumnos

- **Estado:** `PENDING`.
- **Dependencias:** gates de entrada; contrato RBAC de lectura de alumnos.
- **Archivos esperados:** `backend/src/main/java/gestudio/controladores/AlumnoControlador.java`, `backend/src/main/java/gestudio/servicios/alumno/AlumnoServicio.java`, `backend/src/main/java/gestudio/repositorios/AlumnoRepositorio.java`, DTOs de alumno, `frontend/src/api/alumnosApi.ts` y consumidores.
- **Cambio esperado:** buscar por nombre, apellido, ambos órdenes y documento/DNI; respetar estados del contexto; devolver un resumen humano y usar debounce/teclado accesibles.
- **Estrategia mínima:** ampliar el endpoint/repositorio existente y su DTO; no crear un segundo buscador genérico.
- **Riesgo y rollback lógico:** una consulta más amplia puede degradar paginación o exponer inactivos. Mantener paginación y filtros explícitos; si falla, volver temporalmente al contrato anterior sin tocar datos.
- **Aceptación:** los cuatro modos de búsqueda devuelven resultados determinísticos, sin mostrar IDs, y el teclado permite seleccionar/cerrar.
- **Validación y evidencia:** test PostgreSQL del repositorio, test HTTP del resumen y test frontend de debounce/selección. `NO_VERIFICADO` hasta registrar resultados.

### E2-002 — Selectores reutilizables

- **Estado:** `PENDING`.
- **Dependencias:** `E2-001`.
- **Archivos esperados:** componentes bajo `frontend/src/componentes/comunes/`, Pagos, Inscripciones, Asistencias y Reportes.
- **Cambio esperado:** `AlumnoCombobox` y `DisciplinaCombobox` controlados, con loading/error/empty, teclado, etiqueta humana e ID sólo interno.
- **Estrategia mínima:** extraer únicamente el comportamiento repetido confirmado y migrar primero Pagos, Inscripciones y Asistencias/Reportes.
- **Riesgo y rollback lógico:** una extracción prematura puede perder particularidades. Migrar un consumidor por vez; revertir el consumidor sin cambiar el endpoint compartido.
- **Aceptación:** los consumidores mantienen sus payloads y no duplican el contrato de selección.
- **Validación y evidencia:** tests de componente y tests de cada consumidor migrado. `NO_VERIFICADO`.

### E2-003 — Eliminar IDs visibles

- **Estado:** `PENDING`.
- **Dependencias:** `E2-001`; DTOs humanos disponibles cuando una referencia sea necesaria.
- **Archivos esperados:** `PagosPagina.tsx`, `UsuariosPagina.tsx`, páginas de Métodos de pago, Conceptos, Bonificaciones, Salones, Subconceptos, Recargos, `CajaPagina.tsx`, toasts y exportaciones; DTOs backend afectados.
- **Cambio esperado:** sustituir ID, `alumnoId`, `pagoId` y equivalentes por recibo, alumno, concepto, método, fecha u operador; conservar IDs sólo en rutas, keys y payloads.
- **Estrategia mínima:** cambiar primero la respuesta/DTO que carezca de contexto humano y después su render; no inferir relaciones parseando descripciones.
- **Riesgo y rollback lógico:** ocultar un ID sin reemplazo puede quitar trazabilidad. Cada sustitución exige referencia humana estable; rollback de presentación sin modificar relaciones persistidas.
- **Aceptación:** búsqueda dirigida y revisión manual no encuentran IDs técnicos en flujos operativos, toasts, `aria-label` ni nombres descargados.
- **Validación y evidencia:** tests de render y exportación más auditoría `rg` documentada. `NO_VERIFICADO`.

### E2-004 — Alumnos e Inscripciones

- **Estado:** `PENDING`.
- **Dependencias:** `E2-001`, `E2-002` y permisos académicos de Etapa 1.
- **Archivos esperados:** `AlumnosPagina.tsx`, `AlumnosFormulario.tsx`, `InscripcionesPagina.tsx`, `InscripcionesFormulario.tsx`, APIs/controladores/servicios correspondientes.
- **Cambio esperado:** filtros Activos/Inactivos/Todos; baja y reactivación; no editar un alumno inválido; alumno/disciplina inmutables al editar inscripción; finalizar con fecha/confirmación; accesos rápidos a pagos y condiciones.
- **Estrategia mínima:** reflejar invariantes backend existentes y agregar sólo endpoints faltantes; ninguna acción visible debe depender de que el backend la rechace.
- **Riesgo y rollback lógico:** reactivar/finalizar afecta historia. Usar transiciones explícitas y tests; rollback mediante transición inversa permitida, nunca borrado físico.
- **Aceptación:** las acciones disponibles coinciden con estado y permiso y el formulario de edición no permite cambiar claves inmutables.
- **Validación y evidencia:** unitarios de estados, HTTP 401/403/permitido y pruebas de páginas/formularios. `NO_VERIFICADO`.

### E2-005 — Pagos y Caja

- **Estado:** `PENDING`.
- **Dependencias:** `GATE-1B`, permisos de pagos/caja y `E2-003`.
- **Archivos esperados:** `PagosPagina.tsx`, `PagosFormulario.tsx`, `CajaPagina.tsx`, `pagosApi.ts`, `cajaApi.ts`, DTOs y servicios de Pago/Caja.
- **Cambio esperado:** recibo y origen humanos, ARS/estados consistentes, anulación sólo con permiso, fecha operativa de Buenos Aires, Caja abierta en Hoy, método/alumno/concepto/operador cuando existan.
- **Estrategia mínima:** reutilizar `formatMoney`; obtener fecha de negocio sin `toISOString()` y enriquecer DTOs sin parsear descripciones.
- **Riesgo y rollback lógico:** cambiar fecha o referencia puede alterar conciliación. Caracterizar primero valores actuales; rollback sólo de presentación/consulta, sin mutar pagos o movimientos históricos.
- **Aceptación:** pago, recibo y movimiento de caja se correlacionan humanamente y preservan importe/estado exactos.
- **Validación y evidencia:** tests monetarios, zona horaria, PostgreSQL de pago-caja y recorrido UI. `NO_VERIFICADO`.

### E2-006 — Egresos

- **Estado:** `PENDING`.
- **Dependencias:** permisos de egresos y `E2-003`.
- **Archivos esperados:** `EgresosPagina.tsx`, `egresosApi.ts`, `EgresoControlador.java`, `EgresoServicio.java` y DTOs de egreso/caja.
- **Cambio esperado:** motivo/categoría/observación, método, estado y operador humanos; anulación autorizada con motivo e idempotencia; historial auditable.
- **Estrategia mínima:** completar el caso de uso existente y reutilizar su registro de caja; no crear un flujo financiero paralelo.
- **Riesgo y rollback lógico:** duplicar anulaciones o perder contexto. Exigir idempotencia y transacción; recuperar con el registro de reversión, nunca borrando el egreso.
- **Aceptación:** alta/anulación aparecen una sola vez en historial y caja con actor y motivo.
- **Validación y evidencia:** unitarios, PostgreSQL, HTTP de permiso/idempotencia y UI. `NO_VERIFICADO`.

### E2-007 — Stock

- **Estado:** `PENDING`.
- **Dependencias:** `PERM_STOCK_ADMIN`, `PERM_STOCK_VENDER`, contratos financieros cerrados y `E2-002` si venta selecciona alumno.
- **Archivos esperados:** `StocksPagina.tsx`, `StocksFormulario.tsx`, `stocksApi.ts`, `StockControlador.java`, `StockServicio.java`, DTOs de venta/reversión y movimientos.
- **Cambio esperado:** quitar cantidad del formulario general; usar movimientos/ajustes con motivo; implementar venta guiada, reversión e historial o reducir explícitamente el producto a Inventario.
- **Estrategia mínima:** reutilizar venta, movimiento y reversión existentes; no editar stock directo para simular movimientos.
- **Riesgo y rollback lógico:** stock, cargo y caja pueden divergir. Mantener una transacción y reversión explícita; si la venta no queda probada, ocultarla y declarar alcance reducido.
- **Aceptación:** cantidad sólo cambia por movimientos trazables y venta/reversión conservan consistencia.
- **Validación y evidencia:** tests PostgreSQL de stock/cargo/caja, permisos y UI guiada. `NO_VERIFICADO`.

### E2-008 — Asistencias

- **Estado:** `PENDING`.
- **Dependencias:** ownership Profesor de Etapa 1 y `E2-002`.
- **Archivos esperados:** formularios diario/mensual, `asistenciasApi.ts`, controladores, servicios y repositorios de asistencia.
- **Cambio esperado:** Diario como flujo primario; PRESENTE/AUSENTE/JUSTIFICADO; marcar todos; guardado fiable con estado visible; debounce cancelable; consulta histórica y navegación coherente.
- **Estrategia mínima:** corregir el flujo existente y su contrato de guardado; no agregar otra caché o estado global.
- **Riesgo y rollback lógico:** autosave/debounce puede perder cambios o cruzar alumnos. Cancelar pendientes al cambiar contexto y mantener operación explícita de reintento; rollback al guardado manual si no se prueba autosave.
- **Aceptación:** ningún cambio silencioso se pierde y Profesor sólo opera sus disciplinas.
- **Validación y evidencia:** unitarios de transición/debounce, integración de lote, ownership con dos profesores y flujo UI. `NO_VERIFICADO`.

### E2-009 — Usuarios, Roles y Catálogos

- **Estado:** `PENDING`.
- **Dependencias:** Etapa 1 cerrada y decisiones de baja lógica confirmadas.
- **Archivos esperados:** páginas/formularios de Usuarios, Roles, Salones, Métodos de pago, Conceptos, Bonificaciones, Subconceptos y Recargos; servicios/controladores afectados.
- **Cambio esperado:** estado visible; Desactivar/Reactivar; reglas `sistema/editable` alineadas; permisos humanos agrupados y delegables; corregir Acciones duplicadas; implementar o retirar acciones no-op; baja lógica cuando exista historia.
- **Estrategia mínima:** usar estados y endpoints existentes; retirar una acción incompleta antes que simularla.
- **Riesgo y rollback lógico:** una reactivación o baja puede alterar referencias históricas o escalamiento. Probar referencias/delegación y revertir por cambio de estado, no por borrado.
- **Aceptación:** etiquetas y acciones reflejan el efecto real y ningún catálogo histórico se elimina físicamente sin decisión documentada.
- **Validación y evidencia:** tests de servicio/HTTP por estado y permiso, más tests de páginas y headers. `NO_VERIFICADO`.

### E2-010 — Tests UX y flujo Secretaría

- **Estado:** `PENDING`.
- **Dependencias:** `E2-001` a `E2-009`.
- **Archivos esperados:** tests frontend existentes, tests backend afectados, `scripts/smoke-local.ps1` y [08_PLAN_DE_PRUEBAS.md](./08_PLAN_DE_PRUEBAS.md).
- **Cambio esperado:** corregir los tres tests baseline sin debilitar intención; cubrir alumno → inscripción → cargo → pago → caja, errores y vacíos.
- **Estrategia mínima:** ajustar queries responsive y expectativas al formatter real; preferir tests públicos por flujo.
- **Riesgo y rollback lógico:** tests indulgentes pueden esconder regresiones. Mantener aserciones de contrato; revertir sólo fixtures/queries que no representen al usuario.
- **Aceptación:** suite frontend verde, backend afectado verde y recorrido de Secretaría reproducible.
- **Validación y evidencia:** comandos de validación Frontend, Backend y All registrados con conteos. `NO_VERIFICADO`.

## Estrategia transversal

1. Caracterizar antes de modificar cada flujo.
2. Cambiar contrato backend y frontend juntos cuando falte contexto humano.
3. Migrar un consumidor por vez; no hacer reemplazos masivos.
4. Mantener IDs en relaciones/payloads y eliminarlos sólo de la presentación.
5. Aplicar permisos tanto en UI como en backend; la UI nunca es defensa suficiente.
6. Registrar toda ampliación de alcance en [10_DECISIONES_Y_BLOQUEOS.md](./10_DECISIONES_Y_BLOQUEOS.md).

## Validación por tarea

Durante cada tarea se ejecuta el test más cercano. Antes de cerrar el gate:

```powershell
Push-Location .\frontend
try {
    npm test
    npm run lint
    npm run build
}
finally {
    Pop-Location
}

Push-Location .\backend
try {
    if (Test-Path ".\mvnw.cmd") { .\mvnw.cmd clean verify }
    else { mvn clean verify }
}
finally {
    Pop-Location
}

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
```

Los flujos que dependan de PostgreSQL deben usar Testcontainers/base descartable. Los resultados se registran en [09_BITACORA_IMPLEMENTACION.md](./09_BITACORA_IMPLEMENTACION.md).

## GATE-2

- [ ] Cero IDs técnicos visibles en flujos operativos.
- [ ] Búsqueda real por nombre, apellido, ambos órdenes y DNI/documento.
- [ ] Ningún formulario ofrece una acción que contradiga una invariante conocida.
- [ ] Caja, recibos y referencias financieras son humanas y auditables.
- [ ] Stock, Egresos y Asistencia tienen flujo completo o alcance reducido explícitamente.
- [ ] Permisos de menú, ruta y acción siguen alineados con backend.
- [ ] `npm test`, `npm run lint` y `npm run build` terminan correctamente.
- [ ] Backend afectado y validación `All` terminan correctamente.
- [ ] El recorrido de Secretaría fue ejecutado y documentado.
- [ ] Documentación y bitácora reflejan la evidencia final.

**Estado del gate:** `PENDING` / no evaluado. Al cerrarlo, detenerse y pedir autorización explícita para Etapa 3.
