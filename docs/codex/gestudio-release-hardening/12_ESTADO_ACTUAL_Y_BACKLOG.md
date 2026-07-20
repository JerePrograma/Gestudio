# Estado actual y backlog unificado

> Fecha de corte: 20 de julio de 2026  
> Zona horaria: `America/Argentina/Buenos_Aires`  
> Rama objetivo: `main`  
> Estado global: **NO-GO para demo comercial, staging y producción**

Este documento reemplaza los estados operativos anteriores. Los documentos históricos conservan la secuencia de decisiones y evidencias, pero este archivo es la fuente vigente para gates, prioridades y próximos pasos.

## 1. Resumen ejecutivo

Gestudio tiene integrados y probados:

- baseline reproducible;
- seguridad y RBAC fail-closed;
- catálogo de 32 permisos y matrices base;
- liquidación financiera por vigencia;
- snapshots atómicos de cargos;
- Flyway V1-V7;
- demo interna automatizada y seed idempotente;
- emisor administrativo firmado de referencias mínimas de estudiantes, deshabilitado por defecto;
- backup PostgreSQL con manifiesto e inclusión opcional de recibos;
- restore protegido y drill descartable de recuperación.

Continúan abiertos:

- recorridos humanos completos por rol;
- GATE-2 UX crítica;
- rollback forward-compatible de aplicación;
- observabilidad mínima y alertas;
- política de backups: retención, cifrado, custodia, RPO y RTO;
- staging;
- producción;
- receptor multipágina de Jere Platform, bloqueado externamente.

## 2. Estado de gates

| Gate o capacidad | Estado | Evidencia principal |
|---|---|---|
| GATE-0 — baseline y documentación | CERRADO | scripts canónicos, Docker, CI y documentación |
| GATE-1 — seguridad y RBAC | CERRADO / REVALIDADO | 401/403/409, backend fail-closed, frontend alineado, 32 permisos |
| GATE-1B — liquidación por vigencia | CERRADO TÉCNICAMENTE | 149 pruebas al cierre y 162 después de V7; snapshot atómico |
| Flyway V1-V7 | CERRADO | PostgreSQL vacío, smoke, seed y restore |
| Demo interna automatizada | PASS | seed doble, cinco logins, RBAC e integridad |
| Demo humana por rol | PENDIENTE | requiere recorrido visual y funcional documentado |
| Integración Gestudio → Jere Platform | CAPACIDAD SOURCE INTEGRADA | emisor firmado y deshabilitado; end-to-end bloqueado por `jere-platform#59` |
| Backup técnico | PASS | dump custom, recibos, manifiesto y hashes |
| Restore técnico aislado | PASS | datos, V7 y recibos recuperados en base alternativa |
| Política operativa de backup | ABIERTA | faltan destino externo, cifrado, retención, RPO/RTO y responsables |
| Rollback de aplicación | ABIERTO | falta drill con artefacto compatible con migraciones aplicadas |
| Observabilidad | ABIERTO | faltan métricas, alertas y runbook de incidentes |
| GATE-2 — UX crítica | ABIERTO | mejoras parciales; falta recorrido exhaustivo |
| Staging | NO-GO | no definido ni autorizado |
| Producción | NO-GO | no autorizada |

## 3. Evidencia ejecutada vigente

### Aplicación

- backend: **162/162 PASS** después de integrar V7;
- frontend: **142/142 PASS**;
- lint: PASS;
- build frontend: PASS;
- backend image: PASS;
- frontend image: PASS;
- `Scope All`: PASS;
- Docker Compose local y productivo: configuración válida;
- smoke canónico: PASS con Flyway V1-V7;
- seed demo: PASS en primera y segunda aplicación;
- residuos Docker de esos gates: ninguno.

### Backup y restore

Drill ejecutado sobre el contenido del PR técnico:

- runner: Ubuntu 24.04.4;
- Git 2.54.0;
- Docker 28.0.4;
- Docker Compose 2.38.2;
- PowerShell 7.6.3;
- duración: `00:02:17`;
- pasos aprobados: 9;
- fallos: 0;
- resultado global: PASS.

Casos demostrados:

1. stack aislado healthy;
2. Flyway V1-V7 en origen;
3. fixture sintética de alumno y recibo;
4. backup consistente con backend detenido;
5. manifiesto, tamaños y SHA-256 válidos;
6. mutación posterior del origen;
7. restore sin confirmación rechazado;
8. overwrite del origen sin autorización rechazado;
9. restore en base alternativa;
10. alumno, tablas V7 y recibo recuperados;
11. origen no modificado por el restore alternativo;
12. cleanup sin contenedores, volúmenes ni redes residuales.

## 4. Capacidades cerradas

### Seguridad

- roles múltiples efectivos;
- `SUPERADMIN`, `DIRECCION`, `ADMINISTRADOR`, `SECRETARIA` y `CAJA`;
- `PROFESOR` inactivo y no asignable;
- catálogo de 32 permisos;
- matrices base;
- invalidación por `authVersion`;
- refresh token en cookie HttpOnly;
- frontend condicionado por permisos del backend;
- STOMP retirado.

### Finanzas

- mensualidades por primer día del mes;
- matrículas por 1 de enero;
- tarifa histórica obligatoria;
- condición económica opcional;
- costo particular únicamente desde condición efectiva;
- descuentos con `BigDecimal`, escala 2 y `HALF_UP`;
- matrícula multidisciplina por mayor importe final;
- cargo y snapshot atómicos;
- idempotencia secuencial y concurrente;
- recargo tardío como cargo separado;
- campos legacy rechazados en API y retirados de la UI operativa.

### Demo

- dataset sintético;
- cinco usuarios y matrices RBAC;
- ejecución doble idempotente;
- lanzador persistente `Start/Status/Stop/Reset/SeedNative`;
- smoke, integridad financiera, caja, stock, recibos y outbox;
- sin datos reales ni credenciales versionadas.

### Integración V7

- referencias mínimas `GESTUDIO_STUDENT`;
- ID, nombre de visualización y activo únicamente;
- mapping explícito a tenant UUID;
- snapshots y páginas inmutables;
- SHA-256 y HMAC-SHA256;
- secreto dedicado externo;
- permisos administrativos dobles;
- auditoría sanitizada;
- función deshabilitada por defecto;
- sin transporte automático.

### Recuperación

- `pg_dump` custom con `--no-owner --no-privileges`;
- archivo de recibos opcional;
- manifiesto con HEAD, Flyway, tamaños y SHA-256;
- backup completo exige consistencia de aplicación;
- restore destructivo protegido por switches explícitos;
- restauración sobre base alternativa recomendada y probada;
- verificación de Flyway posterior al restore;
- drill permanente en GitHub Actions.

## 5. Backlog priorizado

### P0 — bloqueos de integridad

No se identificó un defecto P0 abierto en el código integrado. Cualquier regresión de seguridad, liquidación, idempotencia, Flyway o restore reabre esta prioridad y bloquea todo lo demás.

### P1 — demo humana y UX

| ID | Tarea | Estado | Criterio de cierre |
|---|---|---|---|
| DEMO-HUM-001 | recorrido SUPERADMIN | PENDIENTE | circuito completo y evidencias visuales |
| DEMO-HUM-002 | recorrido DIRECCION | PENDIENTE | accesos y denegaciones documentados |
| DEMO-HUM-003 | recorrido ADMINISTRADOR | PENDIENTE | accesos y denegaciones documentados |
| DEMO-HUM-004 | recorrido SECRETARIA | PENDIENTE | alumno, inscripción y asistencia sin errores |
| DEMO-HUM-005 | recorrido CAJA | PENDIENTE | cargos, pagos, recibos, caja y stock |
| UX-001 | eliminar IDs técnicos visibles | PARCIAL | cero IDs en flujos comerciales |
| UX-002 | búsqueda humana completa | PARCIAL | nombre, apellido, ambos órdenes y documento |
| UX-003 | loading, empty y error | PENDIENTE | feedback y siguiente acción claros |
| UX-004 | pagos/caja/egresos/recibos | PENDIENTE | referencias humanas y ARS consistente |
| UX-005 | stock y reversión | PENDIENTE | sin edición que eluda movimientos |
| UX-006 | asistencia | PENDIENTE | guardado, error y estado vacío explícitos |
| UX-007 | accesibilidad básica | PENDIENTE | foco, teclado, labels y contraste |
| UX-008 | móvil real | PENDIENTE | recorridos principales utilizables |

