# Referencia API

> Estado: CONFIRMADO  
> Última revisión: 2026-07-26  
> Fuentes principales: controladores, `SecurityConfigurations`, `SecurityHttpIntegrationTest`

## Contrato general

- Base local: `http://localhost:8080/api`.
- Demo local: `http://localhost:18080/api`.
- JSON UTF-8 salvo PDF/bytes.
- 146 mappings reales son descubiertos por reflexión en `SecurityHttpIntegrationTest`.
- Toda ruta no declarada bajo `/api/**` queda denegada.
- El inventario dinámico, no este resumen, es la lista definitiva.

## Autenticación

| Método | Ruta | Acceso | Resultado |
|---|---|---|---|
| POST | `/api/login` | público | access token + refresh cookie |
| POST | `/api/login/refresh` | público, Origin y cookie válidos | rota tokens |
| POST | `/api/login/logout` | público, Origin válido | revoca y expira cookie |
| GET | `/api/usuarios/perfil` | autenticado | perfil actual |

## Familias y contratos principales

| Familia | Rutas relevantes | Permiso |
|---|---|---|
| Usuarios | `/api/usuarios/**` | `USUARIOS_ADMIN`; perfil sólo autenticado |
| Roles/permisos | `/api/roles/**`, `/api/permisos` | `ROLES_ADMIN` |
| Alumnos | CRUD, `/buscar`, `/{id}/disciplinas` | leer/admin |
| Inscripciones | CRUD, filtros, `/alumno/{id}/activas` | leer/admin |
| Condiciones | `/inscripciones/{id}/condiciones-economicas` GET/POST | condiciones admin |
| Disciplinas | CRUD, listado, búsquedas, relaciones, PDF | leer/admin; PDF + exportar |
| Tarifas | `/disciplinas/{id}/tarifas` GET/POST | tarifas admin |
| Profesores | CRUD, activos, búsquedas y relaciones | leer/admin |
| Asistencia | `/asistencias-diarias/**`, `/asistencias-mensuales/**` | leer/registrar |
| Mensualidades | crear, listar, eliminar, generar | pagos leer/anular/generar |
| Matrículas | por alumno/año, anulación | pagos leer/anular o inscripciones admin |
| Cargos | por concepto, pendientes, vencidos | pagos registrar/leer |
| Pagos | registrar, obtener, listar, anular, recibo | pagos registrar/leer/anular |
| Caja | `/caja/resumen` | caja leer |
| Egresos | registrar/listar/anular | egresos admin |
| Stock | CRUD, activos, ventas y reversión | stock leer/admin/vender |
| Créditos | consumo, reversión, ajuste y saldo | pagos leer, crédito consumir/admin |
| Reportes | consulta y exportación PDF | reportes leer/exportar |
| Notificaciones | `/notificaciones/cumpleaneros` | alumnos leer |
| Configuración | métodos, conceptos, subconceptos, salones, bonificaciones, recargos | config leer/admin |
| Jere Platform | crear snapshot y recuperar páginas | config admin + reportes exportar |
| Observaciones | `/observaciones-profesores/**` | denegado |

Para la matriz completa, ver [25-rbac-and-route-matrix.md](25-rbac-and-route-matrix.md).

## Paginación

Todas las respuestas paginadas públicas usan `PageResponse<T>` con el contrato:

```text
content, totalElements, totalPages, size, number, first, last
```

`Page` y `PageImpl` se mantienen únicamente como tipos internos de Spring Data.
El frontend comparte la misma forma estructural y no depende de metadata interna
de Spring.

## Errores

Contrato estándar `ApiErrorResponse`:

```text
timestamp, status, code, message, fieldErrors
```

Códigos derivados de constraints y negocio incluyen duplicados, idempotencia, sobreaplicación, crédito/stock insuficiente y conflictos optimistas. Los detalles internos no se exponen en 500.

## Compatibilidad legacy

- Eliminación de inscripción devuelve texto y maneja error localmente.
- Saldo de crédito devuelve `String`.
- Conceptos aceptan selector de subconcepto por ID o descripción.
- Métodos de pago exponen dos rutas de baja.
- Algunas creaciones devuelven 200 en lugar de 201.

No “uniformar” estos casos dentro de otra tarea sin inventario de consumidores y estrategia de versión.

## OpenAPI

No se confirmó un descriptor OpenAPI como fuente canónica. La prueba dinámica y los controladores son la fuente actual.
