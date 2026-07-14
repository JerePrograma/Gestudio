# Inventario y política de endpoints

> Inventario histórico previo a V5. La fuente ejecutable actual es
> `SecurityConfigurations`; la autorización vigente usa `PERM_*`.

Snapshot histórico: 2026-07-01. En ese snapshot la política se evaluaba en este orden:

1. `OPTIONS /**`, `POST /api/login` y `POST /api/login/refresh`: públicos.
2. `GET /api/usuarios/perfil`: cualquier usuario autenticado y activo.
3. Todo otro `/api/**`: `ROLE_ADMINISTRADOR`.
4. Cualquier otra ruta: denegada.

No hay matchers de deuda, email de prueba, detalle-pago, factura heredada ni
aliases de inscripción retirados. Un endpoint nuevo bajo `/api` queda cerrado a
administrador, no abierto por omisión.

Leyenda: `S` datos personales/sensibles; `F` escritura o lectura financiera;
`I` idempotencia explícita (`key+hash`), natural (`unique`) o no aplicable.
Cada entrada de la tabla era un endpoint HTTP vigente en el snapshot 2026-07-01. El contrato actual está en `SecurityConfigurations` y en la matriz automatizada 144/144 de `docs/codex/gestudio-release-hardening/02_MATRIZ_RBAC.md`.

