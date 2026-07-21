# Cierre técnico de observabilidad mínima

> Fecha de corte: 20 de julio de 2026  
> Rama de implementación: `agent/ops-observability-minimum`  
> PR: `#20`  
> Base inicial: `2eb9a8442c9a0c329c7ddaea42d3ea5c5827f35c`  
> Estado externo: **NO-GO para staging y producción**

## 1. Objetivo

Cerrar un mínimo operativo verificable para determinar si Gestudio está vivo, listo para tráfico, produciendo métricas y generando logs correlacionables sin publicar secretos ni datos personales.

El alcance no pretendió crear una plataforma completa de monitoreo. Se limitó a capacidades source-owned, reproducibles en infraestructura descartable y aptas para conectarse después a un ambiente real.

## 2. Alcance implementado

### Dependencias

- Spring Boot Actuator;
- Micrometer Prometheus registry.

### Health

Endpoints expuestos:

- `GET /actuator/health/liveness`;
- `GET /actuator/health/readiness`.

Contrato:

- acceso público para healthchecks de infraestructura;
- respuesta agregada únicamente;
- sin detalles de componentes;
- readiness vinculada a estado de aplicación, PostgreSQL y disco;
- health de correo deshabilitado para evitar que una integración opcional retire tráfico del backend.

### Métricas

Endpoint:

- `GET /actuator/prometheus`.

Protección:

- cabecera `X-Gestudio-Metrics-Token`;
- secreto independiente `APP_OBSERVABILITY_METRICS_TOKEN`;
- comparación en tiempo constante;
- token vacío mantiene el endpoint cerrado;
- token ausente, incorrecto, con espacios añadidos o mayor a 512 caracteres es rechazado;
- `401 Unauthorized` para credencial ausente o inválida;
- todos los demás endpoints Actuator denegados o no expuestos.

Métricas verificadas:

- JVM;
- proceso;
- HTTP mediante Micrometer cuando existen solicitudes observadas.

### Correlación HTTP

- cabecera aceptada y devuelta: `X-Request-ID`;
- formato restringido a 1..128 caracteres seguros;
- UUID generado cuando falta o es inválido;
- MDC `requestId` durante toda la solicitud;
- limpieza del MDC en `finally`.

### Logs

Para `/api/**` se registra:

- método;
- ruta sin query string;
- estado HTTP;
- duración;
- resultado normal o excepción;
- request ID en el patrón global.

Se excluyen deliberadamente:

- query strings;
- cuerpos;
- cookies;
- Authorization;
- refresh tokens;
- token de métricas;
- secretos JWT, PostgreSQL o integraciones;
- datos personales de formularios.

Saltos de línea y tabulaciones son neutralizados.

### Docker y Compose

- Dockerfile backend usa readiness real en su `HEALTHCHECK`;
- Compose local pasa el token opcional y usa readiness;
- Compose productivo exige `APP_OBSERVABILITY_METRICS_TOKEN`;
- CI productivo usa sólo un valor sintético no reutilizable.

### Automatización

- `scripts/ops/verify-observability.ps1`;
- `.github/workflows/observability-verification.yml`;
- artefacto `observability-evidence`;
- `docs/operations/observability.md`.

## 3. Pruebas agregadas

### Unitarias

`MetricsTokenAuthorizationManagerTest`:

- acepta únicamente token exacto;
- rechaza token incorrecto;
- rechaza espacios agregados;
- rechaza ausencia;
- token configurado vacío mantiene fail-closed;
- rechaza longitud excesiva.

`RequestCorrelationFilterTest`:

- propaga ID seguro;
- genera UUID cuando falta;
- reemplaza espacios y saltos de línea;
- limpia MDC después de responder.

### Integración PostgreSQL/HTTP

`ObservabilityPostgreSqlTest`:

- liveness `UP` sin detalles;
- readiness `UP` sin detalles;
- Prometheus `401` sin token;
- Prometheus `401` con token incorrecto;
- Prometheus `200` con token exacto;
- métricas JVM/proceso presentes;
- request ID propagado, generado y saneado incluso en respuesta `401` de negocio.

La prueba habilita observabilidad externa explícitamente mediante `@AutoConfigureObservability`; Spring Boot la deshabilita por defecto en tests.

## 4. Drill descartable

El verificador crea:

- nombre Compose único;
- puertos aleatorios;
- credenciales sintéticas aleatorias;
- token de métricas aleatorio;
- imagen backend temporal;
- PostgreSQL y volúmenes descartables.

Casos:

1. Docker disponible;
2. stack healthy por readiness real;
3. liveness y readiness públicos y mínimos;
4. Prometheus cerrado sin credencial exacta;
5. Prometheus accesible con credencial exacta;
6. métricas JVM/proceso presentes;
7. request ID propagado;
8. request ID ausente generado;
9. request ID inseguro reemplazado;
10. evento HTTP correlacionado;
11. secretos sintéticos ausentes de logs;
12. cleanup sin contenedores, volúmenes, redes ni imagen residual.

Evidencia verde sobre `4538aa6d9d4dccf3503f5ce7ee29608cd319a3bb`:

- duración: `00:01:34.3933724`;
- pasos PASS: `8`;
- fallos: `0`;
- artefacto digest: `sha256:9d3af5535bed637bb52e61be3cf2e1bce1c17b0877340f1bae57c4f90e496ba0`.

El HEAD final incluye además las correcciones de regresión y CI descritas abajo; debe revalidarse antes del merge.

## 5. Fallos encontrados y correcciones

### FALLO-OBS-001 — contrato 403/401

Primer drill:

- Docker, build y stack: PASS;
- readiness/liveness: PASS;
- fallo: el verificador esperaba `403`, Spring Security devolvió `401`.

Decisión:

- `401` es el contrato correcto para credencial ausente o inválida;
- código, tests, drill y runbook se alinearon;
- no se abrió Prometheus ni se relajó seguridad.

### FALLO-OBS-002 — `MvcRequestMatcher` en contextos sin MVC

Las suites con `spring.main.web-application-type=none` fallaron porque el chain Actuator creado con patrones String requería `mvcHandlerMappingIntrospector`.

Corrección:

- `AntPathRequestMatcher` explícito para `/actuator/**`;
- los contextos no web vuelven a cargar sin incorporar MVC artificialmente.

### FALLO-OBS-003 — Prometheus 404 en test

El runtime real publicaba Prometheus, pero Spring Boot deshabilita observabilidad externa por defecto durante tests.

Corrección:

- `@AutoConfigureObservability(metrics = true, tracing = false)` sólo en la prueba de integración.

### FALLO-OBS-004 — bean ausente en `@WebMvcTest`

Un slice de seguridad importaba `SecurityConfigurations`, pero no escaneaba `MetricsTokenAuthorizationManager` como componente.

Corrección:

- el manager dejó de depender de component scanning;
- `SecurityConfigurations` declara explícitamente el bean desde la propiedad externa.

### FALLO-OBS-005 — Compose productivo en CI

`docker-compose.prod.yml` exige el nuevo secreto, pero el workflow de CI todavía no lo suministraba.

Corrección:

- CI agrega `APP_OBSERVABILITY_METRICS_TOKEN` sintético sólo para validar configuración;
- producción continúa exigiendo un secreto externo real.

## 6. Archivos principales

- `backend/pom.xml`;
- `backend/src/main/resources/application.yml`;
- `backend/src/main/java/gestudio/infra/observabilidad/MetricsTokenAuthorizationManager.java`;
- `backend/src/main/java/gestudio/infra/observabilidad/RequestCorrelationFilter.java`;
- `backend/src/main/java/gestudio/infra/seguridad/SecurityConfigurations.java`;
- `backend/src/test/java/gestudio/infra/observabilidad/*`;
- `backend/Dockerfile`;
- `docker-compose.yml`;
- `docker-compose.prod.yml`;
- `.env.example`;
- `.env.local.example`;
- `scripts/ops/verify-observability.ps1`;
- `.github/workflows/observability-verification.yml`;
- `.github/workflows/github.-actions-demo.yml`;
- `docs/operations/observability.md`.

## 7. Decisión de gate

Se puede declarar **observabilidad mínima cerrada técnicamente** cuando el HEAD final obtenga simultáneamente:

- Backend PASS;
- Frontend PASS;
- Scope All PASS;
- smoke PASS;
- seed doble PASS;
- CI imágenes PASS;
- backup/restore PASS;
- rollback PASS;
- observability verification PASS.

Esto no equivale a observabilidad productiva.

## 8. Límites abiertos

Para staging siguen faltando:

- ambiente provisto;
- Prometheus o servicio equivalente;
- almacenamiento de métricas;
- dashboard;
- alertas entregadas a responsables;
- retención centralizada de logs;
- TLS y segmentación de red;
- secret manager y rotación demostrada;
- medición de carga para ajustar umbrales;
- responsables, on-call y escalamiento.

Producción continúa en `NO-GO` y requiere autorización independiente.
