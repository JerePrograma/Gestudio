# Frontend massive refactor plan

## Baseline e inventario

- Fecha: 2026-07-06 (America/Buenos_Aires).
- Rama y commit: `main`, `0df8b891bab5c89215f10635d0a680cc5f9fa62a`.
- El worktree inicial ya contiene cambios locales en `authSession.ts`,
  `axiosConfig.ts`, `environment.ts`, `authContext.tsx` y `vite-env.d.ts`. Son
  trabajo preexistente y deben preservarse.
- No existe un `AGENTS.md` más específico bajo `frontend/`.
- El frontend contiene 40 archivos de funcionalidades, 27 de API, 27 de
  componentes, 15 hooks/contextos, 15 esquemas de validación y 7 archivos de
  test.
- Módulos funcionales presentes: alumnos, inscripciones, disciplinas,
  profesores, salones, asistencias diarias y mensuales, cargos/mensualidades,
  pagos, caja/egresos, stock, conceptos/subconceptos, métodos de pago,
  bonificaciones/recargos, reportes, observaciones, usuarios y roles.

### Gate inicial

| Comando | Resultado |
| --- | --- |
| `git status --short --branch` | PASS; `main` con cinco archivos frontend modificados previamente |
| `git rev-parse HEAD` | PASS; `0df8b891bab5c89215f10635d0a680cc5f9fa62a` |
| `frontend\\npm ci` | PASS; 434 paquetes instalados |
| `frontend\\npm run lint` | PASS |
| `frontend\\npm test` | PASS; 7 archivos, 17 tests |
| `frontend\\npm run build` | PASS; TypeScript y Vite, 2.269 módulos |
| `scripts\\codex\\validate.ps1 -Scope Frontend` | PASS; lint, test y build |

## Problemas reales detectados

### Aplicación, rutas y layout

- `main.tsx` y `App.tsx` aplican `StrictMode`; la segunda envoltura es
  redundante.
- `MainLayout` envuelve también `/login` y `/unauthorized`, por lo que las rutas
  públicas montan header, sidebar y efectos privados.
- `AuthProvider` navega a `/login` mientras `ProtectedRoute` implementa el mismo
  redirect. Esa doble autoridad puede producir navegación redundante.
- Las rutas administrativas están divididas en dos grupos contiguos con el mismo
  guard. No existe fallback explícito para rutas desconocidas.
- Los fallbacks de carga son `div` ad hoc y no exponen estado accesible.
- Hay comentarios de migración y directivas `use client` heredadas de Next.js
  en una aplicación Vite.

Archivos principales: `main.tsx`, `App.tsx`, `rutas/*`,
`componentes/layout/MainLayout.tsx`, `hooks/context/authContext.tsx`.

### Sesión y cliente HTTP

- La sesión en memoria, el refresh compartido y el tratamiento diferenciado de
  401/403 ya existen y tienen regresiones. Deben conservarse como fuente única.
- Los cambios locales actuales endurecen además headers y endpoints de auth; no
  deben reemplazarse ni duplicarse.
- El interceptor todavía mezcla transporte con toast global y navegación
  imperativa. La redirección por refresh fallido es una excepción de borde que
  debe quedar centralizada; los errores de negocio pertenecen a la UI.
- Login emite mensajes duplicados porque el contexto y la pantalla muestran el
  mismo fallo.
- Los clientes de asistencias y subconceptos contienen toasts y, en asistencias,
  una caché `Map` paralela a React Query.

Archivos principales: `api/authSession.ts`, `api/axiosConfig.ts`,
`api/asistenciasApi.ts`, `api/subConceptosApi.ts`, `paginas/Login.tsx`.

### Contratos y tipos

- `types/types.ts` concentra 618 líneas de dominios no relacionados, aliases,
  enums, request y response. Esto aumenta el radio de cambio y facilita drift.
- Hay respuestas Axios sin genérico y tipos locales que duplican DTOs, por
  ejemplo en disciplinas.
- `Page` y `PageResponse` representan la misma respuesta paginada.
- Fechas y horas tienen aliases, pero se usan de forma inconsistente como
  `string` directo.
- Varias propiedades opcionales reflejan formularios locales y no necesariamente
  la nulabilidad del backend. La separación por dominio debe hacerse por cortes
  con build verde, no mediante una conversión masiva a ciegas.
- Los contratos monetarios canónicos comprobados usan strings decimales; esa
  representación se conserva en inscripciones, disciplinas, cargos, pagos,
  caja, egresos y stock.

Archivos principales: `types/types.ts`, `api/*.ts`, formularios y páginas que
consumen esos DTOs.

### Estado remoto y React Query

- Alumnos, inscripciones, cargos, pagos, caja, egresos y stock ya tienen parte
  del camino canónico: páginas reales y keys con página/tamaño/orden.
- Muchas pantallas de catálogos, usuarios, disciplinas, reportes y asistencias
  aún hacen fetch en `useEffect`, copian respuestas a `useState` y administran
  loading/error manualmente.
- `queryKeys.ts` sólo cubre ocho recursos; faltan detalle, catálogos y dominios
  que ya consumen React Query o deberían hacerlo.
- Algunas invalidaciones usan arrays literales en lugar de builders y varias
  mutaciones llaman APIs directamente desde handlers.
- Disciplinas descarga la colección y aplica filtro/orden/paginación visual en
  memoria. Sólo debe conservarse carga manual donde el backend no tenga un
  contrato paginado canónico; no se inventará infinite scroll.

Archivos principales: `hooks/queryKeys.ts`, páginas bajo `funcionalidades/`,
`paginas/Reportes.tsx` y APIs asociadas.

### Componentes, formularios y accesibilidad

- No hay estados compartidos de loading, error, empty ni controles de
  paginación; se repiten bloques y mensajes inconsistentes.
