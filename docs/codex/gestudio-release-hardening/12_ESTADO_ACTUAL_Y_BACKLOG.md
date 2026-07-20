# Estado actual, alcance y backlog maestro de Gestudio

> Estado: **CANÓNICO PARA CONTINUIDAD**  
> Fecha de corte: **2026-07-20**  
> Zona horaria: `America/Argentina/Buenos_Aires`  
> Repositorio: `JerePrograma/Gestudio`  
> Rama operativa: `main`  
> HEAD remoto revisado: `3f314ba8cc61a71bfa434a46593cd02336ec16e5`  
> Decisión global: **NO-GO para staging y producción**

Este documento reconcilia el estado real de `main` después de la integración de
RBAC, el seed de demostración, la estrategia comercial y las mejoras parciales
de UX. Sustituye las referencias de estado que todavía hablen de una rama RBAC,
un PR reemplazante pendiente o `origin/main` anterior a julio de 2026.

No sustituye:

- la estrategia comercial canónica;
- las especificaciones detalladas de cada etapa;
- la evidencia histórica de la bitácora anterior;
- una corrida real de tests, smoke, backup/restore o despliegue.

## 1. Resumen ejecutivo

| Área | Estado | Veredicto |
|---|---|---|
| Seguridad y RBAC | `INTEGRADO` | Catálogo, matrices, backend, frontend y smoke fueron validados antes de su integración. `PROFESOR` permanece inactivo. |
| Migraciones | `V1-V6 VALIDADO` | V1-V6 son la cadena productiva conocida. No deben editarse. |
| Seed demo | `INTEGRADO / EJECUCIÓN ACTUAL NO ACREDITADA` | El seed reconstruido, el validador y el lanzador persistente están en `main`; falta evidencia de corrida integral sobre el HEAD actual. |
| UX operativa | `PARCIAL` | Hay mejoras en tablas, búsquedas y pantallas, pero GATE-2 no está cerrado. |
| Liquidación por vigencia | `READY` | El bloqueo por merge RBAC terminó. La implementación aún no comenzó. |
| Estrategia comercial | `CANÓNICA` | Precios, segmentación, piloto, mensajes y métricas están documentados. |
| Demo interna | `BLOCKED` | Falta corrida reproducible y recorridos humanos completos por rol. |
| Demo comercial | `PENDING` | Depende de demo interna aprobada. |
| Staging | `PENDING / NO AUTORIZADO` | Faltan ambiente, secretos, TLS, backup/restore, monitoreo y rollback. |
| Producción | `NO-GO` | No existe evidencia suficiente ni autorización. |

### Veredicto

Gestudio ya no está en el estado inicial de hardening. El RBAC y la base de
demostración están materialmente más avanzados, y la oferta comercial está
definida. El cuello de botella cambió:

1. demostrar que el entorno demo actual funciona de punta a punta;
2. corregir la liquidación financiera para usar vigencias y snapshots;
3. cerrar la UX crítica;
4. preparar operación real con backup, restore, observabilidad y rollback.

## 2. Fuentes de autoridad

La prioridad documental y técnica es:

1. migraciones Flyway productivas V1-V6;
2. código y tests presentes en `main`;
3. este estado maestro y el checklist vigente;
4. especificaciones de etapas;
5. bitácoras históricas;
6. estrategia comercial para precios y mensajes;
7. seed manual únicamente como dataset ficticio.

Ante contradicción:

- V1-V6 prevalecen sobre scripts demo;
- backend prevalece sobre permisos o restricciones sólo visibles en frontend;
- evidencia ejecutada prevalece sobre una casilla o una afirmación documental;
- la estrategia comercial prevalece sobre precios copiados en correos o piezas;
- un commit integrado no equivale a una prueba ejecutada sobre ese commit.

## 3. Estado Git y remoto verificado

| Dato | Valor |
|---|---|
| Repositorio | `JerePrograma/Gestudio` |
| Rama por defecto | `main` |
| HEAD remoto | `3f314ba8cc61a71bfa434a46593cd02336ec16e5` |
| Último commit observado | `feat(frontend): mejora tablas y pantallas de gestion` |
| PR abiertos | Ninguno observado el 2026-07-20 |
| Issues abiertos | Ninguno observado el 2026-07-20 |
| Status checks para HEAD | Ninguno publicado por la API consultada |
| Workflow runs para HEAD | Ninguno publicado por la API consultada |
| Working tree local del usuario | No verificado desde la revisión remota |

