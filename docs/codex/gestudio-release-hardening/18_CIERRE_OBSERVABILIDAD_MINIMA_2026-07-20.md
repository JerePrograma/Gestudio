# Cierre técnico de observabilidad mínima

> Fecha de corte: 20 de julio de 2026  
> Rama de implementación: `agent/ops-observability-minimum`  
> PR: `#20`  
> Base inicial: `2eb9a8442c9a0c329c7ddaea42d3ea5c5827f35c`  
> Estado externo: **NO-GO para staging y producción**

## 1. Objetivo

Cerrar un mínimo operativo verificable para determinar si Gestudio está vivo, listo para tráfico, produciendo métricas y generando logs correlacionables sin publicar secretos ni datos personales.

El alcance se limita a capacidades source-owned, reproducibles en infraestructura descartable. No constituye una plataforma completa de monitoreo ni un SLA.

## 2. Alcance implementado

### Dependencias

- Spring Boot Actuator;
- Micrometer Prometheus registry.

### Health

Endpoints:

- `GET /actuator/health/liveness`;
- `GET /actuator/health/readiness`.

Contrato:

- acceso público para infraestructura;
- estado agregado únicamente;
- sin detalles de componentes;
- readiness vinculada a aplicación, PostgreSQL y disco;
- health de correo deshabilitado para no retirar tráfico por una integración opcional.

### Métricas

- endpoint `GET /actuator/prometheus`;
- cabecera `X-Gestudio-Metrics-Token`;
- secreto independiente `APP_OBSERVABILITY_METRICS_TOKEN`;
- comparación en tiempo constante;
- token vacío mantiene fail-closed;
- ausencia, error, espacios agregados o más de 512 caracteres: rechazo;
- `401 Unauthorized` para credencial ausente o inválida;
- demás endpoints Actuator denegados o no expuestos.

Métricas verificadas:

- JVM;
- proceso;
- HTTP mediante Micrometer cuando existen solicitudes observadas.

### Correlación HTTP

- cabecera `X-Request-ID` aceptada y devuelta;
- 1..128 caracteres seguros;
- UUID cuando falta o es inválido;
- MDC `requestId` durante la solicitud;
- limpieza en `finally`.

### Logs

Para `/api/**`:

- método;
- ruta sin query string;
- estado;
- duración;
- outcome;
- request ID global.

Exclusiones:

- query strings;
- cuerpos;
- cookies;
- Authorization;
- refresh tokens;
- token de métricas;
- secretos JWT/PostgreSQL/integraciones;
- datos personales.

Saltos de línea y tabulaciones se neutralizan.

### Docker, Compose y rollback

- imágenes actuales usan readiness real;
- Dockerfile genera `/app/build-metadata/health-contract`;
- `actuator-readiness-v1` para imágenes con Actuator;
- `legacy-api-401-v1` para imágenes anteriores a Actuator;
- Compose selecciona sonda según `BACKEND_HEALTHCHECK_MODE`;
- el script de rollback deriva y aplica el contrato por imagen;
- Compose productivo exige token de métricas;
- CI usa valores sintéticos.

### Automatización

- `scripts/ops/verify-observability.ps1`;
- `.github/workflows/observability-verification.yml`;
- artefacto `observability-evidence`;
- `docs/operations/observability.md`.

## 3. Pruebas

### Unitarias

`MetricsTokenAuthorizationManagerTest`:

- token exacto;
- token incorrecto;
- espacios agregados;
- ausencia;
- configuración vacía;
- longitud excesiva.

`RequestCorrelationFilterTest`:

- propagación;
- generación UUID;
- reemplazo de valores inseguros;
- limpieza MDC.

### Integración PostgreSQL/HTTP

`ObservabilityPostgreSqlTest`:

- liveness/readiness `UP` sin detalles;
- Prometheus 401 sin token o incorrecto;
- Prometheus 200 con token exacto;
- métricas JVM/proceso;
- request ID propagado/generado/saneado aun con respuesta 401.

La prueba usa `@AutoConfigureObservability(metrics = true, tracing = false)` porque Spring Boot deshabilita observabilidad externa por defecto en tests.

## 4. Drill descartable

Crea proyecto, puertos, secretos, token, imagen, PostgreSQL y volúmenes aislados.

