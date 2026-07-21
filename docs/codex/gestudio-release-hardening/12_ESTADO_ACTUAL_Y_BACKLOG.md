# Estado actual y backlog unificado

> Fecha de corte: 21 de julio de 2026  
> Zona horaria: `America/Argentina/Buenos_Aires`  
> Rama objetivo: `main`  
> HEAD reconciliado al iniciar GATE-2: `db89c3e11056e95417cc093034c821bc3dfdd015`  
> Estado global: **NO-GO para demo comercial, staging y producción**

Este archivo es la autoridad documental vigente para gates, prioridades, riesgos y próximos pasos. Git y GitHub prevalecen ante cualquier divergencia. La secuencia detallada de GATE-2 se registra en `21_GATE_2_UX_OPERATIVA_2026-07-21.md`.

## 1. Resumen ejecutivo

Capacidades integradas y técnicamente probadas:

- seguridad y RBAC fail-closed con 32 permisos;
- roles `SUPERADMIN`, `DIRECCION`, `ADMINISTRADOR`, `SECRETARIA` y `CAJA`;
- `PROFESOR` inactivo y no asignable;
- liquidación financiera por vigencia y snapshots atómicos;
- Flyway V1-V7 forward-only;
- demo interna automatizada con seed idempotente y cinco usuarios;
- backup PostgreSQL/recibos, restore aislado y rollback forward-compatible;
- observabilidad mínima source-owned integrada mediante PR `#20` y merge `7dc07d649a468934f3c099a92e5d32747cf64347`;
- emisor `GESTUDIO_STUDENT` integrado y apagado por defecto;
- receptor multipágina integrado en Jere Platform mediante PR `#60`;
- issue técnico `jere-platform#59` cerrado.

Continúan abiertos:

- recorridos humanos completos por los cinco roles;
- GATE-2 UX crítica;
- transporte desplegado y smoke end-to-end Gestudio → Jere Platform;
- issue coordinador `jere-platform#51`, incluidos Scalaris y requisitos productivos;
- servidor externo de métricas, dashboards, alertas y retención;
- políticas operativas de backup, artefactos y secretos;
- TLS/CORS/cookies en ambiente real;
- staging;
- producción.

## 2. Estado de gates

| Gate o capacidad | Estado | Evidencia principal |
|---|---|---|
| GATE-0 — baseline y documentación | CERRADO | scripts canónicos, Docker, CI y fuentes unificadas |
| GATE-1 — seguridad y RBAC | CERRADO / REVALIDADO | 401/403/409, backend fail-closed, frontend alineado |
| GATE-1B — liquidación por vigencia | CERRADO TÉCNICAMENTE | PostgreSQL real y snapshot atómico |
| Flyway V1-V7 | CERRADO | base vacía, smoke, seed, restore y rollback |
| Demo interna automatizada | PASS histórico | requiere revalidación sobre cada SHA candidato |
| Demo humana por rol | PENDIENTE | falta evidencia funcional, visual, accesible y móvil |
| GATE-2 — UX crítica | ABIERTO | dos defectos reproducibles en corrección; recorrido exhaustivo pendiente |
| Integración source Gestudio/Jere Platform | INTEGRADA | emisor y receptor presentes; emisor apagado |
| Transporte Gestudio → Jere Platform | NO DEMOSTRADO | no existe despliegue ni smoke end-to-end |
| Backup técnico | PASS | dump custom, recibos, manifiesto y hashes |
| Restore técnico aislado | PASS | datos, V7 y recibos recuperados |
| Rollback backend | PASS / MAIN | merge `2eb9a8442c9a0c329c7ddaea42d3ea5c5827f35c` |
| Observabilidad mínima source-owned | PASS / MAIN | PR `#20`, health, métricas, correlación, logs y drill |
| Monitoreo y alertas externas | BLOCKED | requiere ambiente y responsables |
| Política operativa de backup | ABIERTA | faltan cifrado, destino, retención y RPO/RTO |
| Política operativa de artefactos | ABIERTA | faltan registry, digest, firma y promoción |
| Staging | NO-GO | ambiente no definido ni autorizado |
| Producción | NO-GO | no autorizada |

## 3. Evidencia técnica integrada previa a GATE-2

