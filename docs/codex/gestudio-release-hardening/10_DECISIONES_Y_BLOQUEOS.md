# Decisiones y bloqueos vigentes

> Fecha de corte: 20 de julio de 2026  
> Rama operativa: `main`  
> Estado global: **NO-GO para demo comercial, staging y producción**

Una implementación integrada, una prueba ejecutada y una autorización de despliegue son estados distintos. Este documento contiene sólo decisiones vigentes; la secuencia histórica se conserva en las bitácoras.

## Decisiones técnicas

### DEC-RBAC-001 — Seguridad fail-closed

- catálogo exacto de 32 permisos;
- `SUPERADMIN`, `DIRECCION`, `ADMINISTRADOR`, `SECRETARIA` y `CAJA`;
- `PROFESOR` inactivo, sin permisos y no asignable;
- backend como autoridad;
- rutas no inventariadas denegadas;
- 401 sin autenticación, 403 sin permiso, 409 para conflictos reales;
- frontend condicionado por permisos efectivos;
- STOMP retirado.

Estado: **INTEGRADA Y VALIDADA**.

### DEC-DB-001 — Flyway forward-only

- V1-V7 son inmutables;
- V6 conserva catálogo y matrices RBAC;
- V7 conserva snapshots/páginas del emisor firmado;
- no se edita una migración aplicada;
- no se ejecutan down migrations;
- una corrección futura requiere V8 o superior;
- el seed demo no es una migración;
- rollback de código debe conservar todas las migraciones ya aplicadas.

Estado: **INTEGRADA Y VALIDADA**.

### DEC-FIN-001 — Liquidación por vigencia

| Tema | Contrato vigente |
|---|---|
| Fecha mensual | primer día del `YearMonth` |
| Fecha matrícula | 1 de enero |
| Tarifa | última `vigenteDesde <= fechaEfectiva`; obligatoria |
| Condición | opcional; última efectiva |
| Precio | costo particular efectivo no nulo; si no, tarifa histórica |
| Descuento | snapshots porcentual/fijo, escala monetaria 2, `HALF_UP` |
| Resultado negativo | abortar y revertir |
| Fórmula | versión 1 |
| Matrícula multidisciplina | mayor importe final; empate por menor inscripción |
| Recargo | cargo tardío separado |
| Legacy | compatible físicamente, fuera de cálculo y edición operativa |

Cargo y snapshot se persisten en la misma transacción. Un cargo existente sin snapshot es inconsistencia y no se reconstruye con configuración actual.

Estado: **INTEGRADA Y VALIDADA**.

### DEC-DEMO-001 — Demo sintética y separada

- seed únicamente sobre base descartable o expresamente demo;
- cinco usuarios con claves solicitadas en cada `Start`/`Reset`;
- ejecución doble idempotente;
- demo persistente separada de los gates descartables;
- no usar datos reales;
- demo automatizada PASS no equivale a demo humana aprobada.

Estado: **AUTOMATIZADA Y VALIDADA; RECORRIDO HUMANO PENDIENTE**.

### DEC-JP-001 — Emisor source-owned V7

- Gestudio conserva propiedad del perfil de estudiante;
- exporta sólo ID, nombre de visualización y activo;
- mapping deployment/academia → tenant UUID explícito;
- secreto HMAC independiente y externo;
- snapshots/páginas inmutables;
- permiso doble administrativo;
- feature deshabilitada por defecto;
- sin push, scheduler, broker, UI ni Scalaris;
- no declarar end-to-end operativo hasta cerrar `JerePrograma/jere-platform#59`.

Estado: **CAPACIDAD INTEGRADA; OPERACIÓN EXTERNA BLOQUEADA**.

### DEC-BACKUP-001 — Punto consistente de backup

- `pg_dump` custom es la copia de PostgreSQL;
- los recibos se incluyen en archivo separado;
- cuando se incluyen recibos, el backend debe detenerse para obtener consistencia de aplicación;
- backup sólo DB puede ejecutarse con backend activo y se marca sin archivo de recibos;
- paquete incompleto se elimina;
- manifiesto registra HEAD, Flyway, tamaños y SHA-256;
- paquetes reales se almacenan fuera de Git y del host de aplicación.

Estado: **IMPLEMENTADA Y VALIDADA TÉCNICAMENTE**.

### DEC-RESTORE-001 — Restaurar primero a base alternativa