La ausencia de status checks no es un resultado verde. Significa que la revisión
remota no encontró una ejecución asociada al HEAD actual.

## 4. Cronología consolidada

### 2026-07-10 a 2026-07-14 — baseline y RBAC

Finalizado:

- inventario de rutas, endpoints, permisos, migraciones y riesgos;
- documentación inicial del hardening;
- V6 con 32 permisos y matrices base;
- autorización backend fail-closed;
- semántica 401/403/409;
- alineación de navegación, rutas y acciones frontend;
- exclusión segura de `PROFESOR`;
- retiro de STOMP y superficie de Observaciones;
- tests backend 129/129;
- tests frontend 140/140, lint y build;
- validación integrada local;
- smoke 20/20.

La documentación histórica dejó el cierre remoto como pendiente, pero esos
cambios ya forman parte de `main`.

### 2026-07-15 — seed demo

Integrado:

- endurecimiento del seed manual;
- separación estricta entre Flyway, RBAC y datos ficticios;
- validaciones de conteos e integridad;
- controles de idempotencia y no modificación de RBAC;
- documentación de 914 filas gestionadas directamente;
- reconciliación de pagos, aplicaciones, crédito, caja y stock.

Persisten dos estados distintos:

- **implementación integrada**: sí;
- **corrida integral sobre HEAD actual registrada**: no acreditada.

### 2026-07-16 — estrategia comercial

Integrado en `docs/comercial/estrategia-comercial.md`:

- posicionamiento;
- cliente objetivo;
- propuesta diferencial;
- bandas por alumnos activos;
- implementación inicial;
- descuento anual;
- promoción de lanzamiento;
- programa piloto administrado;
- mensajes de WhatsApp y correo;
- seguimiento y objeciones;
- métricas comerciales.

Precios vigentes, cuya fuente normativa sigue siendo el documento comercial:

| Plan | Alumnos activos | Precio mensual |
|---|---:|---:|
| Estudio | 1-50 | ARS 39.900 |
| Academia | 51-150 | ARS 59.900 |
| Academia Plus | 151-300 | ARS 89.900 |
| Institución | 301 o más | Desde ARS 119.900 |

### 2026-07-16 — entorno demo persistente

Integrado:

- `scripts/demo-local.ps1`;
- acciones `Start`, `Status`, `Stop`, `Reset` y `SeedNative`;
- puertos fijos y detección de conflictos;
- credenciales solicitadas como `SecureString`;
- cookie aislada para localhost;
- ejecución doble del seed;
- validaciones de frontend, CORS, login, RBAC e integridad;
- documentación operativa en `docs/testing/demo-local.md`.

No debe confundirse la existencia del script con una corrida verde registrada.

### 2026-07-16 — UX parcial

Integrado:

- corrección de la tabla responsive para no representar `Acciones` como dato;
- regresión para impedir `undefined` en tablas;
- preservación de resultados durante búsquedas con `keepPreviousData`;
- preservación de foco en búsqueda de alumnos;
- alineación del contrato de roles y permisos;
- exigencia de API explícita en producción y HTTPS fuera de localhost.

Esto reduce deuda operativa, pero no cierra la lista completa de GATE-2.

## 5. Alcance funcional actual

### 5.1 Gestión académica

Disponible en el producto:

- alumnos e historial;
- profesores;
- disciplinas;
- salones y horarios;
- inscripciones;
- asistencias diarias y mensuales.

Pendientes relevantes:

- búsqueda exhaustiva por nombre, apellido, ambos órdenes y documento;
- recorrido móvil y teclado completo;
- revisión de estados, textos y referencias humanas;
- ownership seguro para habilitar `PROFESOR`.

### 5.2 Gestión financiera

Disponible:

- mensualidades y matrículas;
- cargos;
- pagos totales y parciales;
- aplicaciones de pago;
- movimientos de crédito;
- caja y egresos;
- anulaciones y reversiones;
- recibos y outbox de recibos;
- tarifas y condiciones económicas con vigencia;
- tabla de snapshots `cargo_liquidaciones`.

Defecto estructural abierto:

- mensualidades y matrículas todavía calculan con campos legacy;
- el servicio de snapshots existe, pero no está conectado a esos flujos;
- la UI conserva fuentes de precio paralelas.

### 5.3 Stock

Disponible:

- productos;
- movimientos;
- ventas;
- cargos asociados;
- reversiones.

Pendiente:

- validar el recorrido humano completo y que ninguna edición directa rompa el
  libro de movimientos.

### 5.4 Usuarios y seguridad

Disponible y cerrado para la primera release técnica:

- roles múltiples;
- catálogo de 32 permisos;
- matrices base;
- invalidación por `authVersion`;
- roles y usuarios inactivos sin acceso efectivo;
- separación de Dirección, Secretaría y Caja;
- `PROFESOR` no asignable;
- 401 sin autenticación;
- 403 sin permiso;
- 409 para conflictos reales;
- frontend alineado con backend;
- STOMP retirado.

Pendiente:

- sólo reabrir `PROFESOR` con ownership probado entre dos profesores.

## 6. Alcance comercial actual

Se ofrece como **programa piloto administrado**, no como SaaS empresarial con
SLA maduro.

Incluye comercialmente:

- todos los módulos disponibles;
- una sede;
- usuarios administrativos sin cargo adicional;
- cobro por alumnos con al menos una inscripción activa durante el mes;
- configuración, importación básica, capacitación y acompañamiento inicial;
- precio desde ARS 39.900 mensuales.

No se ofrece como disponible:

- Mercado Pago integrado;
- WhatsApp automático;
- facturación electrónica;
- portal de alumnos o familias;
- multi-sede real;
- reservas automáticas;
- multi-tenancy;
- alta automática de academias;
- SLA productivo.

## 7. Gates vigentes

### GATE-0 — baseline y documentación

Estado: `DONE`, con reconciliación posterior en este documento.

### GATE-1 — seguridad y RBAC

Estado: `DONE / INTEGRADO EN MAIN`.

Evidencia histórica:

- backend 129/129;
- frontend 140/140;
- lint y build;
- validación integrada;
- smoke 20/20;
- V6 y matrices exactas.

### GATE-1B — liquidación financiera

Estado: `READY_TO_START`.

Bloqueo anterior cerrado: RBAC ya está integrado en `main`.

No está cerrado porque todavía faltan:

- caracterización ejecutable;
- servicio único de resolución;
- integración de mensualidades;
- integración de matrículas;
- snapshot transaccional;
- retiro de lecturas legacy;
- matriz de regresión PostgreSQL.

### GATE-2 — UX operativa

Estado: `IN_PROGRESS PARCIAL`, sin tarea formal única activa en el repositorio.

Hecho:

- tablas responsive corregidas;
- foco y continuidad de búsqueda mejorados;
- algunos IDs técnicos retirados;
- contratos de roles alineados.

Falta:

- auditoría completa de IDs visibles;
- búsquedas humanas completas;
- estados y acciones consistentes;
- accesibilidad y teclado;
- recorridos de pagos, caja, egresos, stock y asistencia;
- validación móvil real.

### GATE-3 — componentes y contratos

Estado: `PENDING`.

No debe convertirse en refactor general. Sólo se extraen contratos exigidos por
GATE-1B y GATE-2.

### GATE-4 — demo y publicación

Estado: `PENDING / BLOCKED`.

Preparación existente:

- dataset;
- validador;
- lanzador persistente;
- estrategia comercial;
- circuito narrativo.

Falta:

- corrida completa registrada;
- demo interna por roles;
- guion cronometrado;
- capturas definitivas;
- procedimiento de recuperación ante fallo;
- operación productiva.

## 8. Backlog maestro

### Prioridad P0 — integridad y demostrabilidad

