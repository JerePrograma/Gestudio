# Integración final de observabilidad y compatibilidad de rollback

> Fecha operativa: 20 de julio de 2026, zona `America/Argentina/Buenos_Aires`  
> Integración efectiva en GitHub: 21 de julio de 2026 UTC  
> Repositorio: `JerePrograma/Gestudio`  
> Rama operativa: `main`  
> Estado externo: **NO-GO para demo comercial, staging y producción**

Este documento es la adenda final posterior al merge del PR `#20`. Reemplaza cualquier instrucción anterior que todavía indicara “fusionar PR #20” como tarea pendiente.

## 1. Integración

- PR: `#20` — `feat(obs): cierra observabilidad mínima fail-closed`;
- base inicial: `2eb9a8442c9a0c329c7ddaea42d3ea5c5827f35c`;
- HEAD funcional y documental validado: `ab830475dbd7c1d48deca7d50c1696c309679a88`;
- merge commit en `main`: `7dc07d649a468934f3c099a92e5d32747cf64347`;
- método: merge commit;
- protección: `expected_head_sha` aplicada;
- hilos de revisión pendientes: 0;
- reviews pendientes: 0.

## 2. Workflows finales sobre un único SHA

Todos los siguientes workflows cerraron `success` sobre `ab830475dbd7c1d48deca7d50c1696c309679a88`:

- `GATE-1B validation`;
- `CI Gestudio`;
- `Backup restore verification`;
- `Application rollback verification`;
- `Observability verification`.

## 3. Evidencia de aplicación

- backend: 171 pruebas PASS;
- frontend: 142/142 PASS;
- lint PASS;
- build frontend PASS;
- `Scope All` PASS;
- Compose local PASS;
- Compose productivo PASS con secretos sintéticos exclusivos de CI;
- smoke V1-V7 PASS;
- seed demo primera aplicación PASS;
- seed demo segunda aplicación PASS;
- imágenes backend/frontend PASS;
- recursos residuales: ninguno.

## 4. Observabilidad integrada

### Health

- `GET /actuator/health/liveness` público;
- `GET /actuator/health/readiness` público;
- respuesta agregada únicamente;
- sin detalles internos;
- readiness vinculada a aplicación, PostgreSQL y disco;
- health de correo excluido de readiness.

### Prometheus

- endpoint `/actuator/prometheus`;
- cabecera `X-Gestudio-Metrics-Token`;
- secreto `APP_OBSERVABILITY_METRICS_TOKEN` independiente de JWT;
- comparación exacta en tiempo constante;
- configuración vacía mantiene fail-closed;
- token ausente, incorrecto, alterado o excesivo: `401`;
- token exacto: `200`;
- métricas JVM y proceso verificadas.

### Correlación y logs

- `X-Request-ID` seguro propagado;
- UUID generado para ausencia o valor inválido;
- MDC limpiado en `finally`;
- log HTTP con método, ruta sin query, estado, duración y outcome;
- sin cuerpos, cookies, Authorization, tokens ni secretos;
- saltos de línea/tabulaciones neutralizados.

### Evidencia final

- duración del drill: `00:02:07.0860516`;
- pasos: 8 PASS;
- fallos: 0;
- digest: `sha256:a982566903d55c8ce20c251ffaeb21cb5d4e949f61009bef47c6b7b6b525676c`.

## 5. Rollback compatible con imágenes anteriores a Actuator

Se agregó metadata por imagen:

```text
/app/build-metadata/flyway-latest
/app/build-metadata/git-revision
/app/build-metadata/health-contract
```

Contratos:

- `actuator-readiness-v1`: imagen actual; exige readiness `UP`;
- `legacy-api-401-v1`: imagen pre-Actuator; exige HTTP `401` de `/api/alumnos`.

El modo legacy no acepta una mera apertura de puerto. Demuestra que Spring terminó de iniciar y que la capa web/seguridad responde.

El rollback:

- mantiene igualdad exacta entre Flyway de base e imagen;
- rechaza imagen V6 contra base V7;
- crea backup previo;
- detecta contrato health actual/objetivo;
- cambia actual → legacy compatible;
- preserva alumno, Flyway V7 y tablas V7;
- vuelve legacy → actual;
- recupera readiness actual;
- conserva recuperación automática si target falla;
- elimina stack, volúmenes, imágenes, worktree y temporales.

Evidencia final:

- duración: `00:05:24`;
- pasos: 8 PASS;
- fallos: 0;
- digest: `sha256:d827350708d48930219d1e491191d1227364163d1f2c32842e4b3ddfb490e38b`.

## 6. Fallos encontrados y corregidos

1. contrato esperado `403` frente a `401` para credencial de métricas ausente;
2. `MvcRequestMatcher` incompatible con contexts sin MVC;
3. observabilidad externa deshabilitada por defecto en tests;
4. bean del token ausente en slice `@WebMvcTest`;
5. nuevo secreto ausente en validación de Compose productivo de CI;
6. artefacto rollback pre-Actuator marcado unhealthy por readiness inexistente.

Ningún fallo fue ocultado. El PR permaneció bloqueado hasta que los cinco workflows cerraron verdes sobre el mismo SHA.

## 7. Capacidades cerradas técnicamente

- GATE-0 baseline/documentación;
- GATE-1 seguridad/RBAC;
- GATE-1B liquidación por vigencia;
- Flyway V1-V7;
- demo automatizada y seed idempotente;
- emisor V7 source-owned apagado por defecto;
- backup PostgreSQL/recibos;
- restore aislado;
- rollback backend forward-compatible;
- observabilidad source-owned;
- runbooks de arranque, recuperación, rollback y diagnóstico.

## 8. Tareas pendientes

### Próximo trabajo interno

1. ejecutar los cinco recorridos humanos definidos en `docs/testing/human-role-walkthrough.md`;
2. completar GATE-2;
3. inventariar y retirar IDs técnicos visibles en flujos comerciales;
4. revisar búsqueda humana;
5. completar loading, vacío y error;
6. revisar pagos, caja, egresos, recibos, stock y asistencia;
7. validar foco, teclado, labels, contraste y móvil;
8. corregir sólo defectos demostrados;
9. repetir suites, smoke y seed después de las correcciones.

### Operación externa

- destino cifrado, retención, RPO/RTO y responsables de backups;
- registry por digest, firma, promoción y retención de imágenes;
- secret manager y rotación;
- Prometheus o equivalente desplegado;
- almacenamiento, dashboard y alertas;
- retención centralizada de logs;
- responsables, on-call y escalamiento;
- TLS, CORS y cookies en ambiente real;
- staging;
- autorización productiva.

### Bloqueo externo

- `JerePrograma/jere-platform#59` continúa bloqueando el receptor multipágina end-to-end.

## 9. Decisión final

| Salida | Estado |
|---|---|
| Desarrollo local | GO |
| Validación técnica local/CI | GO |
| Demo automatizada | PASS |
| Demo humana | PENDIENTE |
| Demo comercial | NO-GO |
| Staging | NO-GO |
| Producción | NO-GO |
| Desplegado | NO |
| Datos reales utilizados | NO |

El próximo gate interno es GATE-2 y los recorridos humanos. La producción no queda implícitamente autorizada por ninguna prueba técnica.