- restore destructivo requiere confirmación explícita;
- bases reservadas y nombres inseguros se rechazan;
- sobrescribir la base origen se rechaza por defecto;
- el procedimiento recomendado restaura primero en una base distinta;
- tamaños y hashes se validan antes de destruir destino;
- Flyway se verifica después de `pg_restore`;
- recibos requieren confirmación independiente y backend detenido;
- base y archivos no forman una transacción distribuida.

Estado: **IMPLEMENTADA Y VALIDADA TÉCNICAMENTE**.

### DEC-ROLLBACK-001 — Rollback compatible con esquema aplicado

- no usar una imagen que no contenga las migraciones ya registradas;
- no borrar V7 ni su historial;
- desactivar el emisor mediante feature flag es la primera respuesta operacional;
- un artefacto de rollback debe incluir V1-V7 aunque revierta código funcional;
- el drill debe volver después al artefacto actual y demostrar datos/Flyway intactos.

Estado: **TOMADA; DRILL PENDIENTE**.

### DEC-RELEASE-001 — Autorizaciones separadas

| Salida | Estado |
|---|---|
| Desarrollo y validación local | GO |
| Demo automatizada | PASS |
| Demo humana | pendiente |
| Demo comercial | NO-GO |
| Staging | NO-GO |
| Producción | NO-GO |

Ningún commit, merge, build, smoke o restore cambia por sí solo una autorización externa.

## Decisiones diferidas

- `PROFESOR`: sólo reabrir con ownership backend y prueba cruzada entre dos profesores.
- Observaciones de profesores: conservar historia, sin superficie ni permisos activos.
- Portal de alumnos/familias: fuera de primera release.
- Mercado Pago y facturación electrónica: diferidos.
- WhatsApp automático: diferido.
- Multi-sede y multi-tenancy: diferidos.
- Transporte automático a Jere Platform: diferido hasta contrato receptor y autorización.

## Bloqueos cerrados

| ID | Bloqueo | Evidencia de cierre |
|---|---|---|
| BLK-RBAC | matriz y autorización | GATE-1 integrado y revalidado |
| BLK-FIN | doble fuente financiera | GATE-1B integrado; fuentes legacy fuera de operación |
| BLK-DEMO-AUTO | falta de evidencia automatizada | smoke y seed doble PASS |
| BLK-V7-SCHEMA | gates todavía esperaban V6 | smoke/seed reconciliados y V1-V7 PASS |
| BLK-BACKUP | backup no implementado | dump, recibos, manifiesto y hashes probados |
| BLK-RESTORE | restore no ensayado | base alternativa, V7, datos y recibo recuperados |

## Bloqueos abiertos

### BLK-JP-059 — Receptor multipágina externo

Dependencia: `JerePrograma/jere-platform#59`.

Impacto: impide declarar operativa la reconciliación end-to-end. No bloquea el emisor local deshabilitado.

### BLK-ROLLBACK — Artefacto anterior compatible

Falta demostrar:

- artefacto rollback con V1-V7;
- cambio de imagen sin down migration;
- backend healthy;
- datos y Flyway preservados;
- retorno al artefacto actual.

Bloquea staging y producción.

### BLK-OBS — Observabilidad

Faltan:

- health de aplicación y dependencias;
- métricas mínimas;
- logs sanitizados y correlacionados;
- alertas;
- runbook de incidentes y escalamiento.

Bloquea staging y producción.

### BLK-UX — Recorrido humano y GATE-2

Faltan:

- IDs técnicos visibles;
- búsquedas humanas exhaustivas;
- estados loading/empty/error;
- pagos, caja, egresos, recibos, stock y asistencia;
- foco, teclado, labels, contraste y móvil;
- recorridos de los cinco roles.

Bloquea demo comercial.

### BLK-OPS-POLICY — Política real de recuperación

Aunque el drill técnico está verde, faltan:

- destino externo cifrado;
- frecuencia y retención;
- RPO y RTO;
- responsables;
- prueba periódica;
- gestión y rotación de secretos.

Bloquea staging y producción.

### BLK-ENV — Ambiente externo

Faltan host, dominio, TLS, CORS, cookies, secret manager, responsables, ventana y autorización.

Bloquea staging y producción.

## Próximas acciones obligatorias

1. integrar documentación y evidencia de backup/restore;
2. ejecutar rollback forward-compatible;
3. cerrar observabilidad mínima;
4. completar GATE-2 y recorridos humanos;
5. definir política operativa y secretos;
6. disponer staging;
7. repetir todos los gates en staging;
8. mantener producción en NO-GO hasta decisión independiente.
