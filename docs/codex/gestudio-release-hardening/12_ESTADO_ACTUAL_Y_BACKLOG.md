# Estado actual y backlog unificado

> Fecha de corte: 20 de julio de 2026  
> Zona horaria: `America/Argentina/Buenos_Aires`  
> Rama objetivo: `main`  
> Estado global: **NO-GO para demo comercial, staging y producción**

Este archivo es la fuente vigente para gates, prioridades, riesgos y próximos pasos. La bitácora conserva la secuencia histórica y los documentos de cierre conservan la evidencia detallada.

## 1. Resumen ejecutivo

Integrado y probado o listo para integración después de gates finales:

- baseline reproducible;
- seguridad y RBAC fail-closed;
- catálogo de 32 permisos y matrices base;
- liquidación financiera por vigencia;
- snapshots atómicos de cargos;
- Flyway V1-V7;
- demo interna automatizada y seed idempotente;
- emisor administrativo firmado de referencias mínimas de estudiantes, apagado por defecto;
- backup PostgreSQL y recibos con manifiesto SHA-256;
- restore protegido en base alternativa;
- rollback backend forward-compatible con backup previo y retorno al artefacto actual;
- observabilidad mínima con liveness, readiness, Prometheus protegido, request ID y logs sanitizados.

Continúan abiertos:

- recorridos humanos completos por rol;
- GATE-2 UX crítica;
- servidor externo de métricas, dashboards, alertas, retención de logs y responsables;
- política operativa de backups: destino, cifrado, retención, RPO/RTO y responsables;
- registry, digest, firma, promoción y retención de imágenes;
- gestión de secretos, TLS, CORS y cookies en ambiente real;
- staging;
- producción;
- receptor multipágina de Jere Platform, bloqueado externamente.

## 2. Estado de gates

| Gate o capacidad | Estado | Evidencia principal |
|---|---|---|
| GATE-0 — baseline y documentación | CERRADO | scripts canónicos, Docker, CI y fuentes unificadas |
| GATE-1 — seguridad y RBAC | CERRADO / REVALIDADO | 401/403/409, backend fail-closed, frontend alineado, 32 permisos |
| GATE-1B — liquidación por vigencia | CERRADO TÉCNICAMENTE | pruebas PostgreSQL y snapshot atómico |
| Flyway V1-V7 | CERRADO | base vacía, smoke, seed, restore y rollback |
| Demo interna automatizada | PASS | seed doble, cinco logins, RBAC e integridad |
| Demo humana por rol | PENDIENTE | recorrido visual y funcional documentado |
| Integración Gestudio → Jere Platform | SOURCE INTEGRADA | emisor firmado y apagado; end-to-end bloqueado por `jere-platform#59` |
| Backup técnico | PASS | dump custom, recibos, manifiesto y hashes |
| Restore técnico aislado | PASS | datos, V7 y recibos recuperados |
| Rollback backend | PASS / INTEGRADO | `main` merge `2eb9a8442c9a0c329c7ddaea42d3ea5c5827f35c` |
| Observabilidad mínima source-owned | PASS TÉCNICO | health, métricas protegidas, correlación, logs y drill |
| Alertas y monitoreo externo | ABIERTO / BLOCKED | requiere ambiente, scraper, almacenamiento, notificación y responsables |
| Política operativa de backup | ABIERTA | faltan destino, cifrado, retención, RPO/RTO y responsables |
| Política operativa de artefactos | ABIERTA | faltan registry, digest, firma, promoción y retención |
| GATE-2 — UX crítica | ABIERTO | mejoras parciales; falta recorrido exhaustivo |
| Staging | NO-GO | ambiente no definido ni autorizado |
| Producción | NO-GO | no autorizada |

## 3. Evidencia ejecutada

### Aplicación después de V7 y rollback

- backend antes de observabilidad: **162/162 PASS**;
- backend con observabilidad incorporada: **171 pruebas ejecutadas**; las regresiones de contexts/slices fueron identificadas y corregidas;
- frontend: **142/142 PASS**;
- lint: PASS;
- build frontend: PASS;
- backend image: PASS;
- frontend image: PASS;
- `Scope All`: PASS después de corregir el matcher Actuator;
- Compose local/productivo: configuración válida después de suministrar secreto sintético en CI;
- smoke V1-V7: PASS en gates integrados; revalidación obligatoria sobre HEAD final;
- seed primera y segunda aplicación: PASS en gates integrados; revalidación obligatoria sobre HEAD final;
- recursos Docker residuales: ninguno en drills verdes.

### Backup y restore

- runner: Ubuntu 24.04.4;
- Git 2.54.0;
- Docker 28.0.4;
- Compose 2.38.2;
- PowerShell 7.6.3;
- duración: `00:02:17`;
- 9 pasos PASS;
- 0 fallos;
- datos, tablas V7 y recibo restaurados;
- base origen no alterada;
- cleanup completo.