### P1 — operación

| ID | Tarea | Estado | Criterio de cierre |
|---|---|---|---|
| OPS-004 | backup técnico | DONE | paquete, hashes y evidencia automatizada |
| OPS-005 | restore aislado | DONE | recuperación de DB y recibos, cleanup |
| OPS-006 | rollback de aplicación | EN PROGRESO | rollback forward-compatible y retorno a versión actual |
| OPS-007 | observabilidad mínima | PENDIENTE | health real, métricas, logs y alertas |
| OPS-008 | runbook local | DONE | arranque, uso, backup y diagnóstico |
| OPS-009 | política de backup | PENDIENTE | cifrado, destino, retención, RPO/RTO y responsables |
| OPS-010 | gestión de secretos | PENDIENTE | secret manager y rotación demostrados |
| OPS-011 | TLS/CORS/cookies | PENDIENTE | validación en ambiente destino |
| OPS-012 | staging | BLOCKED | host, dominio, responsables y ventana |

### Bloqueos externos

| ID | Bloqueo | Impacto |
|---|---|---|
| EXT-JP-059 | `JerePrograma/jere-platform#59` | impide declarar operativa la reconciliación multipágina end-to-end |
| EXT-STAGING | ambiente no provisto | impide ejecutar gates de staging |
| EXT-PROD | autorización inexistente | impide despliegue productivo |

### P2 — evolución diferida

- reconciliación para retiro físico de columnas legacy;
- serialización estable de `PageImpl`;
- configuración explícita del agente Mockito para JDK futuros;
- política automática de retención de snapshots V7;
- portal de alumnos/familias;
- Mercado Pago;
- WhatsApp automático;
- facturación electrónica;
- multi-sede y multi-tenancy;
- reapertura del rol Profesor con ownership demostrado.

## 6. Riesgos

### Bloqueantes para staging/producción

- rollback no probado;
- observabilidad y alertas no cerradas;
- política de secretos no demostrada en ambiente destino;
- TLS, CORS, cookies y URLs no validados en un host real;
- staging inexistente;
- recorridos humanos incompletos.

### Altos

- confundir backup técnico con política operacional completa;
- restaurar sobre la base origen sin validar antes una base alternativa;
- usar un artefacto viejo que no contenga migraciones ya aplicadas;
- habilitar el emisor V7 sin receptor multipágina compatible;
- vender la demo como SaaS con SLA maduro.

### Medios

- PostgreSQL y recibos no se restauran en una transacción distribuida;
- cobertura visual no exhaustiva;
- columnas legacy aún presentes físicamente;
- warnings de `open-in-view`, dialecto y Mockito;
- tiempo de Docker frío.

### Aceptados temporalmente

- `PROFESOR` inactivo;
- Observaciones fuera de superficie;
- una instalación/base por cliente;
- seed sólo para demo descartable;
- integración V7 manual y deshabilitada;
- programa piloto sin SLA productivo.

## 7. Secuencia obligatoria siguiente

1. integrar el cierre de backup/restore en `main`;
2. ejecutar un rollback forward-compatible conservando V7;
3. volver a la versión actual y comprobar datos/Flyway;
4. cerrar observabilidad mínima;
5. completar GATE-2 y recorridos humanos por rol;
6. definir política de backup, secretos y responsables;
7. obtener un ambiente staging;
8. ejecutar todos los gates en staging;
9. mantener producción en NO-GO hasta autorización independiente.

## 8. Comandos canónicos

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-demo-seed.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\ops\verify-backup-restore.ps1
```

Demo persistente:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Start
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Status
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Stop
```

## 9. Veredicto vigente

- código financiero: integrado y probado;
- seguridad: integrada y probada;
- V7: integrada y probada;
- demo automatizada: PASS;
- backup/restore técnico: PASS;
- demo humana: pendiente;
- demo comercial: NO-GO;
- staging: NO-GO;
- producción: NO-GO;
- desplegado: no.
