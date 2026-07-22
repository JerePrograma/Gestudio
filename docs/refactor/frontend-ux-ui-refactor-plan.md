# Plan de refactor UX/UI del frontend

Fecha de baseline: 2026-07-07  
Rama: `main`  
HEAD: `0df8b891bab5c89215f10635d0a680cc5f9fa62a`

## Alcance y guardas

Este trabajo modifica exclusivamente presentación y experiencia de uso del
frontend React. No cambia reglas de negocio, contratos HTTP, cálculos,
persistencia, backend, Flyway ni seguridad backend.

El worktree ya contiene un refactor local amplio previo al inicio de esta
fase. Esos cambios se preservan. En particular, no se revierten los cambios de
sesión, API, rutas, queries, tipos ni tests que ya estaban presentes; el trabajo
visual se construye encima de ese estado sin ampliar su alcance funcional.

## Baseline ejecutado

| Comando | Resultado |
| --- | --- |
| `git status --short --branch` | PASS; rama `main`, con cambios locales previos extensos bajo `frontend/` y documentación no trackeada |
| `git rev-parse HEAD` | PASS; `0df8b891bab5c89215f10635d0a680cc5f9fa62a` |
| `cd frontend; npm ci` | PASS; 434 paquetes instalados |
| `cd frontend; npm run lint` | PASS |
| `cd frontend; npm test` | PASS; 9 archivos, 21 tests |
| `cd frontend; npm run build` | PASS; TypeScript y Vite, 2.274 módulos transformados |
| `.\scripts\codex\validate.ps1 -Scope Frontend` | PASS; lint, test y build |

## Diagnóstico visual actual

La interfaz tiene una base Tailwind/Radix reutilizable, pero no existe hoy un
contrato visual único aplicado de extremo a extremo. La captura del login
renderizado confirma una pantalla casi sin contenedor, sin marca, con título
desalineado respecto del formulario y demasiado espacio muerto. En las rutas
administrativas, la lectura de los componentes muestra el mismo problema:
shell, tablas, formularios y estados comparten nombres de clase pero no una
composición coherente.

El problema más concreto del estado actual es que muchas pantallas usan clases
como `page-title`, `page-card`, `page-button`, `page-button-secondary`,
`page-button-danger`, `auth-label` y `auth-error`, pero esas clases no están
definidas en el stylesheet activo. Los antiguos stylesheets por pantalla están
eliminados en el worktree. El build pasa porque Tailwind no valida semántica de
clases; visualmente, sin embargo, la jerarquía queda degradada.

Otros problemas detectados:

- La paleta clara usa un rosa demasiado pálido como acción primaria y neutros
  cálidos de poco contraste. El modo oscuro cambia la marca a violeta y pierde
  continuidad con la identidad visual de Gestudio.
- `color-scheme: light dark` en `:root` deja controles nativos oscuros aunque la
  aplicación todavía esté en tema claro según el sistema.
- La escala tipográfica y de espaciado usa `clamp()` de forma excesiva; tablas y
  formularios crecen innecesariamente en desktop y reducen densidad útil.
- `MainLayout` suma padding superior dos veces: el shell ya reserva el header y
  `.page-container` vuelve a agregar `--header-height`.
- El contenido usa `min-height: 100vh` repetidamente, produciendo espacio vacío
  artificial y scroll vertical innecesario.
- Sidebar y topbar son blancos sobre fondo casi blanco, separados sólo por
  bordes muy débiles. No hay agrupación visual fuerte ni contexto de página.
- El buscador del topbar no tiene comportamiento conectado; visualmente parece
  una capacidad global real que no existe.
- El estado activo del sidebar ocupa todo el ancho con rosa pálido y el árbol
  de subitems no comunica bien jerarquía, expansión ni sección actual.
- `Tabla` centra todas las columnas, incluidos nombres y descripciones; los
  headers son poco contrastados y las acciones por fila dominan el contenido.
- Varias páginas todavía renderizan `<table>` crudas y no heredan el patrón
  compartido de densidad, bordes, estados ni columnas numéricas.
- En móvil, las cards de `Tabla` centran todos los campos y repiten títulos sin
  una separación escaneable entre etiqueta y valor.
- Los formularios mezclan `.form-input`, inputs sin clase, labels de auth y
  grids ad hoc. `Registrar pago` es el caso más crítico: no tiene paneles,
  ayuda progresiva, estados de cargos ni CTA consolidado.
- Caja presenta el resumen financiero como cuatro párrafos y no como métricas
  ejecutivas diferenciadas.
- Egresos no separa claramente la operación de alta del historial.
- `EmptyState`, `LoadingState` y `ErrorState` existen, pero son sólo texto
  centrado; no ofrecen iconografía, contenedor, título/ayuda ni una altura
  estable.
- `Boton` y el primitivo `ui/button` duplican parte del contrato visual.
  Durante este refactor se conservará `Boton`, ya usado por las pantallas, y se
  le darán variantes reales sin migración mecánica masiva.