### Rollback backend

- PR integrado: `#19`;
- merge `main`: `2eb9a8442c9a0c329c7ddaea42d3ea5c5827f35c`;
- duración inicial del drill: `00:03:21`;
- 8 pasos PASS;
- imagen V6 rechazada;
- backup previo generado;
- artefacto anterior compatible healthy;
- alumno, Flyway V7 y tablas V7 preservados;
- retorno a imagen actual verificado;
- cleanup completo.

### Observabilidad mínima

Drill verde demostrado:

- liveness `UP`;
- readiness `UP` con PostgreSQL;
- health sin detalles internos;
- Prometheus `401` sin credencial exacta;
- Prometheus `200` con token exacto;
- métricas JVM y proceso presentes;
- request ID propagado, generado y saneado;
- log HTTP correlacionado;
- secretos sintéticos ausentes de logs;
- cleanup completo;
- duración: `00:01:34.3933724`;
- 8 pasos PASS;
- 0 fallos;
- artefacto digest: `sha256:9d3af5535bed637bb52e61be3cf2e1bce1c17b0877340f1bae57c4f90e496ba0`.

Fallos corregidos durante el gate:

1. expectativa incorrecta `403` frente a `401` para credencial ausente;
2. `MvcRequestMatcher` incompatible con contexts no web;
3. observabilidad externa deshabilitada por defecto en tests;
4. bean del token ausente en slice `@WebMvcTest`;
5. secreto sintético ausente en validación de Compose productivo.

## 4. Capacidades cerradas

### Seguridad

- roles múltiples efectivos;
- `SUPERADMIN`, `DIRECCION`, `ADMINISTRADOR`, `SECRETARIA` y `CAJA`;
- `PROFESOR` inactivo y no asignable;
- catálogo de 32 permisos;
- invalidación por `authVersion`;
- refresh token HttpOnly;
- frontend condicionado por backend;
- STOMP retirado;
- Actuator fail-closed fuera de health;
- Prometheus con secreto independiente.

### Finanzas

- mensualidad al primer día del mes;
- matrícula al 1 de enero;
- tarifa histórica obligatoria;
- condición económica opcional;
- costo particular sólo desde condición efectiva;
- `BigDecimal`, escala 2 y `HALF_UP`;
- matrícula multidisciplina por mayor importe final;
- cargo y snapshot atómicos;
- idempotencia secuencial y concurrente;
- recargo tardío separado;
- fuentes legacy rechazadas y retiradas de UI.

### Demo

- datos sintéticos;
- cinco usuarios y matrices RBAC;
- doble aplicación idempotente;
- lanzador `Start/Status/Stop/Reset/SeedNative`;
- smoke, caja, stock, recibos, outbox e integridad.

### Integración V7

- `GESTUDIO_STUDENT` con ID, nombre visible y activo;
- tenant UUID explícito;
- snapshots/páginas inmutables;
- SHA-256 y HMAC-SHA256;
- secreto externo;
- permisos administrativos dobles;
- auditoría sanitizada;
- feature apagada por defecto;
- sin transporte automático.

### Recuperación y rollback

- `pg_dump` custom y recibos opcionales;
- manifiesto con HEAD, Flyway, tamaños y hashes;
- restore destructivo protegido;
- restore alternativo probado;
- metadata Flyway/revisión dentro de imagen backend;
- igualdad estricta esquema ↔ artefacto;
- backup previo al rollback;
- recuperación automática de imagen anterior ante target unhealthy;
- drills permanentes en GitHub Actions.

### Observabilidad source-owned

- Actuator health y Prometheus;
- readiness real en Dockerfile y Compose;
- token externo exacto y fail-closed;
- request ID seguro y UUID de reemplazo;
- MDC limpiado en `finally`;
- logs sin query strings, cuerpos ni credenciales;
- drill y workflow permanente;
- runbook de diagnóstico y rollback.

## 5. Backlog priorizado

### P0

No se identificó un defecto P0 abierto. Una regresión de seguridad, liquidación, idempotencia, Flyway, restore, rollback u observabilidad reabre P0 y bloquea todo.

### P1 — operación externa

| ID | Tarea | Estado | Criterio de cierre |
|---|---|---|---|
| OPS-004 | backup técnico | DONE | paquete, hashes y drill |
| OPS-005 | restore aislado | DONE | DB, V7, recibos y cleanup |
| OPS-006 | rollback backend | DONE / MAIN | ida/vuelta compatible y datos preservados |
| OPS-007A | observabilidad source-owned | DONE TÉCNICO | health, métricas, correlación, logs y drill |
| OPS-007B | monitoreo y alertas externas | BLOCKED | scraper, storage, dashboard, alertas y responsables |
| OPS-008 | runbooks | DONE | arranque, uso, recovery, rollback y observabilidad |
| OPS-009 | política de backup | PENDIENTE | cifrado, destino, retención, RPO/RTO y responsables |
| OPS-010 | política de artefactos | PENDIENTE | registry, digest, firma, promoción y retención |
| OPS-011 | gestión de secretos | PENDIENTE | secret manager y rotación demostrados |
| OPS-012 | TLS/CORS/cookies | PENDIENTE | validación en ambiente destino |
| OPS-013 | staging | BLOCKED | host, dominio, responsables y ventana |

