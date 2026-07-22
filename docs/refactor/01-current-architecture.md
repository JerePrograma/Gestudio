# Arquitectura actual

Gestudio es un monolito modular en dos aplicaciones versionadas juntas.

## Backend

Flujo habitual: controlador HTTP -> DTO -> servicio de caso de uso -> repositorio
Spring Data -> PostgreSQL. Los controladores no retornan entidades JPA. Los
servicios ordinarios son clases concretas; sólo email y almacenamiento de
recibos representan límites externos.

Capacidades activas: alumnos, inscripciones, disciplinas, profesores, salones,
asistencias, cargos/mensualidades/matrículas, pagos/crédito/caja, stock, egresos,
seguridad, reportes, notificaciones y recibos.

Las transacciones financieras terminan antes de PDF, filesystem o SMTP. El
worker de recibos reclama filas con `FOR UPDATE SKIP LOCKED`, usa lease y cierra
cada cambio de estado en una transacción corta.

## Frontend

React Router define las pantallas y el cliente Axios centraliza autenticación.
React Query es la autoridad remota en los flujos canónicos paginados. Sus keys
incluyen recurso, página, tamaño, filtro y orden. No existe carga automática de
páginas sucesivas; la colección de una página se reemplaza y las listas locales
adicionales usan una acción explícita `Mostrar más`.

Los importes de request/response/formulario son strings decimales. La utilidad
`utils/money.ts` valida, normaliza, compara y formatea sin convertir a `number`.

## Infraestructura

- Una baseline Flyway V1 y `ddl-auto=validate`.
- Testcontainers PostgreSQL 15 para catálogo, SQL, locks y planes.
- CI: backend `clean verify`; frontend `npm ci`, lint, tests y build; Compose;
  imágenes SHA sólo después de gates verdes. No hay deploy automático.