- backend: 171 pruebas en el último gate con observabilidad;
- frontend: 142 pruebas;
- lint y build frontend: PASS;
- Scope All: PASS;
- smoke V1-V7: PASS;
- seed primera y segunda aplicación: PASS;
- backup/restore: 9 PASS, 0 fallos;
- rollback: 8 PASS, 0 fallos;
- observabilidad: 8 PASS, 0 fallos;
- imagen V6 rechazada contra base V7;
- Prometheus `401` sin token exacto y `200` con token;
- request ID y logs sanitizados verificados;
- recursos Docker residuales: ninguno en drills verdes.

Estos resultados son evidencia histórica integrada. No equivalen a workflows verdes sobre un SHA nuevo y no sustituyen recorridos humanos.

## 4. GATE-2 — estado de ejecución

### Reconciliación

- `main` verificado en `db89c3e11056e95417cc093034c821bc3dfdd015` al iniciar;
- PR abiertos al iniciar: ninguno;
- issues abiertos en Gestudio al iniciar: ninguno;
- observabilidad `#20`: fusionada;
- receptor Jere Platform `#60`: fusionado;
- issue `jere-platform#59`: cerrado;
- issue coordinador `jere-platform#51`: abierto;
- documentación obsoleta identificada y en corrección.

### Defectos reproducibles

| ID | Área | Severidad | Estado | Corrección |
|---|---|---:|---|---|
| UX-20260721-001 | Pagos | P2 | CORREGIDO EN RAMA | se retira ID técnico de tabla y nombre accesible |
| UX-20260721-002 | Búsqueda de alumnos | P1 recorrido | CORREGIDO EN RAMA | nombre, apellido, ambos órdenes, documento y parciales |

### Pruebas agregadas

- frontend: la tabla de Pagos no muestra cabecera/celda de ID y expone acciones por fecha/monto;
- PostgreSQL: búsqueda de alumno por nombre, apellido, `nombre apellido`, `apellido nombre`, documento, fragmentos y exclusión de inactivos.

### Recorridos por rol

| Rol | Estado | Motivo |
|---|---|---|
| SUPERADMIN | PENDIENTE | falta navegador y evidencia humana completa |
| DIRECCION | PENDIENTE | falta navegación visual y denegaciones por URL |
| ADMINISTRADOR | PENDIENTE | falta recorrido funcional completo |
| SECRETARIA | PENDIENTE | búsqueda corregida; recorrido alumno-inscripción-asistencia pendiente |
| CAJA | PENDIENTE | Pagos corregido; cobro-recibo-caja-stock pendiente |

No se declara PASS por análisis estático ni por API solamente.

## 5. Matriz UX pendiente

| Área | Escritorio | 360 px | 390 px | 768 px | Teclado | Loading | Vacío | Error | IDs humanos |
|---|---|---|---|---|---|---|---|---|---|
| Login | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | N/A | pendiente | N/A |
| Alumnos | pendiente | pendiente | pendiente | pendiente | pendiente | parcial | parcial | parcial | búsqueda corregida |
| Inscripciones | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Tarifas | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Asistencia | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Cargos/pagos | pendiente | pendiente | pendiente | pendiente | pendiente | presente en Pagos | presente en Pagos | presente en Pagos | ID de pago corregido |
| Caja/egresos | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Recibos | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Stock | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Reportes | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Usuarios/roles | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |

## 6. Backlog priorizado

### P0

No se identificó un P0 abierto. Cualquier regresión de seguridad, liquidación, idempotencia, Flyway o recuperación bloquea todo.

### P1 — demo humana y UX

| ID | Tarea | Estado | Criterio de cierre |
|---|---|---|---|
| DEMO-HUM-001 | recorrido SUPERADMIN | PENDIENTE | circuito completo y evidencia |
| DEMO-HUM-002 | recorrido DIRECCION | PENDIENTE | accesos y denegaciones documentados |
| DEMO-HUM-003 | recorrido ADMINISTRADOR | PENDIENTE | operación amplia sin gobierno de roles |
| DEMO-HUM-004 | recorrido SECRETARIA | PENDIENTE | alumno, inscripción y asistencia |
| DEMO-HUM-005 | recorrido CAJA | PENDIENTE | cargos, pagos, recibos, caja y stock |
| UX-001 | eliminar IDs técnicos | PARCIAL | cero IDs como referencia comercial única |
| UX-002 | búsqueda humana | CORREGIDO EN RAMA | prueba PostgreSQL y CI verde |
| UX-003 | loading/empty/error | PENDIENTE | feedback y siguiente acción claros |
| UX-004 | pagos/caja/egresos/recibos | PARCIAL | Pagos corregido; resto pendiente |
| UX-005 | stock y reversión | PENDIENTE | movimientos y stock no negativo |
| UX-006 | asistencia | PENDIENTE | guardado/error/vacío explícitos |
| UX-007 | accesibilidad | PENDIENTE | foco, teclado, labels y contraste |
| UX-008 | móvil | PENDIENTE | 360, 390, 768 y escritorio operables |