- Los importes no tienen una declaración visual consistente de alineación
  tabular; se conserva el formateo y la autoridad actual de `money.ts`.

## Pantallas afectadas

Prioridad alta:

- shell autenticado: sidebar, topbar y contenedor principal;
- login, como puerta de entrada y prueba del sistema visual;
- Alumnos e Inscripciones;
- Registrar pago y listado de Pagos;
- Caja y Egresos;
- Asistencia diaria;
- Profesores;
- Conceptos, Métodos de pago y Stock.

Prioridad de consistencia:

- Disciplinas, salones, bonificaciones, recargos, subconceptos, usuarios,
  roles, reportes y formularios de alta/edición que ya consumen las mismas
  clases compartidas.

## Componentes afectados y consolidaciones

- `MainLayout`, `Header`, `Sidebar`, `NavGroup`.
- `Boton`, `Tabla`, `PaginationControls`, `EmptyState`, `LoadingState`,
  `ErrorState`, `FormField` y `MoneyInput`.
- Se crearán sólo primitivas con reutilización inmediata:
  `PageHeader`, `SectionCard`, `StatCard`, `FilterBar`, `StatusBadge` y
  `RowActions`.
- No se creará un framework de formularios ni una segunda data table. Los
  formularios existentes adoptarán `SectionCard`, `.form-grid` y las clases de
  campo compartidas.

## Criterios visuales nuevos

### Color y superficie

- Primario rosa coral oscuro y accesible para CTA, foco y estado activo.
- Fondo marfil rosado muy leve; superficies blancas definidas por borde,
  sombra corta y contraste suficiente.
- Neutros tinta para texto principal y gris ciruela para texto secundario.
- Estados semánticos independientes: éxito, advertencia, error e información.
- Modo oscuro alineado con el mismo rosa coral, no violeta.

### Tipografía y jerarquía

- Fuente del sistema para rendimiento y consistencia nativa.
- Título de página entre 1.5 y 1.875 rem, peso 700; subtítulo y contador en
  escala compacta.
- Texto base de 0.9375 rem en superficies administrativas; tablas a 0.875 rem.
- Números monetarios con `font-variant-numeric: tabular-nums` y alineación a la
  derecha cuando la columna lo permita.

### Espaciado y densidad

- Escala fija basada en 4 px para evitar crecimiento impredecible.
- Contenido con ancho máximo amplio (`1600px`) y padding responsive de 16 a
  32 px.
- Cards de 16 a 24 px de padding; filas de tabla de 44 a 52 px.
- Formularios en grid de 1/2 columnas con secciones explícitas y acciones al
  pie.

### Interacción y accesibilidad

- Foco visible de alto contraste en todos los controles.
- Hover sin desplazamientos de layout ni animaciones decorativas.
- Disabled con contraste legible y cursor/aria coherentes.
- Botones de icono con nombre accesible; acciones destructivas separadas.
- Estados de carga con spinner CSS respetando `prefers-reduced-motion`.
- Empty/error states con icono, título, ayuda y acción opcional.

## Fases del refactor

1. **Sistema visual base.** Rehacer tokens y estilos globales activos;
   restituir las clases compartidas que hoy no tienen definición; normalizar
   botones, inputs, cards, tablas, badges, foco y estados.
2. **Shell y navegación.** Corregir doble offset vertical, refinar sidebar,
   grupos, topbar y comportamiento responsive. El buscador global se presenta
   como acceso visual neutro o se retira si no ejecuta ninguna acción real.
3. **Primitivas pagas.** Crear las seis primitivas mínimas y conectar
   `Tabla`, paginación y estados compartidos.
4. **Listados administrativos.** Aplicar un mismo encabezado, toolbar, tabla,
   badges y acciones a Alumnos, Inscripciones, Profesores, Conceptos, Métodos
   de pago y Stock; extender el patrón a catálogos equivalentes.
5. **Flujos operativos.** Reorganizar visualmente Registrar pago/Pagos, Caja,
   Egresos y Asistencia diaria sin alterar handlers, payloads ni queries.
6. **Formularios.** Aplicar panel, secciones, grillas y barra de acciones a los
   formularios de alta/edición prioritarios.
7. **Estados y limpieza.** Uniformar empty/loading/error, eliminar clases y
   comentarios visuales muertos sólo cuando no tengan consumidores, y revisar
   responsive/foco.

Cada fase grande termina con lint, tests, build y validación frontend. No se
avanza con errores introducidos por la fase.

## Riesgos

- **Worktree previo extenso:** los cambios ya existentes mezclan UI con auth,
  API y queries. Se evita editar esos contratos y se revisa el diff por ruta.
- **Falta de backend autenticado durante QA visual:** la UI protegida puede no
  estar disponible en navegador sin credenciales. La validación visual se hará
  sobre rutas accesibles y, para el resto, por composición renderizada y tests
  existentes; no se desactiva autenticación para inspeccionar pantallas.