| Base | Endpoints actuales | Política | S/F/I |
| --- | --- | --- | --- |
| `/api/login` | `POST /`; `POST /refresh` | Público | S sí; F no; I n/a |
| `/api/usuarios` | `POST /registro`; `PUT /{id}`; `GET /{id}`; `GET /`; `DELETE /{id}` | Admin | S sí; F no; I n/a |
| `/api/usuarios` | `GET /perfil` | Autenticado | S sí; F no; I n/a |
| `/api/roles` | `POST /`; `GET /{id}`; `GET /` | Admin | S no; F no; I n/a |
| `/api/alumnos` | `POST /`; `GET /`; `GET /{id}`; `PUT /{id}`; `DELETE /{id}`; `GET /buscar`; `GET /{alumnoId}/disciplinas` | Admin | S sí; F indirecto; I n/a |
| `/api/inscripciones` | `POST /`; `PUT /{id}`; `GET /`; `GET /{id}`; `DELETE /{id}`; `GET /alumno/{alumnoId}/activas` | Admin | S sí; F origina cargos; I natural |
| `/api/cargos` | `POST /concepto`; `GET /{id}`; `GET /alumno/{alumnoId}/pendientes`; `GET /vencidos` | Admin | S sí; F sí; I key en POST |
| `/api/pagos` | `POST /`; `POST /{id}/anulacion`; `GET /{id}`; `GET /alumno/{alumnoId}`; `GET /recibo/{pagoId}` | Admin | S sí; F sí; I key+hash en escrituras |
| `/api/creditos` | `POST /consumos`; `POST /consumos/{id}/reversion`; `POST /ajustes`; `GET /alumno/{alumnoId}/saldo` | Admin | S sí; F sí; I key+hash |
| `/api/caja` | `GET /resumen` | Admin | S no; F sí; I n/a |
| `/api/egresos` | `POST /`; `POST /{id}/anulacion`; `GET /{id}`; `GET /` | Admin | S no; F sí; I key+hash en escrituras |
| `/api/stocks` | `POST /`; `GET /`; `GET /activos`; `GET /{id}`; `PUT /{id}`; `DELETE /{id}`; `POST /ventas`; `POST /ventas/{id}/reversion` | Admin | S venta/alumno; F sí; I key+hash en venta/reverso |
| `/api/matriculas` | `POST /alumno/{alumnoId}`; `GET /alumno/{alumnoId}`; `POST /{id}/anulacion` | Admin | S sí; F sí; I unique alumno/año |
| `/api/mensualidades` | `POST /`; `GET /{id}`; `GET /inscripcion/{inscripcionId}`; `DELETE /{id}`; `POST /generar-mensualidades` | Admin | S sí; F sí; I unique inscripción/período |
| `/api/reportes` | `GET /mensualidades`; `POST /mensualidades/exportar` | Admin | S sí; F sí; I n/a |
| `/api/disciplinas` | `POST /`; `GET /`; `GET /{id}`; `PUT /{id}`; `DELETE /dar-baja/{id}`; `DELETE /{id}`; `GET /listado`; `GET /por-fecha`; `GET /{disciplinaId}/alumnos`; `GET /{disciplinaId}/profesor`; `GET /por-horario`; `GET /buscar`; `GET /{disciplinaId}/alumnos/pdf` | Admin | S en alumnos/PDF; F catálogo; I n/a |
| `/api/profesores` | `POST /`; `GET /{id}`; `GET /`; `GET /activos`; `PUT /{id}`; `DELETE /{id}`; `GET /{profesorId}/disciplinas`; `GET /buscar`; `GET /{profesorId}/alumnos` | Admin | S sí; F no; I n/a |
| `/api/salones` | `POST /`; `GET /`; `GET /{id}`; `PUT /{id}`; `DELETE /{id}` | Admin | S no; F no; I n/a |
| `/api/asistencias-diarias` | `PUT /registrar`; `PUT /{id}`; `GET /por-asistencia-mensual/{asistenciaMensualId}`; `DELETE /{id}`; `GET /por-disciplina-y-fecha` | Admin | S sí; F no; I natural fecha/alumno |
| `/api/asistencias-mensuales` | `GET /`; `POST /`; `PUT /{id}`; `GET /por-disciplina/detalle`; `POST /crear-asistencias-activos-detallado` | Admin | S sí; F no; I uniques de período |
| `/api/observaciones-profesores` | `POST /`; `DELETE /{id}`; `GET /{id}`; `GET /`; `GET /profesor/{profesorId}`; `GET /fechas`; `GET /profesor/{profesorId}/mes` | Admin | S sí; F no; I n/a |
| `/api/bonificaciones` | `POST /`; `GET /`; `GET /{id}`; `PUT /{id}`; `DELETE /{id}` | Admin | S no; F catálogo; I n/a |
| `/api/recargos` | `GET /`; `GET /{id}`; `POST /`; `PUT /{id}`; `DELETE /{id}` | Admin | S no; F catálogo; I n/a |
| `/api/metodos-pago` | `POST /`; `GET /`; `GET /{id}`; `PUT /{id}`; `DELETE /{id}`; `DELETE /baja/{id}` | Admin | S no; F catálogo; I n/a |
| `/api/conceptos` | `POST /`; `GET /`; `GET /{id}`; `PUT /{id}`; `DELETE /{id}`; `GET /sub-concepto/{subConceptoDesc}` | Admin | S no; F catálogo; I n/a |
| `/api/sub-conceptos` | `GET /{id}`; `POST /`; `GET /`; `PUT /{id}`; `DELETE /{id}`; `GET /buscar` | Admin | S no; F catálogo; I n/a |
| `/api/notificaciones` | `GET /cumpleaneros` | Admin | S sí; F no; I n/a |

## Evidencia HTTP

`SecurityHttpIntegrationTest` prueba la cadena real para:

- login/refresh válidos e inválidos;
- access vs refresh, expiración, firma, issuer, usuario/rol inactivo;
- 401 anónimo y contrato JSON;
- 403 de rol incorrecto sin cerrar sesión;
- acceso administrador a usuarios y matriz financiera;
- recibo protegido y no enumerable anónimamente;
- validación 400, recurso inexistente y 500 sanitizado sin stack trace;
- preflight CORS.

La cobertura vigente deriva de 144 políticas explícitas por método/ruta; el
fallback `/api/**` es `denyAll`. La prueba de arquitectura impide que
controladores retornen entidades JPA y la matriz contractual detecta endpoints
sin política declarada.
