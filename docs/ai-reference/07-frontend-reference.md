# Referencia frontend

> Estado: CONFIRMADO  
> Última revisión: 2026-07-24  
> Fuentes principales: `../../frontend/package.json`, `../../frontend/src/rutas/routes.ts`, `AppRouter.tsx`

## Stack

React 18.3, React DOM, TypeScript 5.6, Vite 6, React Router 7, TanStack Query 5, Axios, Formik, Yup, Radix UI, Tailwind, date-fns, React Toastify y Vitest/Testing Library.

## Estructura

- `src/rutas`: definición de rutas, permisos y guardas.
- `src/funcionalidades`: pantallas por capacidad.
- `src/paginas`: login, dashboard, reportes y unauthorized.
- `src/componentes`: layout, navegación y componentes comunes.
- `src/config`: códigos de permisos y contratos.
- cliente Axios compartido: autoridad para autenticación HTTP.
- `nginx`: SPA fallback, proxy y headers.

## Router

`AppRouter` carga rutas con `lazy`, usa `Suspense`, una guarda global autenticada y otra guarda por `requiredPermissions`. `MainLayout` envuelve las pantallas privadas. La ruta desconocida redirige a `/`.

Se declaran 32 entradas:

- 1 pública;
- 3 protegidas generales;
- 4 administrativas;
- 24 funcionales.

El inventario exacto y permisos están en [25-rbac-and-route-matrix.md](25-rbac-and-route-matrix.md).

## Permisos

`routes.ts` es la matriz central pantalla → permisos. Toda ruta funcional exige `APP_ACCESS` y uno o más permisos. La ocultación de UI no sustituye la autorización backend.

## Estado y acceso a datos

- TanStack Query gestiona consultas/cache donde se aplica.
- Axios centraliza HTTP y autenticación.
- Formik/Yup gestiona formularios y validación cliente.
- El backend recalcula y valida valores financieros; el frontend no es autoridad.
- Fechas deben usar `VITE_APP_TIME_ZONE` y utilidades compartidas.

## Autenticación

- 401 puede disparar un único refresh serializado.
- 403 preserva sesión y muestra falta de permiso.
- Refresh fallido elimina sólo claves de autenticación propias.
- No usar `localStorage.clear()`.
- No usar `process.env` en código Vite; usar `import.meta.env`.

## Build y seguridad web

`npm run build` ejecuta TypeScript, Vite y genera `_headers`. CI verifica CSP, ausencia de placeholder y ausencia de URL localhost en el bundle productivo. Nginx sirve SPA y headers.

## Pruebas

Vitest y Testing Library cubren componentes, rutas protegidas, permisos y flujos. Checks Node validan contratos Nginx. El release registró 149 tests Vitest y 2 contratos Nginx; ese número es evidencia fechada, no un contador permanente.

## Riesgos de cambio

- Desalinear `PERMISSIONS`, `routePermissions` y Spring Security.
- Introducir otra librería de estado/formularios sin necesidad.
- Duplicar fórmulas financieras.
- Romper refresh concurrente.
- Cambiar rutas sin actualizar navegación, tests y manual.