### P1 — operación externa

| ID | Tarea | Estado | Criterio de cierre |
|---|---|---|---|
| OPS-004 | backup técnico | DONE | paquete, hashes y drill |
| OPS-005 | restore aislado | DONE | DB, V7, recibos y cleanup |
| OPS-006 | rollback backend | DONE / MAIN | ida/vuelta compatible |
| OPS-007A | observabilidad source-owned | DONE / MAIN | health, métricas, correlación y logs |
| OPS-007B | monitoreo y alertas externas | BLOCKED | scraper, storage, dashboard y responsables |
| OPS-008 | runbooks | DONE | arranque, uso y recovery |
| OPS-009 | política de backup | PENDIENTE | cifrado, destino, retención, RPO/RTO |
| OPS-010 | política de artefactos | PENDIENTE | registry, digest, firma y promoción |
| OPS-011 | gestión de secretos | PENDIENTE | secret manager y rotación |
| OPS-012 | TLS/CORS/cookies | PENDIENTE | validación en ambiente destino |
| OPS-013 | staging | BLOCKED | host, dominio, responsables y ventana |

### Bloqueos externos

| ID | Bloqueo | Impacto |
|---|---|---|
| EXT-JP-051 | coordinador `jere-platform#51` | transporte desplegado, Scalaris y requisitos productivos |
| EXT-OBS | ambiente/scraper/canales no provistos | alertas y retención reales |
| EXT-STAGING | ambiente no provisto | gates externos |
| EXT-PROD | autorización inexistente | despliegue productivo |

### P2

- retiro físico futuro de columnas legacy después de reconciliación;
- serialización estable de `PageImpl`;
- agente Mockito explícito para JDK futuros;
- retención automática de snapshots V7;
- tracing distribuido cuando exista transporte real;
- portal de familias;
- Mercado Pago;
- WhatsApp automático;
- facturación electrónica;
- multi-sede/multi-tenancy;
- reapertura de `PROFESOR` sólo con ownership demostrado.

## 7. Riesgos abiertos

- GATE-2 puede revelar P1 visuales o funcionales no detectables por CI;
- la búsqueda ampliada debe validarse en PostgreSQL y preservar paginación;
- la eliminación de IDs visibles no debe quitar trazabilidad interna de API/logs;
- no hay evidencia móvil ni accesible de los flujos críticos;
- no existe staging;
- no hay monitoreo externo, retención ni responsables;
- políticas de backup, artefactos y secretos siguen incompletas;
- la integración Jere Platform es source-only, no desplegada.

## 8. Recuperación

Los cambios de GATE-2 no modifican migraciones, infraestructura, observabilidad ni contratos de recuperación. Continúan vigentes:

- backup previo para operaciones destructivas;
- restore sobre base alternativa;
- igualdad estricta entre migraciones de imagen y base;
- rechazo de imagen V6 sobre V7;
- recuperación automática al artefacto anterior si el target queda unhealthy;
- prohibición de down migrations.

## 9. Próximos pasos exactos

1. abrir PR draft desde `agent/gate-2-ux-operativa`;
2. obtener SHA candidato y workflows requeridos;
3. inspeccionar logs de cualquier fallo;
4. mantener draft mientras haya checks pendientes o rojos;
5. revisar hilos y reviews;
6. fusionar con protección de SHA sólo si todos los gates aplicables están verdes;
7. verificar HEAD final de `main`;
8. ejecutar recorridos humanos en navegador sobre ese SHA;
9. registrar evidencia por rol, ancho, teclado, estado y denegación;
10. mantener demo comercial, staging y producción en NO-GO hasta completar sus condiciones.

## 10. Veredictos vigentes

| Superficie | Veredicto |
|---|---|
| Desarrollo local | GO condicionado a requisitos y scripts versionados |
| Validación técnica integrada | GO histórico; nuevo SHA pendiente de CI |
| Demo automatizada | GO histórico; revalidación obligatoria |
| Demo humana | NO-GO |
| Demo comercial | NO-GO |
| Staging | NO-GO / no provisto |
| Producción | NO-GO / no autorizada |
