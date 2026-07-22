# Auditoría definitiva del seed demo

Fecha: 2026-07-22
Zona civil: `America/Argentina/Buenos_Aires`

## Contrato

El seed `scripts/gestudio_demo_seed_full.sql` es manual, sintético e idempotente.
No forma parte de Flyway, no se ejecuta en producción y no contiene contraseñas
en claro. El lanzador genera cinco hashes BCrypt distintos a partir de claves
ingresadas por consola o por el mecanismo no interactivo del entorno efímero.

Se distinguen:

- `anchor_date`: ancla estable para conservar relaciones históricas;
- `business_date`: fecha civil diaria de Buenos Aires para estados y cumpleaños.

## Inventario validado

- 914 filas demo en total;
- cinco usuarios: `demo-superadmin`, `demo-direccion`, `demo-administrador`,
  `demo-secretaria` y `demo-caja`;
- cinco hashes BCrypt distintos y cinco logins HTTP 200;
- roles/permisos tomados de Flyway, sin mutar el catálogo RBAC;
- alumnos, inscripciones, disciplinas, horarios, asistencias, cargos, pagos,
  caja, stock, egresos, recibos y outbox con referencias consistentes;
- cumpleaños del día para Sofía Benítez y exclusión de personas inactivas;
- ningún registro demo en las tablas de exportación V7.

## Idempotencia

El gate aplica el seed dos veces. La segunda ejecución debe producir un snapshot
idéntico de IDs, relaciones, estados financieros, caja, stock, outbox, hashes y
RBAC. La ejecución final del 22 de julio terminó con 914 filas en ambas corridas,
sin duplicados ni diferencias.

## Seguridad y aislamiento

- Las claves son deliberadamente demo y no deben reutilizarse.
- No se escriben en archivos versionados ni se imprimen en logs.
- Variables hostiles heredadas se neutralizan dentro del proceso hijo.
- La demo usa el proyecto Compose fijo `gestudio-demo-local`; los gates técnicos
  usan proyectos aleatorios y limpian sólo sus recursos etiquetados.
- Reset elimina exclusivamente los volúmenes de la demo antes de reconstruir.
- Capturas y trazas de navegador se guardan fuera del repositorio.

## Evidencia 2026-07-22

| Comprobación | Resultado |
|---|---|
| Flyway local | V1-V7 contiguas, derivadas del manifiesto |
| Base vacía | migraciones y `ddl-auto=validate` correctos |
| Primera corrida | 914 filas e invariantes verdes |
| Segunda corrida | snapshot idéntico |
| Login/RBAC | 5 logins; 200/400/401/403 diferenciados |
| Navegador | cinco roles, escritorio/móvil, rutas y logout |
| Limpieza | sin secretos ni temporales en el repositorio |

Uso y credenciales deliberadas se documentan en
`docs/testing/demo-seed.md` y `docs/testing/demo-local.md`.