### P1 — demo humana y UX

| ID | Tarea | Estado | Criterio de cierre |
|---|---|---|---|
| DEMO-HUM-001 | recorrido SUPERADMIN | PENDIENTE | circuito completo y evidencia |
| DEMO-HUM-002 | recorrido DIRECCION | PENDIENTE | accesos/denegaciones documentados |
| DEMO-HUM-003 | recorrido ADMINISTRADOR | PENDIENTE | accesos/denegaciones documentados |
| DEMO-HUM-004 | recorrido SECRETARIA | PENDIENTE | alumno, inscripción y asistencia |
| DEMO-HUM-005 | recorrido CAJA | PENDIENTE | cargos, pagos, recibos, caja y stock |
| UX-001 | eliminar IDs técnicos | PARCIAL | cero IDs en flujos comerciales |
| UX-002 | búsqueda humana | PARCIAL | nombre, apellido, ambos órdenes y documento |
| UX-003 | loading/empty/error | PENDIENTE | feedback y siguiente acción claros |
| UX-004 | pagos/caja/egresos/recibos | PENDIENTE | referencias humanas y ARS consistente |
| UX-005 | stock y reversión | PENDIENTE | movimientos como única fuente |
| UX-006 | asistencia | PENDIENTE | guardado/error/vacío explícitos |
| UX-007 | accesibilidad | PENDIENTE | foco, teclado, labels y contraste |
| UX-008 | móvil | PENDIENTE | recorridos principales utilizables |

### Bloqueos externos

| ID | Bloqueo | Impacto |
|---|---|---|
| EXT-JP-059 | `JerePrograma/jere-platform#59` | bloquea reconciliación multipágina end-to-end |
| EXT-OBS | ambiente/scraper/canales no provistos | bloquea alertas y retención reales |
| EXT-STAGING | ambiente no provisto | bloquea gates externos |
| EXT-PROD | autorización inexistente | bloquea despliegue productivo |

### P2

- retiro físico de columnas legacy después de reconciliación;
- serialización estable de `PageImpl`;
- agente Mockito explícito para JDK futuros;
- retención automática de snapshots V7;
- tracing distribuido cuando exista más de un servicio;
- portal de familias;
- Mercado Pago;
- WhatsApp automático;
- facturación electrónica;
- multi-sede/multi-tenancy;
- reapertura de Profesor sólo con ownership demostrado.

## 6. Riesgos

### Bloqueantes para staging/producción

- monitoreo externo y alertas no instalados;
- política de backups y artefactos incompleta;
- secretos no demostrados en ambiente destino;
- TLS/CORS/cookies no validados;
- staging inexistente;
- recorridos humanos incompletos.

### Altos

- usar tags mutables en rollback;
- construir de urgencia un artefacto anterior no probado;
- confundir backup técnico con política completa;
- exponer Prometheus sin segmentación o token;
- habilitar V7 sin receptor compatible;
- vender la demo como SaaS con SLA maduro.

### Medios

- DB y recibos no forman una transacción distribuida;
- rollback backend no coordina automáticamente frontend;
- efectos externos no se revierten con feature flag;
- cobertura visual incompleta;
- columnas legacy físicas;
- warnings de `open-in-view`, dialecto y Mockito;
- logs sin almacenamiento central todavía.

## 7. Secuencia siguiente

1. fusionar PR `#20` después de todos los workflows verdes sobre un único SHA;
2. completar GATE-2 y recorridos humanos por rol;
3. corregir defectos UX demostrables y repetir recorridos;
4. definir políticas de backup, artefactos y secretos;
5. proveer scraper, storage, dashboard, alertas y responsables;
6. obtener staging;
7. repetir todos los gates en staging;
8. mantener producción en NO-GO hasta autorización independiente.

## 8. Comandos canónicos

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-demo-seed.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\verify-backup-restore.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\verify-application-rollback.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\verify-observability.ps1
```

## 9. Veredicto

- desarrollo/validación local: GO;
- seguridad, finanzas, V7, demo automatizada, backup, restore y rollback técnico: PASS;
- observabilidad source-owned: PASS técnico;
- alertas/retención externas: BLOCKED;
- demo humana/comercial: NO-GO;
- staging: NO-GO;
- producción: NO-GO;
- desplegado: no;
- datos reales utilizados: no.
