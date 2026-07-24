# Referencia frontend

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: `frontend/package.json`, `frontend/src`

## Stack

React 18.3, TypeScript 5.6, Vite 6, React Router 7, TanStack Query 5, Axios, Formik/Yup, Radix UI, Tailwind, date-fns y React Toastify.

## Scripts

- `npm run dev`
- `npm run build`: `tsc -b`, Vite y generación de headers.
- `npm run lint`
- `npm test`: checks nginx y Vitest.
- `npm run test:watch`
- `npm run preview`

## Responsabilidades

SPA por roles/permisos; rutas, layouts, formularios, clientes HTTP, errores y vistas de dominio. El recorrido real cubre cinco roles en escritorio y móvil.

## PENDIENTE

Inventariar rutas/componentes y mapear pantalla → endpoint → permiso.