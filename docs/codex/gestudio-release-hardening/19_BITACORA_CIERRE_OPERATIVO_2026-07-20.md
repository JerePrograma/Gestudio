# Bitácora de cierre operativo — rollback y observabilidad

> Fecha: 20 de julio de 2026  
> Zona horaria: `America/Argentina/Buenos_Aires`  
> Repositorio: `JerePrograma/Gestudio`  
> Estado externo: **NO-GO para demo comercial, staging y producción**

Este archivo registra la cronología compacta posterior al cierre de backup/restore. La evidencia detallada permanece en los documentos 17 y 18 y en los artefactos de GitHub Actions.

## 1. Rollback forward-compatible

### Estado inicial

- PR: `#19`;
- candidato final: `bb82ff1ddc7a6b319383185e76d5e598ecc1d744`;
- base: `main`;
- hilos de revisión pendientes: 0;
- reviews pendientes: 0.

### Workflows finales

- `GATE-1B validation`: success;
- `CI Gestudio`: success;
- `Backup restore verification`: success;
- `Application rollback verification`: success.

### Integración

- PR marcado ready;
- merge method: merge commit;
- protección `expected_head_sha` aplicada;
- merge en `main`: `2eb9a8442c9a0c329c7ddaea42d3ea5c5827f35c`.

### Decisión

Rollback backend queda integrado y cerrado técnicamente. Registry, firma, promoción y retención de imágenes permanecen abiertos.

## 2. Inicio de observabilidad mínima

### Rama y PR

- rama: `agent/ops-observability-minimum`;
- base inicial: `2eb9a8442c9a0c329c7ddaea42d3ea5c5827f35c`;
- PR: `#20`;
- modalidad: draft hasta todos los gates verdes.

### Diseño

- health público mínimo;
- Prometheus fail-closed con secreto independiente;
- request ID seguro;
- logs sin datos sensibles;
- readiness real en Docker;
- prueba PostgreSQL y drill descartable.

## 3. Fallos observados

### OBS-001 — contrato HTTP del token

Primer drill:

- stack healthy;
- liveness/readiness PASS;
- fallo por esperar `403` cuando Spring Security devolvió `401`.

Resolución:

- contrato correcto fijado en `401 Unauthorized` para credencial ausente o inválida;
- implementación, tests, script y runbook alineados.

### OBS-002 — matcher dependiente de MVC

Síntoma:

- contexts con `web-application-type=none` no cargaban;
- `MvcRequestMatcher` exigía `mvcHandlerMappingIntrospector`.

Resolución:

- matchers Actuator reemplazados por `AntPathRequestMatcher` explícitos.

### OBS-003 — métricas deshabilitadas en test

Síntoma:

- Prometheus devolvía 404 en integración, aunque el runtime Docker era correcto.

Resolución:

- `@AutoConfigureObservability(metrics = true, tracing = false)` en la prueba específica.

### OBS-004 — bean ausente en slice MVC

Síntoma:

- `@WebMvcTest` importaba seguridad pero no escaneaba el manager del token.

Resolución:

- manager sin component scanning;
- bean declarado explícitamente en `SecurityConfigurations`.

### OBS-005 — nuevo secreto ausente en CI productivo

Síntoma:

- backend, frontend y Compose local PASS;
- Compose productivo fallaba por variable requerida ausente.

Resolución:

- valor sintético CI-only añadido al workflow;
- requisito productivo no fue relajado.

## 4. Evidencia verde de observabilidad

Drill sobre `4538aa6d9d4dccf3503f5ce7ee29608cd319a3bb`:

- Docker disponible;
- stack healthy por readiness;
- health mínimo;
- Prometheus cerrado y autenticado correctamente;
- métricas JVM/proceso;
- correlación propagada/generada/saneada;
- logs sin secretos conocidos;
- cleanup completo;
- 8 PASS;
- 0 fallos;
- duración `00:01:34.3933724`;
- digest `sha256:9d3af5535bed637bb52e61be3cf2e1bce1c17b0877340f1bae57c4f90e496ba0`.

Las correcciones posteriores de contexts, slices y CI requieren revalidación final sobre el último SHA del PR antes del merge.

## 5. Documentación publicada en la rama

- README actualizado;
- estado y backlog unificado;
- checklist de release;
- decisiones y bloqueos;
- tablero maestro;
- handoff;
- runbook local;
- runbook de observabilidad;
- cierre técnico de observabilidad;
- recorridos humanos por rol;
- esta bitácora.

## 6. Próximo punto de control

Antes de fusionar PR `#20`:

1. obtener HEAD final;
2. comprobar `GATE-1B validation`;
3. comprobar `CI Gestudio`;
4. comprobar backup/restore;
5. comprobar rollback;
6. comprobar observabilidad;
7. revisar hilos y reviews;
8. marcar ready;
9. fusionar con `expected_head_sha`;
10. confirmar nuevo HEAD de `main`.

Después del merge:

- GATE-2 y recorridos humanos pasan a ser el siguiente trabajo interno;
- monitoreo externo, políticas y staging continúan bloqueados por insumos no provistos.
