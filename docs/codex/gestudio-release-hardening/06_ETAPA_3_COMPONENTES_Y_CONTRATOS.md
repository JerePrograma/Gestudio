# Etapa 3 — Componentes y contratos reutilizables

> Estado: `PENDING`  
> Gate previo requerido: `GATE-2` cerrado y autorización explícita  
> Gate de salida: `GATE-3`  
> Baseline documental: `main` en `b833f6741cf614c508666e8a121701e8db2fcf9a`

[Índice](./00_INDEX.md) · [Baseline](./01_BASELINE_Y_HALLAZGOS.md) · [Matriz RBAC](./02_MATRIZ_RBAC.md) · [Etapa 2](./05_ETAPA_2_UX_OPERATIVA.md) · [Etapa 4](./07_ETAPA_4_DEMO_Y_PUBLICACION.md) · [Plan de pruebas](./08_PLAN_DE_PRUEBAS.md) · [Bitácora](./09_BITACORA_IMPLEMENTACION.md) · [Decisiones](./10_DECISIONES_Y_BLOQUEOS.md) · [Checklist release](./11_CHECKLIST_RELEASE.md)

## Objetivo

Reducir duplicación comprobada después de Etapa 2 sin crear un framework propio. Cada extracción debe tener consumidores reales, un contrato pequeño y pruebas de comportamiento.

## Fuera de alcance

- CRUD, formulario o tabla universales.
- Un framework nuevo de permisos, rutas, estado o formularios.
- Reescribir flujos de negocio cerrados en etapas anteriores.
- Refactor visual completo, design system nuevo o cambio de librerías.
- Preparación de demo, staging y producción de Etapa 4.

## Dependencias y condiciones de entrada

- [ ] `GATE-2` cerrado en [00_INDEX.md](./00_INDEX.md) y autorización de Etapa 3 registrada.
- [ ] Flujos UX estabilizados; no extraer componentes mientras su contrato siga cambiando.
- [ ] Matriz RBAC y metadata de rutas vigentes disponibles.
- [ ] Baseline de duplicación medido antes de decidir cada extracción.
- [ ] Sólo una tarea del plan está `IN_PROGRESS`.

## Estado actual verificado

- `VALIDADO`: ya existen utilidades/componentes útiles (`filterNavigationItems`, `formatMoney`, `getApiErrorMessage`, tabla responsive y estados comunes); deben reutilizarse.
- `RESUELTO EN GATE-1`: `PermissionCode` tipa rutas, navegación, gates y auth; no quedan literales productivos `PERM_*` fuera del catálogo.
- `RESUELTO EN GATE-1`: rutas y permisos tienen cobertura exhaustiva y un contrato frontend que falla ante divergencias; la suite vigente cubre 21 archivos y 140 tests.
- `VALIDADO`: la tabla responsive duplica deliberadamente contenido desktop/mobile y un test usa una query singular incompatible con ese DOM.
- `INFERIDO`: selectores y formateos restantes pueden estar duplicados, pero sólo E3-001 puede confirmarlos después de Etapa 2.
- `NO_VERIFICADO`: no se midió aún duplicación post-Etapa 2 ni accesibilidad de los candidatos.
- `PENDING`: ninguna tarea E3 fue iniciada; `GATE-3` está abierto.

## Candidatos permitidos

`PermissionGate`/`Can`, `AlumnoCombobox`, `DisciplinaCombobox`, `ConfirmActionDialog`, `formatMoney`, `formatLocalDate`, etiquetas de estado, `getApiErrorMessage`, metadata única ruta/permiso/navegación y helpers de tests para tabla responsive. Un candidato sin al menos dos consumidores reales se descarta o permanece local.

## Orden obligatorio de tareas

### E3-001 — Medir duplicación restante

- **Estado:** `PENDING`.
- **Dependencias:** `GATE-2`.
- **Archivos esperados:** `frontend/src/`, con inventario en este documento y baseline en la bitácora.
- **Cambio esperado:** mapa de duplicaciones por contrato y consumidores; ninguna edición productiva todavía.
- **Estrategia:** `rg`, comparación de comportamiento y conteo de consumidores; conservar implementaciones locales cuando no haya contrato común.
- **Riesgo/rollback:** confundir similitud visual con igualdad funcional. La tarea es sólo diagnóstico; retirar candidatos no demostrados.
- **Aceptación:** cada candidato tiene evidencia, consumidores y beneficio concreto.
- **Validación/evidencia:** búsquedas/comparación documentadas. `NO_VERIFICADO`.

### E3-002 — Consolidar formatters y mensajes

- **Estado:** `PENDING`.
- **Dependencias:** `E3-001`.
- **Archivos esperados:** `frontend/src/utils/money.ts`, utilidades de fecha/estado, `frontend/src/api/apiError.ts` y consumidores medidos.
- **Cambio esperado:** una implementación para moneda, fecha local, estados y mensajes equivalentes.
- **Estrategia:** extender utilidades existentes antes de crear otra; migrar un formato por vez.
- **Riesgo/rollback:** cambiar representación financiera o zona horaria. Caracterizar entradas límite; revertir consumidores sin tocar datos.
- **Aceptación:** no quedan fórmulas/formateos duplicados para el mismo contrato.
- **Validación/evidencia:** unitarios de precisión monetaria, zona horaria, estados y errores. `NO_VERIFICADO`.

### E3-003 — Consolidar confirmaciones accesibles