- **Tablas con columnas variables:** `Tabla` recibe arrays renderizados; la
  alineación se aplicará con defaults y wrappers explícitos, sin inferir tipos
  de dominio.
- **Pantallas grandes de asistencia:** no se separará su estado ni lógica. Sólo
  se modificará su JSX/clases en bloques localizados.
- **Dinero:** no se recalcula ni normaliza en UI durante este trabajo; sólo se
  formatea y alinea visualmente mediante utilidades existentes.
- **Modo oscuro:** se conserva porque ya está instalado y conectado; los tokens
  se ajustan en paralelo para evitar degradarlo.

## Decisiones explícitas de no alcance

- No modificar `backend/`, migraciones, Docker, despliegue ni dependencias.
- No cambiar endpoints, DTOs, payloads, query keys, caché, auth ni autorización.
- No cambiar cálculos monetarios, estados de negocio ni reglas de validación.
- No reemplazar React, Tailwind, Formik, React Query, Radix ni la navegación.
- No crear landing, gráficos nuevos ni animaciones de producto.
- No agregar tipografías remotas, librerías de tablas, iconos o formularios.
- No convertir todas las pantallas a una abstracción genérica. Se reutilizan
  componentes sólo donde ya existen al menos dos consumidores reales.

## Validaciones previstas

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

También se realizará revisión visual con viewport desktop y mediano cuando la
ruta pueda renderizarse sin debilitar autenticación, más inspección de foco,
overflow horizontal, empty states y consola del navegador.

## Resultado implementado

El refactor visual quedó aplicado sobre el worktree existente con estas piezas:

- tokens claros y oscuros unificados alrededor del rosa coral de Gestudio;
- escala tipográfica y de espaciado compacta para administración;
- shell autenticado con sidebar, navegación jerárquica, topbar contextual y
  contenido sin doble offset vertical;
- login reconstruido como experiencia de acceso de producto;
- componentes compartidos `PageHeader`, `SectionCard`, `FilterBar`,
  `SearchInput`, `StatCard`, `StatusBadge` y `RowActions`;
- tabla compartida con densidad, encabezados, hover, acciones livianas, versión
  móvil y empty state coherentes;
- estados loading/error/empty con contenedor, iconografía, jerarquía y acción;
- listados prioritarios de Alumnos, Inscripciones, Profesores, Conceptos,
  Métodos de pago y Stock alineados al mismo patrón;
- Registrar pago reorganizado en datos, cargos y confirmación; Pagos con
  consulta y acciones contextuales; Caja con métricas ejecutivas; Egresos con
  alta separada del historial;
- Asistencia diaria convertida en un flujo guiado de selección, validación y
  lista de toma de asistencia;
- formularios prioritarios de Alumnos, Inscripciones y Stock agrupados por
  secciones, grillas y acciones consistentes;
- Dashboard ajustado al shell y a la jerarquía visual nueva.

No se agregaron dependencias ni se modificaron backend, migraciones, contratos
HTTP, payloads, cálculos monetarios, query keys, autenticación o reglas de
negocio como parte de esta fase visual.

## Evidencia visual

Se revisó el login renderizado en 1280×720, 768×900 y 390×844. En los tres
viewports el contenido quedó contenido, sin overflow horizontal, con jerarquía
estable, inputs y CTA legibles. La consola del navegador no informó errores ni
warnings durante esta revisión. Las rutas protegidas no se abrieron con
credenciales ni se debilitó la autenticación para inspeccionarlas.

## Resultado final de gates

| Comando | Resultado final |
| --- | --- |
| `npm run lint` | PASS |
| `npm test` | PASS; 9 archivos, 21 tests |
| `npm run build` | PASS; TypeScript y Vite, 2.331 módulos transformados |
| `.\scripts\codex\validate.ps1 -Scope Frontend` | PASS; lint, test y build |
| `.\scripts\codex\validate.ps1 -Scope All` | FAIL de entorno en backend; frontend volvió a pasar dentro del gate |
| `docker compose config --quiet` | PASS |
| `git diff --check` | PASS |

El primer intento de `-Scope All` terminó antes de Maven porque `JAVA_HOME`
apuntaba a un directorio inexistente. Se reintentó sin modificar archivos,
usando para ese proceso el JDK Corretto 21.0.7 ya instalado.

El reintento compiló 292 fuentes backend y 30 fuentes de test, pero `mvn clean
verify` terminó con `80 tests, 0 failures, 16 errors`: todos los errores
PostgreSQL derivaron de la inicialización compartida de Testcontainers porque
no había un Docker daemon accesible. El mismo `-Scope All` ejecutó después el
frontend completo en verde y reportó `docker compose config: PASS`. Este
bloqueo no fue introducido por el refactor visual y no se inició Docker
automáticamente, de acuerdo con las instrucciones del repositorio.