| ID | Tarea | Estado | Dependencias | Criterio de cierre |
|---|---|---|---|---|
| `DOC-RECON-001` | Reconciliar índice, checklist y estado postintegración | `DONE` al publicar este bloque | Ninguna | No quedan referencias operativas a PR RBAC pendiente |
| `DEMO-VAL-001` | Ejecutar `validate-demo-seed.ps1` sobre HEAD actual | `READY / NO_EJECUTADO` | Docker, JDK 21, PowerShell | Exit 0, segunda ejecución idéntica y cleanup completo |
| `DEMO-VAL-002` | Ejecutar Backend, Frontend, All y smoke en HEAD actual | `READY / NO_EJECUTADO` | Entorno local | Conteos y exit codes registrados |
| `DEMO-RUN-001` | Levantar demo persistente desde cero | `BLOCKED POR EVIDENCIA` | `DEMO-VAL-001/002` | `Start`, logins, RBAC e integridad verdes |
| `DEMO-RUN-002` | Completar recorrido humano por Dirección, Secretaría y Caja | `PENDING` | Demo persistente | Circuitos y denegaciones documentados |
| `E1B-001` | Caracterizar cálculo vigente y casos de borde | `READY` | `main` actualizado | Tests rojos/verdes y tabla de casos |
| `E1B-002` | Crear resolución única de liquidación | `PENDING` | `E1B-001` | Una fórmula y cero fallbacks legacy |
| `E1B-003` | Integrar mensualidades por vigencia | `PENDING` | `E1B-002` | Cargo y snapshot correctos e idempotentes |
| `E1B-004` | Integrar matrículas por vigencia | `PENDING` | `E1B-002` | Máximo efectivo entre disciplinas activas, probado |
| `E1B-005` | Garantizar cargo + snapshot atómicos | `PENDING` | `E1B-003/004` | Cero cargos sin snapshot y cero duplicados |
| `E1B-006` | Retirar cálculo y edición financiera legacy | `PENDING` | `E1B-003/005` | Cero lecturas financieras legacy |
| `E1B-007` | Cerrar regresión financiera PostgreSQL | `PENDING` | `E1B-001..006` | Suites focalizadas y completas verdes |

### Prioridad P1 — UX crítica

| ID | Tarea | Estado | Criterio de cierre |
|---|---|---|---|
| `UX-001` | Inventario final de IDs técnicos visibles | `PARTIAL` | Cero IDs en flujos comerciales |
| `UX-002` | Búsqueda humana de alumnos | `PARTIAL` | Nombre, apellido, órdenes y documento |
| `UX-003` | Tablas responsive y acciones | `PARTIAL` | PC/móvil sin duplicados ni `undefined` |
| `UX-004` | Estados loading/empty/error | `PENDING` | Feedback y siguiente acción autorizada |
| `UX-005` | Pagos, caja, recibos y egresos | `PENDING` | Referencias humanas y ARS consistente |
| `UX-006` | Stock y reversiones | `PENDING` | Sin edición que eluda movimientos |
| `UX-007` | Asistencia diaria | `PENDING` | Estados y guardado explícitos |
| `UX-008` | Accesibilidad básica | `PENDING` | Foco, labels, teclado y contraste revisados |

### Prioridad P1 — operación y release

| ID | Tarea | Estado | Criterio de cierre |
|---|---|---|---|
| `OPS-001` | Definir ambiente staging | `BLOCKED` | Host, dominio, responsables y ventana |
| `OPS-002` | Gestión de secretos | `PENDING` | Secretos fuera de repo, imagen y logs |
| `OPS-003` | TLS, CORS, cookies y URLs | `PENDING` | Configuración de ambiente verificada |
| `OPS-004` | Backup automatizado | `PENDING` | Frecuencia, retención, cifrado y destino |
| `OPS-005` | Restore aislado | `PENDING` | Restauración y smoke sobre copia |
| `OPS-006` | Rollback de aplicación | `PENDING` | Artefacto anterior y comandos exactos |
| `OPS-007` | Observabilidad mínima | `PENDING` | Health, logs, métricas y alertas |
| `OPS-008` | Runbook operativo | `PENDING` | Diagnóstico, escalamiento y abortar |

### Prioridad P2 — evolución de producto

| ID | Tarea | Estado | Condición de reapertura |
|---|---|---|---|
| `PROD-PORTAL-001` | Portal de alumnos/familias | `DEFERRED` | Release interna estable |
| `PROD-PAY-001` | Integración de cobros | `DEFERRED` | Contrato financiero cerrado |
| `PROD-WA-001` | WhatsApp/push | `DEFERRED` | Necesidad y costos confirmados |
| `PROD-MULTI-001` | Multi-sede y multi-tenancy | `DEFERRED` | Modelo institucional definido |
| `PROD-FISCAL-001` | Facturación electrónica | `DEFERRED` | Alcance fiscal y proveedor definidos |
| `PROF-OWN-001` | Habilitar rol Profesor | `DEFERRED` | Ownership backend y pruebas cruzadas |

## 9. Próxima ejecución técnica recomendada

El orden correcto es:

1. ejecutar las validaciones completas del HEAD actual;
2. registrar resultados reales en la bitácora de continuidad;
3. corregir cualquier fallo del demo antes de usarlo comercialmente;
4. iniciar `E1B-001` con tests de caracterización;
5. completar GATE-1B;
6. retomar el inventario UX con los flujos financieros ya estabilizados;
7. aprobar demo interna;
8. recién después preparar staging.

