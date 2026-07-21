# Decisiones y bloqueos vigentes

> Fecha de corte: 20 de julio de 2026  
> Rama operativa: `main`  
> Estado global: **NO-GO para demo comercial, staging y producción**

Implementación, prueba, integración y autorización de despliegue son estados distintos.

## Decisiones vigentes

### Seguridad

- 32 permisos exactos;
- `SUPERADMIN`, `DIRECCION`, `ADMINISTRADOR`, `SECRETARIA` y `CAJA`;
- `PROFESOR` inactivo/no asignable;
- backend fail-closed;
- 401/403/409 diferenciados;
- frontend condicionado por permisos;
- STOMP retirado.

Estado: **INTEGRADA Y VALIDADA**.

### Flyway

- V1-V7 inmutables;
- correcciones futuras mediante V8 o superior;
- sin down migrations;
- seed demo fuera de Flyway;
- rollback de código conserva todas las migraciones aplicadas.

Estado: **INTEGRADA Y VALIDADA**.

### Liquidación financiera

- mensualidad al primer día del mes;
- matrícula al 1 de enero;
- tarifa histórica obligatoria;
- condición efectiva opcional;
- costo particular sólo desde condición;
- descuentos con `BigDecimal`, escala 2 y `HALF_UP`;
- matrícula por mayor importe final;
- cargo/snapshot atómicos;
- recargo tardío separado;
- fuentes legacy fuera de cálculo y edición operativa.

Estado: **INTEGRADA Y VALIDADA**.

### Demo

- datos sintéticos;
- cinco usuarios;
- doble aplicación idempotente;
- demo persistente separada de gates;
- demo automatizada no reemplaza recorrido humano.

Estado: **AUTOMATIZADA Y VALIDADA; HUMANA PENDIENTE**.

### Integración V7

- Gestudio conserva ownership del estudiante;
- sólo ID, nombre visible y activo;
- tenant UUID explícito;
- snapshots/páginas inmutables;
- SHA-256/HMAC-SHA256;
- secreto externo;
- doble permiso administrativo;
- feature apagada;
- sin push, scheduler, broker, UI ni Scalaris;
- end-to-end bloqueado por `JerePrograma/jere-platform#59`.

Estado: **SOURCE INTEGRADA; OPERACIÓN EXTERNA BLOQUEADA**.

### Backup/restore

- dump custom y recibos separados;
- backend detenido para punto consistente completo;
- manifiesto con HEAD, Flyway, tamaños y hashes;
- restore destructivo protegido;
- restaurar primero a base alternativa;
- verificar Flyway y archivos antes de promoción;
- base y recibos no forman transacción distribuida.

Estado: **VALIDADO TÉCNICAMENTE**.

### Rollback forward-compatible

- no borrar ni editar V7;
- la imagen objetivo declara `/app/build-metadata/flyway-latest`;
- la versión declarada debe igualar el máximo Flyway exitoso de la base;
- imagen sin metadata o con V6 se rechaza antes de cambiar backend;
- `ExpectedCurrentImage` evita carreras;
- backup consistente previo por defecto;
- si el target no queda healthy, se intenta recuperar automáticamente la imagen anterior;
- volver al artefacto actual usa el mismo mecanismo;
- feature flag es mitigación, no reversión de efectos externos;
- artefactos operativos deben identificarse por digest, no sólo tag.

Estado: **INTEGRADA EN MAIN Y VALIDADA TÉCNICAMENTE**.

### Observabilidad source-owned

- liveness y readiness públicos con estado agregado únicamente;
- readiness real en Dockerfile y Compose;
- Prometheus protegido por token externo independiente;
- token ausente, incorrecto, vacío o alterado devuelve `401`;
- comparación exacta en tiempo constante;
- todos los demás endpoints Actuator denegados o no expuestos;
- `X-Request-ID` propagado o reemplazado por UUID;
- MDC limpiado en `finally`;
- logs HTTP sin query strings, cuerpos, cookies ni secretos;
- drill descartable y workflow permanente;
- runbook de diagnóstico, umbrales iniciales y rollback.

Estado: **IMPLEMENTADA Y VALIDADA TÉCNICAMENTE**.

### Monitoreo externo

- el código no incorpora un servidor Prometheus ni Grafana;
- alertas, retención y canales dependen del ambiente destino;
- health y métricas source-owned no equivalen a un SLA productivo;
- los umbrales iniciales deben calibrarse con carga real.

Estado: **BLOQUEADO POR AMBIENTE Y RESPONSABLES**.

### Release

| Salida | Estado |
|---|---|
| Desarrollo/validación local | GO |
| Demo automatizada | PASS |
| Demo humana | pendiente |
| Demo comercial | NO-GO |
| Staging | NO-GO |
| Producción | NO-GO |

## Bloqueos cerrados

| ID | Bloqueo | Evidencia |
|---|---|---|
| BLK-RBAC | autorización y matrices | GATE-1 |
| BLK-FIN | doble fuente financiera | GATE-1B |
| BLK-DEMO-AUTO | falta de evidencia automatizada | smoke/seed doble |
| BLK-V7-SCHEMA | gates esperaban V6 | V1-V7 PASS |
| BLK-BACKUP | backup inexistente | dump/recibos/manifiesto |
| BLK-RESTORE | restore no probado | base alternativa y recibo |
| BLK-ROLLBACK | artefacto anterior incompatible | drill ida/vuelta con V7 y datos preservados |
| BLK-OBS-SOURCE | health/métricas/correlación/logs ausentes | Actuator, token, request ID, drill y runbook |

## Bloqueos abiertos

### BLK-OBS-EXTERNAL — Monitoreo y alertas reales

Faltan:

- scraper Prometheus o equivalente;
- almacenamiento y retención de métricas;
- dashboard;
- alertas entregadas a responsables;
- retención centralizada de logs;
- prueba de rotación del token;
- on-call y escalamiento;
- calibración con carga real.

Bloquea staging y producción.

### BLK-JP-059 — Receptor externo

`JerePrograma/jere-platform#59` bloquea reconciliación multipágina end-to-end. No bloquea el emisor local apagado.

### BLK-UX — Recorridos humanos y GATE-2

Faltan IDs técnicos, búsquedas humanas, loading/empty/error, pagos/caja/stock/asistencia, accesibilidad, móvil y cinco recorridos por rol. Bloquea demo comercial.

### BLK-OPS-POLICY — Políticas reales

Faltan:

- destino externo cifrado;
- retención, RPO/RTO y responsables;
- registry por digest;
- firma/promoción/retención de imágenes;
- secret manager y rotación.

Bloquea staging y producción.

### BLK-ENV — Ambiente externo

Faltan host, dominio, TLS, CORS, cookies, responsables, ventana y autorización. Bloquea staging y producción.

## Decisiones diferidas

- Profesor sólo con ownership y pruebas cruzadas;
- Observaciones sin superficie;
- tracing distribuido cuando exista más de un servicio;
- portal familias;
- Mercado Pago/facturación;
- WhatsApp automático;
- multi-sede/multi-tenancy;
- transporte automático a Jere Platform.

## Próximas acciones

1. fusionar observabilidad sólo con todos los gates verdes sobre un SHA único;
2. completar GATE-2 y recorridos humanos;
3. definir políticas operativas;
4. proveer monitoreo externo y responsables;
5. disponer staging;
6. repetir gates en staging;
7. mantener producción en NO-GO hasta autorización independiente.