- `Tabla` usa índices como keys de filas y celdas, recalcula `customRender` para
  la variante móvil y no permite declarar una key estable.
- Las búsquedas dependen sólo de placeholder; varios botones de icono y estados
  de submit no expresan claramente la operación en curso.
- Los formularios canónicos de alumnos/inscripciones ya son pequeños, pero usan
  fetch manual, errores genéricos y no mapean `ApiErrorResponse.fieldErrors`.
- Los campos monetarios son `text` con `inputMode=decimal`, pero no comparten
  normalización, descripción ni asociación accesible de errores.
- Las bajas/eliminaciones suelen ejecutarse sin confirmación uniforme.
- Asistencia diaria y mensual mezclan fetch, transformación, edición y render en
  archivos de 522 y 525 líneas; requieren caracterización antes de separarlos.

Archivos principales: `componentes/comunes/*`, formularios y páginas críticas,
`api/apiError.ts`, `utils/money.ts`.

### Tests y limpieza

- Los 17 tests actuales protegen dinero, errores API, query keys, configuración,
  refresh, login y paginación de alumnos. Son una base útil pero pequeña frente
  a los dominios existentes.
- Faltan regresiones de layout público/privado, rutas protegidas, estados
  comunes, keys estables, field errors, formularios monetarios y paginación
  compartida.
- Existen comentarios obsoletos, imports directos del cliente Axios desde
  componentes, directivas `use client`, un asset Vite sin consumidor potencial
  y nombres con errores como `AlumnosPorDIsciplina`.
- La eliminación de archivos/dependencias sólo se hará después de comprobar
  consumidores con búsqueda y build.

## Decisiones y fases

Cada fase corresponde a un commit lógico propuesto; no se crearán commits sin
autorización explícita.

1. **Cimientos de aplicación.** Quitar el `StrictMode` duplicado, separar layout
   público y autenticado en el router, dejar el redirect en `ProtectedRoute`,
   agregar fallback accesible y ruta desconocida. Preservar la sesión en memoria
   y sus tests.
2. **Primitivas compartidas.** Agregar sólo componentes que eliminan repetición
   demostrada: `LoadingState`, `ErrorState`, `EmptyState`,
   `PaginationControls`, `FormField`, `MoneyInput` y confirmación nativa o el
   diálogo Radix ya instalado. Mejorar `Tabla` con `getRowKey` obligatorio.
3. **Contratos transversales.** Robustecer `apiError`, builders de query keys y
   normalización de formularios. Separar tipos por dominio gradualmente y
   conservar un punto de reexportación temporal para no producir un cambio
   mecánico descontrolado.
4. **Slices canónicos prioritarios.** Migrar alumnos, inscripciones,
   disciplinas, pagos, caja, egresos, stock y usuarios/roles a queries/mutations
   con estados comunes, keys completas, invalidaciones acotadas y formularios
   con field errors. Mantener paginación backend donde existe.
5. **Asistencias y reportes.** Caracterizar primero los requests y estados
   editables; extraer queries/transformaciones sólo cuando reduzca el archivo y
   no cambie el contrato. No convertir edición local de una planilla en estado
   remoto antes del submit.
6. **Limpieza y cobertura.** Eliminar UI en clientes API, cachés paralelas,
   comentarios/directivas obsoletos y código sin consumidores comprobados.
   Agregar tests de comportamiento, no snapshots masivos.

## Riesgos y mitigaciones

- **Cambios locales de auth:** trabajar alrededor de ellos, revisar el diff en
  cada gate y no restaurar versiones de `HEAD`.
- **Contratos frontend/backend divergentes:** contrastar cada request/response
  con controlador y DTO Java antes de cambiar el tipo; el frontend se adapta.
- **Dinero:** ninguna conversión numérica ni fórmula local; usar `money.ts` y
  testear normalización/errores antes de conectar formularios.
- **Colecciones grandes:** conservar `Page` y navegación explícita; no usar
  `useInfiniteQuery` ni endpoints completos como reemplazo de paginación.
- **Asistencias:** sus pantallas grandes contienen edición local legítima; no
  confundir borradores UI con caché remota.
- **Refactor amplio:** aplicar cortes verticales pequeños y ejecutar gates antes
  de avanzar al siguiente dominio.

## Gates

Después de cada fase grande:

```powershell
Push-Location frontend
try {
    npm run lint
    npm test
    npm run build
}
finally {
    Pop-Location
}
.\scripts\codex\validate.ps1 -Scope Frontend
```

Al cierre:

```powershell
.\scripts\codex\validate.ps1 -Scope All
docker compose config --quiet
git diff --check
git status --short --branch
```

También se revisarán `npm ls`, usos de `any`, conversiones numéricas cerca de
importes, `localStorage` de auth, navegación imperativa, copias de estado remoto
y cargas completas. `Number` seguirá siendo válido para IDs, páginas, meses y
otros enteros no monetarios.

## Fuera de alcance deliberado

- Backend, Flyway, entidades, seguridad backend y contratos HTTP: no se cambian
  sin incompatibilidad reproducida. El relevamiento actual no exige hacerlo.
- Rediseño visual global: se conserva el lenguaje existente y se corrigen sólo
  consistencia, estados y accesibilidad funcional.
- Nueva librería de estado, formularios, tablas, fechas, dinero o tests: el
  stack instalado cubre el trabajo.
- Data table genérica, capa de repositorios frontend, codegen o una arquitectura
  de múltiples capas: no pagan alquiler para este repositorio.
- Optimización por memoización indiscriminada: sólo se aplicará si elimina un
  cálculo observable o estabiliza una dependencia real.
- Reescritura simultánea de todas las pantallas y tipos: el tamaño aparente del
  diff no justifica perder validación incremental.