No se debe comenzar staging ni prometer operación productiva mientras el demo
interno y el restore no estén probados.

## 10. Comandos de evidencia requeridos

Desde PowerShell en la raíz del repositorio:

```powershell
git status --short --branch
git rev-parse HEAD
git fetch --prune origin
git rev-parse origin/main
git diff --check

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\codex\validate.ps1 -Scope Backend

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\codex\validate.ps1 -Scope Frontend

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\codex\validate.ps1 -Scope All

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\smoke-local.ps1

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\validate-demo-seed.ps1
```

Para la demo persistente, sólo después de los gates anteriores:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 -Action Reset

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 -Action Status
```

Cada comando debe registrar:

- fecha y hora;
- HEAD exacto;
- versión de herramientas;
- exit code;
- cantidad de tests;
- fallos y clasificación;
- recursos residuales;
- decisión resultante.

## 11. Riesgos actuales

### Bloqueantes

- no hay evidencia ejecutada del HEAD actual en el repositorio;
- demo interna no aprobada;
- liquidación financiera sigue usando precios legacy;
- staging no está definido;
- restore y rollback no fueron probados.

### Altos

- vender el piloto como SaaS maduro;
- usar el seed sobre una base no descartable;
- mantener dos fuentes de precio;
- confundir integración con validación;
- asumir que ausencia de checks significa CI verde.

### Medios

- PDFs demo sin archivo físico;
- estados y mensajes técnicos en UX;
- cobertura HTTP representativa pero no exhaustiva en el validador demo;
- puertos fijos ocupados;
- tiempo de ejecución alto en Docker frío.

### Aceptados temporalmente

- `PROFESOR` inactivo;
- Observaciones fuera de superficie;
- seed no apto para producción;
- programa piloto sin SLA;
- una instalación o base separada por cliente mientras no exista multi-tenancy.

## 12. Criterios para cambiar el veredicto

### A demo interna `GO`

Se requiere:

- suites completas verdes sobre el HEAD exacto;
- seed demo verde e idempotente;
- demo persistente reproducible;
- recorridos humanos por rol;
- circuito alumno → inscripción → cargo → pago → recibo → caja;
- ausencia de IDs técnicos y acciones rotas en ese circuito;
- evidencia en bitácora.

### A demo comercial `GO`

Además:

- guion de 10-15 minutos;
- capturas definitivas;
- mensajes alineados con la estrategia canónica;
- plan de recuperación si falla la demo;
- aprobación explícita.

### A staging `GO`

Además:

- host y dominio;
- secretos;
- TLS y CORS;
- backup y restore;
- monitoreo;
- rollback;
- autorización específica.

### A producción `GO`

Además:

- staging aprobado;
- artefacto congelado;
- ventana y responsables;
- migración y recovery revisados;
- smoke post-deploy;
- riesgos residuales aceptados;
- autorización explícita previa.

## 13. Decisión vigente

**Gestudio continúa en `NO-GO` para staging y producción.**

Está en condiciones de continuar trabajo técnico y preparar una demo interna,
pero no de afirmar disponibilidad productiva. La próxima tarea de código es
`E1B-001`; la próxima tarea de evidencia es `DEMO-VAL-001`.

<!-- GATE1B-ESTADO-2026-07-20 -->
## Estado supersedente al 20 de julio de 2026

| Gate | Estado | Evidencia |
|---|---|---|
| GATE-0 | CERRADO | baseline y documentación |
| GATE-1 | CERRADO / revalidado | RBAC, 401/403/409, backend fail-closed, frontend alineado |
| GATE-1B | CERRADO TÉCNICAMENTE | 149 backend + 142 frontend, Scope All, smoke y seed PASS |
| GATE-2 | ABIERTO | UX crítica y recorrido humano pendientes |
| Demo interna automatizada | PASS | seed doble, 5 logins, RBAC e integridad |
| Demo comercial | NO-GO | falta recorrido humano y GATE-2 |
| Staging | NO-GO | backup/restore, rollback y observabilidad pendientes |
| Producción | NO-GO | no autorizada |

Finalizado: E1B-001 a E1B-010. Pendientes P1: recorridos humanos por rol, GATE-2, backup/restore, rollback, observabilidad y staging. Pendientes P2: reconciliación para retiro físico futuro de columnas legacy, serialización estable de `PageImpl` y agente Mockito para futuros JDK.
