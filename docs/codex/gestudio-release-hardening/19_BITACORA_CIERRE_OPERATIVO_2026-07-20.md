# Bitácora de cierre operativo — rollback y observabilidad

> Fecha: 20 de julio de 2026  
> Zona horaria: `America/Argentina/Buenos_Aires`  
> Repositorio: `JerePrograma/Gestudio`  
> Estado externo: **NO-GO para demo comercial, staging y producción**

Este archivo registra la cronología posterior a backup/restore. La evidencia detallada permanece en los documentos 17 y 18 y en GitHub Actions.

## 1. Rollback forward-compatible integrado

- PR: `#19`;
- candidato: `bb82ff1ddc7a6b319383185e76d5e598ecc1d744`;
- hilos/reviews pendientes: 0;
- GATE-1B, CI, backup/restore y rollback: success;
- merge protegido en `main`: `2eb9a8442c9a0c329c7ddaea42d3ea5c5827f35c`.

Decisión: rollback backend cerrado técnicamente. Registry, firma, promoción y retención siguen abiertos.

## 2. Inicio de observabilidad mínima

- rama `agent/ops-observability-minimum`;
- base `2eb9a8442c9a0c329c7ddaea42d3ea5c5827f35c`;
- PR `#20` draft;
- health público mínimo;
- Prometheus fail-closed;
- request ID;
- logs sanitizados;
- readiness Docker;
- tests PostgreSQL y drill descartable.

## 3. Fallos OBS-001 a OBS-005

### OBS-001 — 403/401

- stack y health PASS;
- verificador esperaba 403 y runtime devolvió 401;
- 401 fijado como contrato correcto para credencial ausente/incorrecta.

### OBS-002 — matcher dependiente de MVC

- contexts no web fallaban por `MvcRequestMatcher`;
- reemplazo por `AntPathRequestMatcher`.

### OBS-003 — métricas deshabilitadas en test

- runtime Prometheus correcto, prueba devolvía 404;
- `@AutoConfigureObservability(metrics = true, tracing = false)` en integración.

### OBS-004 — bean ausente en slice MVC

- `@WebMvcTest` no escaneaba manager;
- bean explícito en `SecurityConfigurations`.

### OBS-005 — secreto ausente en CI productivo

- backend/frontend/Compose local PASS;
- Compose productivo fallaba por nueva variable requerida;
- token sintético CI-only añadido sin relajar producción.

## 4. Evidencia verde inicial de observabilidad

Drill `4538aa6d9d4dccf3503f5ce7ee29608cd319a3bb`:

- Docker y stack healthy;
- health mínimo;
- Prometheus cerrado/abierto correctamente;
- métricas JVM/proceso;
- correlación y sanitización;
- secretos ausentes de logs;
- cleanup;
- 8 PASS;
- 0 fallos;
- `00:01:34.3933724`;
- digest `sha256:9d3af5535bed637bb52e61be3cf2e1bce1c17b0877340f1bae57c4f90e496ba0`.

## 5. Primera validación documental final

HEAD `415fe9040f072440f997719bcf2b030cb47e453a`:

- GATE-1B completo: success;
- CI: success;
- backup/restore: success;
- observabilidad: success;
- rollback: failure.

El fallo se mantuvo bloqueante y PR `#20` no fue fusionado.

## 6. OBS-006 — rollback anterior a Actuator

Evidencia:

- artefacto histórico inició Spring, PostgreSQL y Flyway V7;
- el Compose nuevo exigía `/actuator/health/readiness`;
- ese código histórico era anterior a Actuator;
- contenedor marcado unhealthy;
- recuperación automática a imagen actual: success;
- cleanup: success;
- datos/Flyway no fueron la causa;
- digest del artefacto de fallo: `sha256:cefdc52779c5ab3d0108f7a1b27fcc9f75e1d10d8a69936191a16ea007e7277e`.

Resolución:

- metadata `/app/build-metadata/health-contract`;
- `actuator-readiness-v1` para imágenes actuales;
- `legacy-api-401-v1` para imágenes pre-Actuator;
- Dockerfile deriva el contrato desde `pom.xml`;
- healthcheck autocontenido lee la metadata;
- Compose selecciona contrato por `BACKEND_HEALTHCHECK_MODE`;
- rollback lee ambos contratos y aplica el del target;
- imagen sin metadata health recibe fallback legacy con advertencia;
- contrato desconocido se rechaza;
- recuperación automática conserva el contrato de la imagen anterior.

La sonda legacy exige HTTP 401 de `/api/alumnos`; no se degradó a una simple apertura TCP.

## 7. Documentación publicada en la rama

- README;
- estado/backlog;
- checklist;
- decisiones/bloqueos;
- índice;
- handoff;
- runbook local;
- backup/restore;
- rollback ampliado;
- observabilidad;
- cierres 17/18;
- recorridos humanos;
- esta bitácora.

## 8. Punto de control final

Antes de fusionar PR `#20`:

1. obtener un nuevo HEAD único;
2. revalidar GATE-1B;
3. revalidar CI/imágenes;
4. revalidar backup/restore;
5. revalidar rollback actual → legacy → actual;
6. revalidar observabilidad;
7. revisar hilos/reviews;
8. marcar ready;
9. fusionar con `expected_head_sha`;
10. confirmar `main`.

Después del merge:

- GATE-2 y recorridos humanos son el siguiente trabajo interno;
- monitoreo externo, políticas, staging y producción siguen bloqueados.