- **Estado:** `PENDING`.
- **Dependencias:** `E3-001`; acciones de Etapa 2 estables.
- **Archivos esperados:** componente común sólo si se confirman consumidores; páginas con `window.confirm` y pruebas.
- **Cambio esperado:** confirmación accesible para acciones destructivas/reversibles con foco, teclado, estado pending y texto específico.
- **Estrategia:** un contrato mínimo `title/message/confirm/cancel/pending`; no motor genérico de formularios.
- **Riesgo/rollback:** doble ejecución o pérdida de foco. Bloquear confirmación pendiente y mantener callbacks idempotentes; volver al diálogo local si un flujo no encaja.
- **Aceptación:** al menos dos consumidores reales comparten el componente sin flags de negocio internos.
- **Validación/evidencia:** tests de foco, teclado, cancelación y una sola confirmación. `NO_VERIFICADO`.

### E3-004 — Consolidar rutas, permisos y navegación

- **Estado:** `PENDING`.
- **Dependencias:** matriz RBAC cerrada, `E3-001`.
- **Archivos esperados:** `frontend/src/config/permissions.ts`, `navigation.ts`, `frontend/src/rutas/routes.ts`, `AppRouter.tsx`, `ProtectedRoute.tsx` y `PermissionGate` si ya existe.
- **Cambio esperado:** metadata única o un contrato explícito que impida divergencias; `/unauthorized` sigue accesible a todo autenticado.
- **Estrategia:** reutilizar la estructura más pequeña existente y tipar con `PermissionCode`; no crear un router propio.
- **Riesgo/rollback:** bloquear rutas válidas u ocultar navegación. Mantener caso autenticado-sin-permiso y migrar rutas en tabla; rollback a metadata anterior conservando tests.
- **Aceptación:** cada ruta protegida tiene política explícita y menú/ruta/acción usan el mismo código.
- **Validación/evidencia:** tests parametrizados de metadata, navegación y acceso directo. `NO_VERIFICADO`.

### E3-005 — Remover implementaciones duplicadas migradas

- **Estado:** `PENDING`.
- **Dependencias:** `E3-002` a `E3-004` verdes.
- **Archivos esperados:** sólo duplicados listados por `E3-001` cuyos consumidores ya fueron migrados.
- **Cambio esperado:** borrar helpers/componentes sin consumidores y imports muertos.
- **Estrategia:** probar equivalencia, migrar todos los callers, buscar referencias y recién entonces eliminar.
- **Riesgo/rollback:** borrar una variante todavía necesaria. Reponer el archivo desde el diff local si aparece un caller; no hacer eliminación masiva.
- **Aceptación:** `rg` no encuentra callers viejos, TypeScript compila y no queda compatibilidad temporal sin uso.
- **Validación/evidencia:** tests de consumidores, lint, build y `rg` de referencias. `NO_VERIFICADO`.

### E3-006 — Contrato automatizado de rutas y permisos

- **Estado:** `PENDING`.
- **Dependencias:** `E3-004`.
- **Archivos esperados:** tests junto a `routes.ts`, `navigation.ts`, `ProtectedRoute` y `PermissionGate`.
- **Cambio esperado:** una prueba falla si una ruta protegida carece de política, si navegación diverge o si aparece un string ad hoc.
- **Estrategia:** test de datos parametrizado sobre metadata exportada; sin snapshots grandes ni parser de código propio.
- **Riesgo/rollback:** test demasiado rígido. Afirmar contratos de seguridad, no orden o presentación irrelevantes.
- **Aceptación:** casos permitido/denegado y excepción autenticada `/unauthorized` están cubiertos.
- **Validación/evidencia:** suite de contrato y suite frontend completa. `NO_VERIFICADO`.

### E3-007 — Limpiar código muerto confirmado y logs de datos

- **Estado:** `PENDING`.
- **Dependencias:** `E3-005`, inventario de logs y seguridad.
- **Archivos esperados:** módulos sin callers confirmados y logs frontend/backend identificados; no archivos operativos ni históricos.
- **Cambio esperado:** retirar código muerto y logs de payloads/datos personales; conservar logs operativos por ID/estado/resultado.
- **Estrategia:** verificar referencias y comportamiento antes de borrar; no ampliar a formateo masivo.
- **Riesgo/rollback:** perder diagnóstico o borrar entrada dinámica. Mantener eventos operativos mínimos; restaurar sólo el punto necesario.
- **Aceptación:** no hay `console.log`/logs de payloads sensibles ni módulos confirmados sin uso dentro del alcance.
- **Validación/evidencia:** búsquedas, lint, build y suites afectadas. `NO_VERIFICADO`.

## Estrategia transversal

1. Medir primero; extraer sólo contratos estables.
2. Preferir utilidad/componente ya existente.
3. Migrar y validar un consumidor por vez.
4. Eliminar el duplicado sólo después de equivalencia probada.
5. No agregar dependencias para resolver estos candidatos.

## Validación por tarea

Cada tarea ejecuta sus tests focalizados. Antes del gate:

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

powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
git diff --check
```

Registrar comandos, conteos y fallos clasificados en [09_BITACORA_IMPLEMENTACION.md](./09_BITACORA_IMPLEMENTACION.md).

## GATE-3

- [ ] No quedan strings de permisos ad hoc.
- [ ] Rutas, navegación y acciones no divergen.
- [ ] Selectores equivalentes no están triplicados.
- [ ] Moneda, fechas, estados y mensajes usan contratos consistentes.
- [ ] Componentes extraídos son accesibles, testeados y tienen consumidores reales.
- [ ] No se introdujo CRUD/formulario/tabla/framework universal.
- [ ] Código duplicado o muerto sólo se eliminó después de probar equivalencia.
- [ ] Suite completa, lint, build y validación `All` terminan correctamente.
- [ ] Documentación y bitácora están actualizadas.

**Estado del gate:** `PENDING` / no evaluado. Al cerrarlo, detenerse y pedir autorización explícita para Etapa 4.