Casos:

1. Docker disponible;
2. stack healthy por readiness;
3. health público mínimo;
4. Prometheus cerrado sin credencial exacta;
5. Prometheus abierto con credencial exacta;
6. métricas JVM/proceso;
7. request ID propagado;
8. request ID generado;
9. request ID inseguro reemplazado;
10. evento HTTP correlacionado;
11. secretos sintéticos ausentes de logs;
12. cleanup completo.

Evidencia verde sobre `4538aa6d9d4dccf3503f5ce7ee29608cd319a3bb`:

- duración `00:01:34.3933724`;
- 8 PASS;
- 0 fallos;
- digest `sha256:9d3af5535bed637bb52e61be3cf2e1bce1c17b0877340f1bae57c4f90e496ba0`.

## 5. Fallos encontrados y correcciones

### OBS-001 — 403/401

El primer drill esperaba 403 y runtime devolvió 401 para credencial ausente.

Corrección: 401 fijado como contrato correcto sin abrir Prometheus.

### OBS-002 — matcher dependiente de MVC

Contexts `web-application-type=none` fallaron porque patrones String crearon `MvcRequestMatcher`.

Corrección: `AntPathRequestMatcher` explícito.

### OBS-003 — Prometheus 404 en test

Runtime publicaba métricas, pero tests deshabilitaban observabilidad externa.

Corrección: `@AutoConfigureObservability` en la prueba específica.

### OBS-004 — bean ausente en slice MVC

`@WebMvcTest` importaba seguridad pero no escaneaba el manager.

Corrección: bean explícito en `SecurityConfigurations`.

### OBS-005 — secreto ausente en CI productivo

Compose productivo exigía el token y CI no lo suministraba.

Corrección: token sintético CI-only; producción conserva requisito externo.

### OBS-006 — rollback anterior a Actuator

En `415fe9040f072440f997719bcf2b030cb47e453a`:

- Backend, Frontend, Scope All, smoke, seed, CI, backup/restore y observabilidad: PASS;
- rollback: FAIL.

La imagen histórica inició con PostgreSQL y Flyway V7, pero no tenía `/actuator/health/readiness`. El Compose nuevo la marcó unhealthy y recuperó correctamente la imagen actual.

Corrección:

- metadata `health-contract` por imagen;
- readiness para artefactos actuales;
- sonda HTTP 401 para artefactos legacy;
- selección explícita durante rollback;
- rechazo de contratos desconocidos;
- imagen actual recupera readiness al volver;
- no se aceptó una sonda meramente TCP.

Artefacto de fallo preservado:

- digest `sha256:cefdc52779c5ab3d0108f7a1b27fcc9f75e1d10d8a69936191a16ea007e7277e`.

## 6. Archivos principales

- `backend/pom.xml`;
- `backend/src/main/resources/application.yml`;
- `backend/src/main/java/gestudio/infra/observabilidad/*`;
- `backend/src/main/java/gestudio/infra/seguridad/SecurityConfigurations.java`;
- `backend/src/test/java/gestudio/infra/observabilidad/*`;
- `backend/Dockerfile`;
- `docker-compose.yml`;
- `docker-compose.prod.yml`;
- `.env.example` y `.env.local.example`;
- `scripts/ops/rollback-backend.ps1`;
- `scripts/ops/verify-observability.ps1`;
- workflows CI, rollback y observabilidad;
- runbooks de rollback y observabilidad.

## 7. Decisión de gate

Observabilidad mínima sólo queda cerrada cuando un único HEAD obtiene:

- Backend PASS;
- Frontend PASS;
- Scope All PASS;
- smoke PASS;
- seed doble PASS;
- CI imágenes PASS;
- backup/restore PASS;
- rollback PASS, incluyendo legacy health;
- observability verification PASS.

Esto no equivale a observabilidad productiva.

## 8. Límites abiertos

- ambiente real;
- Prometheus/servicio equivalente;
- almacenamiento y dashboards;
- alertas y responsables;
- retención de logs;
- TLS/segmentación;
- secret manager y rotación;
- carga real y ajuste de umbrales;
- on-call/escalamiento.

Producción continúa en `NO-GO` y requiere autorización independiente.
