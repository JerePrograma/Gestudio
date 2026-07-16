# Auditoría técnica del seed integral de demostración de Gestudio

## Estado del informe

| Campo | Valor |
|---|---|
| Repositorio | `JerePrograma/Gestudio` |
| Rama auditada | `main` |
| HEAD inicial auditado | `6443dbd735befbc0f9d05e78c03ef975bdd5156d` |
| `origin/main` observado | `6443dbd735befbc0f9d05e78c03ef975bdd5156d` |
| Fecha de auditoría | 2026-07-15 |
| Última migración productiva auditada | `V6__rbac_permission_catalog_and_base_roles.sql` |
| Seed reconstruido evaluado | `scripts/gestudio_demo_seed_full.sql` |
| Validador evaluado | `scripts/validate-demo-seed.ps1` |
| Alcance actual | Revisión estática, de arquitectura y de contratos |
| Veredicto provisional | **PENDIENTE DE VALIDACIÓN INTEGRADA** |

Este documento corresponde exclusivamente al **segmento 6**. Consolida el inventario y el análisis técnico previo a ejecutar las validaciones completas del segmento 7. No constituye evidencia de que el seed haya superado compilación, suites de pruebas, smoke, ejecución integrada ni reejecución en el entorno local definitivo.

---

## 1. Objetivo y criterio de autoridad

El objetivo es disponer de un dataset comercial ficticio, coherente y reproducible para demostrar Gestudio sin convertir datos de prueba en parte de la evolución productiva del esquema.

La jerarquía de autoridad adoptada es:

1. Las migraciones Flyway productivas definen esquema, invariantes, backfills canónicos y RBAC base.
2. Las entidades JPA deben validar contra ese esquema mediante `ddl-auto=validate`.
3. Los servicios productivos son la autoridad sobre eventos derivados, sesiones, auditoría y archivos físicos.
4. El seed manual sólo carga datos sintéticos compatibles con esas autoridades.
5. El validador crea un entorno descartable, aplica Flyway, ejecuta el seed y comprueba contratos sin alterar las migraciones históricas.

La consecuencia práctica es deliberada: el seed no puede corregir el modelo productivo, redefinir permisos ni suplir comportamientos que corresponden a servicios de aplicación.

---

# 2. Baseline

## 2.1 Git

| Dato | Evidencia disponible | Estado |
|---|---|---|
| Rama | `main` | Confirmado por el repositorio remoto auditado |
| HEAD inicial | `6443dbd735befbc0f9d05e78c03ef975bdd5156d` | Confirmado |
| `origin/main` | `6443dbd735befbc0f9d05e78c03ef975bdd5156d` | Confirmado en la consulta remota |
| Working tree local | No accesible desde el conector remoto | Debe capturarse en segmento 7 |
| Diferencia local esperada | Seed reconstruido, validador, guía operativa e informe | Pendiente de corroboración con `git status` y `git diff` |
| Estado remoto del seed | El HEAD auditado todavía contiene el seed anterior defectuoso | Riesgo alto hasta reemplazo y commit |

### Observación crítica

El repositorio remoto y los archivos reconstruidos no representan todavía la misma realidad:

- en `origin/main`, `scripts/gestudio_demo_seed_full.sql` conserva el encabezado y la lógica del seed anterior;
- los archivos evaluados para esta auditoría contienen una reconstrucción posterior que separa correctamente Flyway, RBAC y datos demo;
- hasta que el segmento 7 valide el árbol local y el segmento 8 publique los cambios, no debe confundirse “archivo preparado” con “estado integrado del repositorio”.

## 2.2 Herramientas

| Herramienta | Contrato requerido o detectado | Evidencia actual | Validación pendiente |
|---|---|---|---|
| PowerShell | Windows PowerShell 5.1 o PowerShell 7 | El validador evita sintaxis exclusiva innecesaria y declara ambos modos | Parser real y versión exacta |
| Git | Git 2.x | Requerido por la guía | `git --version` |
| Java | JDK 21 con `java` y `javac` | El validador busca y comprueba ejecutables 21 | Versiones exactas del host |
| Maven | Maven Wrapper versionado | El validador usa `backend/mvnw.cmd` | Versión efectiva y `clean verify` |
| Docker | Docker Engine operativo | Requerido para el entorno efímero | `docker info` |
| Docker Compose | Compose v2 | El script usa `docker compose` | `docker compose version` |
| PostgreSQL | Imagen `postgres:15.12-alpine3.21` | Definida en `docker-compose.yml` | Arranque, health y Flyway reales |
| Node.js | Requerido por el frontend | No se ejecuta en segmento 6 | Versión exacta en segmento 7 |
| npm | Requerido por el frontend | No se ejecuta en segmento 6 | `npm ci`, lint, test y build |

## 2.3 Archivos examinados

| Archivo o fuente | Finalidad |
|---|---|
| `backend/src/main/resources/db/migration/V1__canonical_schema.sql` | Esquema canónico inicial |
| `V2__security_superadmin_sessions_audit.sql` | Seguridad, sesiones, bootstrap y auditoría |
| `V3__effective_dated_pricing.sql` | Tarifas y condiciones económicas con vigencia |
| `V4__cargo_liquidations_and_events.sql` | Liquidaciones, eventos de cargo y vista de cuotas |
| `V5__base_roles_permissions_seed.sql` | Estructura RBAC y backfill transicional |
| `V6__rbac_permission_catalog_and_base_roles.sql` | Catálogo y matrices RBAC productivas |
| Entidades JPA del backend | Mapeo objeto-relacional vigente |
| `PostgreSqlSchemaValidationTest` | Contrato de esquema, Flyway, Hibernate y RBAC |
| `CanonicalArchitectureContractTest` | Inmutabilidad de migraciones y reglas arquitectónicas |
| Seed anterior en `origin/main` | Fuente de defectos que motivó la reconstrucción |
| Seed manual reconstruido | Dataset demo propuesto |
| `validate-demo-seed.ps1` | Gate específico de integración del dataset |
| `docs/testing/demo-seed.md` | Guía operativa del segmento 5 |
| `docker-compose.yml` | Infraestructura local y efímera reutilizada |

---

# 3. Inventario Flyway

El contrato arquitectónico fija exactamente seis migraciones productivas. El seed demo no forma parte de esta secuencia.

| Versión | Archivo | Tipo | Responsabilidad | Datos canónicos | Relación con el seed |
|---:|---|---|---|---|---|
| 1 | `V1__canonical_schema.sql` | Esquema canónico | Crea el dominio académico, financiero, caja, stock, asistencias, recibos y notificaciones | Incluye roles legacy mínimos necesarios para el esquema vacío | El seed debe respetar sus FK, checks, uniques y tipos |
| 2 | `V2__security_superadmin_sessions_audit.sql` | Esquema + dato canónico mínimo | Agrega seguridad de usuario, sesiones de refresh, bootstrap y auditoría append-only | Inserta el rol técnico `SUPERADMIN` si no existe | El seed no debe fabricar sesiones, bootstrap ni auditorías |
| 3 | `V3__effective_dated_pricing.sql` | Esquema financiero | Crea tarifas por vigencia y condiciones económicas históricas de inscripción | No carga dataset operativo | El seed crea historias demo compatibles y fechadas |
| 4 | `V4__cargo_liquidations_and_events.sql` | Esquema + backfill productivo | Crea liquidaciones, eventos append-only y `v_cuotas_seguimiento`; backfillea cargos existentes | Sí, backfill conservador de datos preexistentes | El seed crea liquidaciones demo, pero no falsifica eventos derivados |
| 5 | `V5__base_roles_permissions_seed.sql` | Estructura RBAC + backfill | Extiende roles, crea permisos y tablas join, preserva `usuarios.rol_id`, invalida autenticación | Backfill de asignaciones legacy; no crea permisos ni matrices operativas | El seed sólo usa la estructura resultante |
| 6 | `V6__rbac_permission_catalog_and_base_roles.sql` | **RBAC productivo** | Define 32 permisos, seis roles base, matrices exactas e invalida sesiones afectadas | Sí: catálogo y matrices canónicas | El seed exige V6 y prohíbe modificar sus resultados |
| — | `scripts/gestudio_demo_seed_full.sql` | **Seed manual** | Carga datos ficticios transaccionales e idempotentes | No pertenece a Flyway | Se ejecuta después de Flyway en una base descartable |

## 3.1 Clasificación por autoridad

### Esquema

- V1 crea la base canónica.
- V2 agrega infraestructura de seguridad y trazabilidad.
- V3 agrega vigencias económicas.
- V4 agrega liquidación y eventos financieros.
- V5 agrega estructura RBAC.

### Datos canónicos y backfills

- V2 garantiza la existencia del rol técnico base.
- V4 reconstruye liquidaciones y eventos mínimos de cargos preexistentes.
- V5 migra el rol legacy de cada usuario a `usuario_roles`.
- V6 reconcilia el catálogo y las matrices de autorización.

### RBAC productivo

La autoridad exclusiva es V6:

- 32 permisos activos de sistema;
- `SUPERADMIN`: 32 permisos;
- `DIRECCION`: 31 permisos;
- `ADMINISTRADOR`: 31 permisos;
- `SECRETARIA`: 17 permisos;
- `CAJA`: 8 permisos;
- `PROFESOR`: inactivo, no editable y sin permisos.

### Seed manual

El seed reconstruido:

- no se llama internamente V6;
- no tiene prefijo Flyway;
- no crea ni altera tablas;
- no toca `roles`, `permisos` ni `rol_permisos`;
- no activa `PROFESOR`;
- no crea un usuario profesor;
- no incluye passwords ni hashes fijos;
- aborta si la base no coincide con el contrato productivo esperado.

## 3.2 Regla forward-only

V1 a V6 deben permanecer inmutables. Cualquier corrección de esquema o RBAC debe publicarse en una migración posterior. El seed no puede utilizarse para “arreglar” una migración histórica ni para reconciliar instalaciones divergentes.

---

# 4. Inventario del esquema relevante

El contrato PostgreSQL espera 42 tablas, incluida `flyway_schema_history`.

## 4.1 Tablas de dominio y aplicación

| Área | Tablas |
|---|---|
| Seguridad y RBAC | `roles`, `usuarios`, `permisos`, `rol_permisos`, `usuario_roles`, `refresh_sessions`, `bootstrap_ejecuciones`, `auditoria_eventos` |
| Alumnos y academia | `alumnos`, `salones`, `profesores`, `observaciones_profesores`, `disciplinas`, `disciplina_horarios`, `inscripciones` |
| Configuración económica | `bonificaciones`, `recargos`, `metodo_pagos`, `sub_conceptos`, `conceptos`, `disciplina_tarifas`, `inscripcion_condiciones_economicas` |
| Facturación | `mensualidades`, `matriculas`, `cargos`, `cargo_liquidaciones`, `cargo_eventos` |
| Cobros y caja | `pagos`, `aplicaciones_pago`, `egresos`, `movimientos_caja`, `movimientos_credito` |
| Stock | `stocks`, `ventas_stock`, `movimientos_stock` |
| Asistencias | `asistencias_mensuales`, `asistencias_alumno_mensual`, `asistencias_diarias` |
| Recibos | `recibos`, `recibos_pendientes` |
| Notificaciones | `notificaciones` |
| Infraestructura | `flyway_schema_history` |

## 4.2 Invariantes estructurales relevantes

- Los importes y porcentajes se persisten como `NUMERIC`, no como tipos de punto flotante.
- Las PK de negocio son `BIGINT`, salvo identificadores técnicos expresamente diferentes como UUID de sesiones y clave textual de bootstrap.
- Las FK usan eliminación restrictiva por defecto.
- Los `CASCADE` quedan limitados a composiciones estrictas y tablas join controladas.
- Cada FK debe contar con índice de prefijo.
- Las operaciones reversibles utilizan estado, referencias al original y claves de idempotencia.
- `auditoria_eventos` y `cargo_eventos` son append-only mediante triggers.
- Los recibos históricos y la outbox técnica tienen responsabilidades separadas.

---

# 5. Inventario JPA

Se identifican 35 entidades JPA. Algunas tablas de infraestructura e historial se consumen por SQL, JDBC, vistas o asociaciones `@JoinTable` y no poseen una entidad dedicada.

## 5.1 Entidades y relaciones

| # | Entidad | Tabla | Relaciones principales | Papel en el seed |
|---:|---|---|---|---|
| 1 | `Alumno` | `alumnos` | Referenciado por inscripciones, matrículas, cargos, pagos, créditos y ventas | 28 alumnos variados |
| 2 | `Salon` | `salones` | Uno a muchos lógico con disciplinas | 3 salones demo |
| 3 | `Profesor` | `profesores` | Usuario opcional; referenciado por disciplinas | 6 profesores sin usuario operativo |
| 4 | `ObservacionProfesor` | `observaciones_profesores` | Muchos a uno con profesor | 6 observaciones |
| 5 | `Disciplina` | `disciplinas` | Muchos a uno con salón y profesor | 6 disciplinas |
| 6 | `DisciplinaHorario` | `disciplina_horarios` | Muchos a uno con disciplina; composición | 11 horarios |
| 7 | `Inscripcion` | `inscripciones` | Muchos a uno con alumno, disciplina y bonificación opcional | 34 inscripciones |
| 8 | `Mensualidad` | `mensualidades` | Muchos a uno con inscripción; bonificación y recargo opcionales | 70 mensualidades |
| 9 | `Matricula` | `matriculas` | Muchos a uno con alumno | 26 matrículas |
| 10 | `Bonificacion` | `bonificaciones` | Referenciada por inscripciones, mensualidades y condiciones | 4 bonificaciones |
| 11 | `Recargo` | `recargos` | Referenciado por mensualidades | 3 recargos |
| 12 | `MetodoPago` | `metodo_pagos` | Referenciado por pagos, egresos y caja | 4 métodos |
| 13 | `SubConcepto` | `sub_conceptos` | Uno a muchos con conceptos | 4 subcategorías |
| 14 | `Concepto` | `conceptos` | Muchos a uno con subconcepto; origen de cargos | 8 conceptos |
| 15 | `Stock` | `stocks` | Referenciado por ventas y movimientos | 6 productos |
| 16 | `VentaStock` | `ventas_stock` | Muchos a uno con alumno y stock; origen uno a uno de cargo | 6 ventas, incluidas anulaciones |
| 17 | `Cargo` | `cargos` | Alumno; uno a uno opcional con mensualidad, matrícula y venta; concepto opcional; autorrelación de recargo | 115 cargos |
| 18 | `Pago` | `pagos` | Alumno, método y usuario; uno a muchos lógico con aplicaciones | 48 pagos |
| 19 | `AplicacionPago` | `aplicaciones_pago` | Muchos a uno con pago, cargo y usuario | 82 aplicaciones |
| 20 | `Egreso` | `egresos` | Método de pago y usuario | 7 egresos |
| 21 | `MovimientoCaja` | `movimientos_caja` | Método; pago o egreso opcional; autorrelación de reverso; usuario | 61 movimientos |
| 22 | `MovimientoCredito` | `movimientos_credito` | Alumno; cargo y pago opcionales; autorrelación de reverso; usuario | 11 movimientos |
| 23 | `MovimientoStock` | `movimientos_stock` | Stock; venta opcional; autorrelación de reverso; usuario | 14 movimientos |
| 24 | `AsistenciaMensual` | `asistencias_mensuales` | Muchos a uno con disciplina | 6 planillas |
| 25 | `AsistenciaAlumnoMensual` | `asistencias_alumno_mensual` | Inscripción y planilla mensual | 18 alumnos en planillas |
| 26 | `AsistenciaDiaria` | `asistencias_diarias` | Muchos a uno con asistencia mensual del alumno | 54 registros diarios |
| 27 | `Recibo` | `recibos` | Asociado a pago; historial documental | 48 metadatos de recibo |
| 28 | `ReciboPendiente` | `recibos_pendientes` | Asociado a pago; outbox técnica | 48 entradas pendientes |
| 29 | `Notificacion` | `notificaciones` | Asociación con usuario según el modelo | No poblada por SQL demo |
| 30 | `Usuario` | `usuarios` | Rol principal legacy y muchos a muchos con roles mediante `usuario_roles` | 5 usuarios demo |
| 31 | `Rol` | `roles` | Muchos a muchos con permisos mediante `rol_permisos` | Sólo consultado |
| 32 | `Permiso` | `permisos` | Muchos a muchos con roles | Sólo consultado |
| 33 | `RefreshSession` | `refresh_sessions` | Usuario y autorrelación de reemplazo | No poblada por SQL demo |
| 34 | `TarifaDisciplina` | `disciplina_tarifas` | Disciplina y usuario creador | 12 vigencias |
| 35 | `CondicionEconomicaInscripcion` | `inscripcion_condiciones_economicas` | Inscripción, bonificación opcional y usuario creador | 40 vigencias |

## 5.2 Tablas sin entidad JPA dedicada

| Tabla | Motivo |
|---|---|
| `flyway_schema_history` | Infraestructura administrada por Flyway |
| `bootstrap_ejecuciones` | Registro técnico consumido por bootstrap/JDBC |
| `auditoria_eventos` | Bitácora append-only; acceso especializado |
| `cargo_liquidaciones` | Snapshot financiero consultado por SQL/repositorios específicos |
| `cargo_eventos` | Event log append-only |
| `usuario_roles` | Tabla join de `Usuario.roles` |
| `rol_permisos` | Tabla join de `Rol.permisos` |

## 5.3 Compatibilidad transicional de usuario y roles

`Usuario` conserva simultáneamente:

- `rol_id`, relación many-to-one legacy obligatoria;
- `usuario_roles`, colección many-to-many efectiva.

El método de autoridades prioriza la colección de roles y utiliza `rol_id` como fallback. Por eso el seed reconstruido mantiene ambas representaciones sincronizadas y elimina asociaciones demo ajenas al rol efectivo esperado.

---

# 6. Hallazgos

## 6.1 Esquema

### Hallazgos favorables

- Existe una baseline canónica compacta y una secuencia forward-only de seis migraciones.
- Los dominios monetarios usan `NUMERIC(19,2)` y porcentajes con precisión explícita.
- Los modelos de pago, caja, crédito y stock incluyen idempotencia y reversión.
- Las tablas append-only tienen protección en base de datos.
- El contrato automatizado exige índices para FK y limita eliminaciones en cascada.

### Defecto pendiente

`asistencias_diarias.estado` fue creado como `VARCHAR(10)`, pero el check admite `JUSTIFICADO`, que requiere 11 caracteres. PostgreSQL rechaza ese valor por longitud antes de evaluar el check.

Decisión provisional:

- no modificar V1 retroactivamente;
- el seed utiliza sólo `PRESENTE` y `AUSENTE`;
- crear una migración productiva posterior para ampliar la columna antes de usar `JUSTIFICADO`.

## 6.2 JPA

### Hallazgos favorables

- Las entidades centrales reflejan el esquema canónico y usan `BigDecimal` para dinero.
- Los controladores tienen un contrato que impide devolver entidades JPA directamente.
- Hibernate está previsto en modo `validate`, no como generador del esquema.
- Las asociaciones reflejan la política restrictiva de borrado y la trazabilidad histórica.

### Riesgos residuales

- La doble representación `Usuario.rol` y `Usuario.roles` es una deuda transicional: un seed debe mantenerla consistente o puede producir autoridades inesperadas.
- Las tablas sin entidad dedicada requieren validación SQL específica; `ddl-auto=validate` no cubre por sí solo toda su semántica.
- La auditoría debe verificar en segmento 7 que el conjunto real de entidades siga siendo exactamente el inventariado.

## 6.3 RBAC

### Contrato productivo

- V6 es la única autoridad del catálogo de 32 permisos y de las matrices base.
- `SUPERADMIN` es el único rol técnico completo, activo, de sistema y no editable.
- `DIRECCION` y `ADMINISTRADOR` comparten 31 permisos y excluyen administración de roles.
- `SECRETARIA` posee 17 permisos operativos.
- `CAJA` posee 8 permisos de consulta y cobro.
- `PROFESOR` permanece diferido hasta implementar ownership seguro.

### Protección implementada por el seed reconstruido

- Precondiciones de cardinalidad y estado.
- Snapshot hash de permisos y matriz antes de insertar datos.
- Comparación exacta al final de la transacción.
- Prohibición estática de DML sobre `roles`, `permisos` y `rol_permisos`.
- Exclusión del rol `PROFESOR` de usuarios demo y de roles asignables.
- Protección byte a byte de usuarios no demo relevantes.

### Observación crítica

Comprobar sólo cantidades de permisos no bastaría: dos matrices distintas pueden tener la misma cardinalidad. El seed mejora esa defensa al comparar la huella ordenada completa antes y después. El validador debe confirmar además los códigos efectivos devueltos por los perfiles HTTP.

## 6.4 Finanzas

### Cobertura del dataset

- cargos pendientes, vencidos, parciales, pagados y anulados;
- mensualidades y matrículas de distintos períodos;
- cargo por concepto, venta de stock y recargo enlazado;
- pagos simples, distribuidos, con excedente y anulados;
- aplicaciones activas y revertidas;
- crédito generado, consumido, ajustado y revertido;
- egresos, ajustes y reversos de caja;
- liquidación histórica por cargo.

### Conciliaciones esperadas

| Métrica | Valor esperado |
|---|---:|
| Pagos registrados | 1.956.700,00 |
| Aplicaciones activas | 1.938.700,00 |
| Crédito activo originado en pagos | 18.000,00 |
| Conciliación | 1.938.700,00 + 18.000,00 = 1.956.700,00 |
| Crédito neto global | 21.000,00 |

### Controles internos

- una liquidación por cargo demo;
- importe final igual a base menos descuento más recargo;
- ninguna aplicación supera el pago ni el cargo;
- saldos no negativos;
- estado de cargo coherente con saldo;
- un único origen válido por cargo;
- reversos vinculados a una operación original;
- claves de idempotencia únicas.

### Límite deliberado

El seed inserta snapshots financieros necesarios para representar historia, pero no debe inventar `cargo_eventos`. Esos eventos pertenecen a los servicios productivos y se evaluarán cuando las operaciones HTTP reales los generen.

## 6.5 Stock

### Cobertura

- productos con y sin control de cantidad;
- ingreso inicial;
- ajuste positivo y negativo;
- venta registrada;
- venta pagada;
- venta anulada;
- movimiento inverso de restauración.

### Invariantes

- cantidad materializada no negativa;
- conciliación con el libro de movimientos;
- venta con cargo y movimiento correspondiente;
- venta anulada con reverso único;
- idempotencia por operación y reversión.

### Riesgo

El estado materializado de `stocks.cantidad_actual` y el libro deben permanecer sincronizados. La comprobación SQL es obligatoria porque Hibernate sólo valida estructura, no equivalencia contable.

## 6.6 Asistencias

### Cobertura

- seis planillas mensuales;
- dieciocho asociaciones alumno-período;
- cincuenta y cuatro asistencias diarias;
- presentes y ausentes;
- permisos diferenciados de lectura y registro.

### Limitación aceptada temporalmente

No se usa `JUSTIFICADO` por el defecto de longitud de V1. La omisión evita que el seed dependa de una corrección inexistente, pero también significa que ese caso funcional no queda demostrado todavía.

## 6.7 Recibos

### Separación correcta

- `recibos` representa metadatos históricos del documento;
- `recibos_pendientes` representa el estado técnico de procesamiento;
- el esquema evita duplicar estado técnico en la tabla histórica.

### Cobertura del seed

- 48 recibos;
- 48 entradas de outbox;
- unicidad por pago y por claves técnicas;
- distintos estados de procesamiento representables.

### Limitación

El seed no crea PDFs físicos. Una `storage_key` demo puede no resolver a un archivo y el endpoint de descarga puede devolver 404. Fabricar un PDF mediante SQL falsearía la responsabilidad del servicio de recibos.

## 6.8 Auditoría y datos derivados

El seed reconstruido captura conteos antes y después y exige no modificar:

- `refresh_sessions`;
- `bootstrap_ejecuciones`;
- `auditoria_eventos`;
- `cargo_eventos`;
- `notificaciones`.

Esta decisión es correcta porque:

- las sesiones deben nacer de autenticación real;
- el bootstrap debe registrar ejecuciones reales;
- la auditoría es append-only y debe reflejar acciones efectivas;
- los eventos de cargo deben surgir de servicios transaccionales;
- las notificaciones deben respetar deduplicación y reglas del servicio.

El validador HTTP puede generar legítimamente sesiones o auditorías después de la comprobación del SQL. Ese incremento no debe confundirse con contaminación del seed.

## 6.9 Frontend

### Hallazgos favorables

- El frontend fue alineado recientemente con rutas y acciones basadas en la matriz RBAC.
- Los DTO monetarios tienen un contrato que evita declarar dinero como `number` de TypeScript.
- El validador propone probar navegación y endpoints representativos con cinco perfiles.

### Pendientes

- El seed es una infraestructura de datos, no una prueba visual exhaustiva.
- Deben ejecutarse `npm ci`, lint, tests y build completos.
- Debe verificarse que las pantallas toleren recibos sin archivo físico y que no expongan IDs técnicos innecesarios.
- La matriz de rutas visibles debe coincidir con los permisos efectivos, no sólo con el nombre del rol.

## 6.10 Seed anterior

El seed anterior presente en el HEAD remoto auditado contiene defectos incompatibles con la arquitectura actual.

| Defecto | Evidencia conceptual | Impacto |
|---|---|---|
| Encabezado falso de V6 | Se autodenomina migración demo V6 aunque V6 ya es RBAC productivo | Colisión de autoridad e historial Flyway ambiguo |
| Autoridad Flyway incorrecta | Declara depender sólo de V1..V5 | Ignora la migración productiva vigente |
| Redefinición de RBAC | Inserta o actualiza roles, permisos y matrices | Puede otorgar privilegios distintos de producción |
| Activación inválida de `PROFESOR` | Convierte el rol diferido en operativo | Abre acceso sin ownership por profesor |
| Usuario operativo `profesor` | Crea una identidad asociada a ese rol | Expone un flujo expresamente no soportado |
| Contraseña conocida | Incluye credenciales y BCrypt fijos versionados | Riesgo de acceso predecible y reutilización accidental |
| IDs rígidos masivos | Reserva valores altos y reajusta secuencias | Aumenta acoplamiento y riesgo de colisión |
| Datos derivados falsificados | Inserta sesiones, bootstrap, auditoría, eventos y notificaciones | Destruye trazabilidad semántica |
| Fechas fijas | Dataset envejece y pierde valor demostrativo | Resultados incoherentes con el período actual |

### Conclusión sobre el seed anterior

No debe conservarse como alternativa, migración opcional ni archivo de ejemplo. Debe ser reemplazado por el seed manual reconstruido y quedar fuera de `db/migration`.

---

# 7. Decisiones de diseño

## 7.1 Conservar V6 intacta

V6 se conserva porque es una migración productiva forward-only que:

- define el catálogo cerrado de permisos;
- preserva IDs de roles existentes;
- reconcilia roles base;
- asigna matrices exactas;
- invalida sesiones potencialmente afectadas;
- contiene precondiciones para evitar conciliaciones ambiguas.

Modificarla después de haber sido publicada alteraría checksums y rompería la trazabilidad de Flyway. Cualquier cambio futuro debe ser V7 o posterior.

## 7.2 Mantener el seed fuera de Flyway

El dataset demo:

- no es necesario para ejecutar Gestudio;
- contiene transacciones ficticias;
- depende de una fecha ancla;
- necesita credenciales efímeras;
- debe poder destruirse y recrearse;
- no debe alcanzar producción por classpath.

Por eso se conserva en `scripts/` y se aplica explícitamente con `psql`.

## 7.3 Proteger RBAC

La protección usa capas complementarias:

1. comprobación estática del archivo;
2. precondiciones SQL del catálogo y matrices;
3. snapshot de roles, permisos y asociaciones;
4. comparación de hashes antes del commit;
5. pruebas HTTP de permisos positivos y denegaciones;
6. comparación posterior a la segunda ejecución.

## 7.4 Generar credenciales

El validador:

- genera cinco passwords distintas con RNG criptográfico;
- las mantiene en memoria;
- calcula BCrypt con el codificador real del backend;
- exige cinco hashes distintos y válidos;
- pasa sólo hashes a `psql`;
- redacta secretos en mensajes;
- busca filtraciones en temporales al finalizar.

No se documentan contraseñas reutilizables ni hashes fijos.

## 7.5 Garantizar idempotencia

La idempotencia no se reduce a “no fallar al ejecutar dos veces”. El contrato exige:

- claves naturales y namespace `demo-*`/`demo-seed:v1:*`;
- `UPSERT` controlado;
- fecha ancla idéntica;
- hashes idénticos entre ambas aplicaciones del mismo test;
- conteos estables;
- IDs estables;
- importes, estados y asociaciones estables;
- huellas MD5 ordenadas estables;
- RBAC idéntico antes y después.

Una segunda ejecución con otra fecha ancla se rechaza para evitar desplazar silenciosamente la historia.

## 7.6 Manejar fechas

La fecha operativa se calcula en `America/Argentina/Buenos_Aires` y deriva:

- mes actual;
- uno y dos meses anteriores;
- año operativo;
- vencimientos;
- asistencias;
- edades y fechas narrativas.

Esto mantiene vigentes los escenarios sin recurrir a `CURRENT_DATE` disperso dentro de cada inserción.

## 7.7 Conciliar importes

El seed representa libros separados pero relacionados:

- cargos y liquidaciones;
- pagos y aplicaciones;
- crédito;
- caja;
- stock y ventas.

Cada libro se valida individualmente y luego contra sus contrapartes. Las conciliaciones no se delegan a conteos superficiales.

## 7.8 No falsificar servicios productivos

La ausencia de eventos, auditorías, sesiones y PDFs físicos no es una omisión accidental: evita que SQL suplante comportamientos con semántica de aplicación. La demo debe distinguir datos históricos sintéticos de efectos realmente producidos durante el smoke.

---

# 8. Diseño y cobertura del dataset

## 8.1 Identidad narrativa

La institución ficticia es **Academia Movimiento Sur**. El modelo no posee una entidad `institucion`; el nombre se utiliza en descripciones y no justifica crear una tabla nueva.

## 8.2 Conteos esperados

| Tabla | Filas demo |
|---|---:|
| `usuarios` | 5 |
| `usuario_roles` | 5 |
| `salones` | 3 |
| `profesores` | 6 |
| `observaciones_profesores` | 6 |
| `bonificaciones` | 4 |
| `recargos` | 3 |
| `metodo_pagos` | 4 |
| `sub_conceptos` | 4 |
| `conceptos` | 8 |
| `stocks` | 6 |
| `disciplinas` | 6 |
| `disciplina_horarios` | 11 |
| `alumnos` | 28 |
| `inscripciones` | 34 |
| `disciplina_tarifas` | 12 |
| `inscripcion_condiciones_economicas` | 40 |
| `mensualidades` | 70 |
| `matriculas` | 26 |
| `asistencias_mensuales` | 6 |
| `asistencias_alumno_mensual` | 18 |
| `asistencias_diarias` | 54 |
| `ventas_stock` | 6 |
| `cargos` | 115 |
| `cargo_liquidaciones` | 115 |
| `pagos` | 48 |
| `aplicaciones_pago` | 82 |
| `egresos` | 7 |
| `movimientos_caja` | 61 |
| `movimientos_credito` | 11 |
| `movimientos_stock` | 14 |
| `recibos` | 48 |
| `recibos_pendientes` | 48 |
| **Total gestionado directamente** | **914** |

## 8.3 Módulos cubiertos

- autenticación y perfiles;
- usuarios y roles;
- alumnos;
- profesores;
- salones;
- disciplinas y horarios;
- inscripciones;
- tarifas y condiciones económicas;
- mensualidades y matrículas;
- cargos y liquidaciones;
- pagos y aplicaciones;
- crédito;
- caja y egresos;
- stock y ventas;
- asistencias;
- recibos y outbox;
- reportes;
- configuración.

## 8.4 Roles demo

| Usuario | Rol | Propósito |
|---|---|---|
| `demo-superadmin` | Rol técnico completo detectado dinámicamente | Verificación integral y recuperación técnica |
| `demo-direccion` | `DIRECCION` | Dirección operativa |
| `demo-administrador` | `ADMINISTRADOR` | Compatibilidad del rol legacy |
| `demo-secretaria` | `SECRETARIA` | Gestión académica y cobros |
| `demo-caja` | `CAJA` | Consultas y registro de cobros |

No se crea usuario `PROFESOR`.

## 8.5 Escenarios principales

### Académicos

- alumnos activos e inactivos;
- menores y adultos;
- alumnos sin inscripción;
- inscripciones activas, inactivas y finalizadas;
- una y varias disciplinas;
- profesores activos e inactivos;
- disciplinas con uno y dos días semanales;
- tarifas actuales e históricas;
- costo particular;
- descuentos porcentuales y fijos;
- cambios de condición económica;
- asistencia presente y ausente.

### Financieros

- pendiente, vencido, parcial, pagado y anulado;
- pago simple y distribuido;
- excedente y crédito;
- anulación y reversión;
- ajuste de crédito y débito;
- recargo vinculado;
- egreso y anulación;
- ajuste manual de caja.

### Stock

- producto controlado y no controlado;
- ingreso y ajustes;
- venta registrada, pagada y anulada;
- restitución de unidades.

### Seguridad

- cinco logins;
- anónimo 401;
- permitido 200;
- solicitud autorizada pero inválida 400;
- usuario autenticado sin permiso 403;
- `PROFESOR` ausente de roles asignables.

---

# 9. Cobertura de endpoints prevista por el validador

## 9.1 Comunes

| Prueba | Resultado esperado |
|---|---:|
| Health del backend | 200 |
| Perfil anónimo | 401 |
| Login de cinco usuarios | 200 |
| Perfil del usuario actual | 200 |

## 9.2 Superadministración

Se consultan endpoints representativos de:

- alumnos;
- disciplinas;
- profesores;
- inscripciones;
- mensualidades;
- cargos;
- pagos;
- caja;
- stock;
- asistencias;
- reportes;
- configuración;
- usuarios;
- roles.

Resultado esperado: 200, perfil con 32 permisos y catálogo asignable sin `PROFESOR`.

## 9.3 Dirección y administrador legacy

- administración de usuarios: 200;
- administración de roles: 403.

Esto comprueba que tener 31 permisos no equivale a superadministración completa.

## 9.4 Secretaría

Positivos:

- alumnos;
- inscripciones;
- asistencias;
- reportes;
- registro de pago con payload deliberadamente inválido, esperado 400;
- registro de asistencia inválida, esperado 400.

Negativos:

- usuarios: 403;
- roles: 403;
- egresos administrativos: 403.

## 9.5 Caja

Positivos:

- alumnos;
- pagos;
- caja;
- stock;
- configuración;
- registro de pago inválido, esperado 400.

Negativos:

- egresos administrativos;
- inscripciones;
- reportes;
- profesores.

Resultado esperado: 403.

## 9.6 Alcance real de esta cobertura

La cobertura es representativa, no exhaustiva. No sustituye una matriz completa endpoint × método × permiso ni las suites unitarias e integradas del backend y frontend.

---

# 10. Cobertura de pruebas y gates

| Gate | Implementado en el validador específico | Estado en segmento 6 |
|---|---|---|
| Parser nativo de PowerShell | Sí | Revisado estáticamente; ejecución pendiente |
| Contrato estático del seed | Sí | Revisado |
| Ausencia de DML RBAC | Sí | Revisado |
| Ausencia de credenciales fijas | Sí | Revisado |
| Build del backend con Maven Wrapper | Sí, `package -DskipTests` | Pendiente de ejecución |
| PostgreSQL aislado | Sí | Pendiente |
| Flyway desde base vacía | Sí | Pendiente |
| V6 exitosa y sin migración demo | Sí | Pendiente |
| Hibernate `ddl-auto=validate` | Sí | Pendiente |
| Aplicación del seed | Sí | Pendiente |
| Conteos exactos | Sí | Pendiente |
| Integridad financiera | Sí | Pendiente |
| Integridad de stock | Sí | Pendiente |
| RBAC inmutable | Sí | Pendiente |
| Login y perfiles | Sí | Pendiente |
| Denegaciones 401/403 | Sí | Pendiente |
| Autorización demostrada con 400 | Sí | Pendiente |
| Segunda ejecución | Sí | Pendiente |
| Comparación de IDs y hashes | Sí | Pendiente |
| Reinicio y nuevo login | Sí | Pendiente |
| Detección de secretos en temporales | Sí | Pendiente |
| Limpieza de Docker y temporales | Sí | Pendiente |
| Backend `clean verify` completo | No dentro del validador | Obligatorio en segmento 7 |
| Frontend lint, tests y build | No dentro del validador | Obligatorio en segmento 7 |
| Validador integrado `Scope All` | Externo | Obligatorio en segmento 7 |
| Smoke canónico | Externo | Obligatorio en segmento 7 |
| SQL de auditoría existentes | Externo | Obligatorio en segmento 7 |

---

# 11. Evaluación del validador PowerShell

## 11.1 Fortalezas

- Proyecto Compose con nombre aleatorio y recursos aislados.
- Base, usuario, password, JWT y puertos aleatorios.
- Deadline global y comprobaciones de disponibilidad.
- Inicio del backend real con Flyway y Hibernate validate.
- Generación de BCrypt mediante código del backend.
- Redacción de secretos centralizada.
- SQL con `ON_ERROR_STOP`.
- Snapshot JSON amplio con conteos, IDs y hashes ordenados.
- Detención del backend antes de la segunda aplicación.
- Limpieza en `finally` de proceso, contenedores, red, volúmenes, temporales y entorno.

## 11.2 Límites y observaciones

1. El build interno usa `-DskipTests package`; no acredita la suite backend.
2. El patrón estático de DML RBAC se enfoca en nombres `public.*`; la comparación SQL de hashes compensa parcialmente esa limitación.
3. Los hashes BCrypt se pasan como argumentos de proceso a Docker/psql. No son passwords, pero podrían ser visibles transitoriamente a otros administradores del host.
4. La selección de un puerto libre y su uso posterior tienen una ventana de carrera pequeña.
5. El timeout de 35 minutos puede ser insuficiente en una primera ejecución con imágenes y dependencias frías.
6. La búsqueda de secretos se concentra en el directorio temporal del proyecto; no audita el historial completo del daemon ni herramientas externas.
7. Los tests HTTP son representativos y deben complementarse con las suites existentes.

Ninguno de estos puntos autoriza a debilitar el gate. Deben documentarse y, cuando corresponda, corregirse sólo si se manifiestan durante la ejecución real.

---

# 12. Riesgos clasificados

## 12.1 BLOQUEANTE

| Riesgo | Motivo | Condición de cierre |
|---|---|---|
| Validación integrada aún no ejecutada | No hay evidencia real de parser, compilación, Flyway, SQL, HTTP, reejecución y cleanup en el entorno definitivo | Completar segmento 7 sin fallos |
| Suites completas no ejecutadas | El validador específico compila con tests omitidos y no cubre frontend | Backend `clean verify`, frontend completo, `Scope All` y smoke verdes |

## 12.2 ALTO

| Riesgo | Motivo | Mitigación |
|---|---|---|
| `origin/main` todavía contiene el seed anterior | El archivo remoto redefine RBAC y contiene credenciales conocidas | Reemplazarlo, revisar diff, validar y publicar sin conservar una alternativa insegura |
| Divergencia entre archivos preparados y repositorio | La auditoría analiza artefactos nuevos no confirmados todavía en el working tree remoto | Capturar Git real y verificar contenido exacto en segmento 7/8 |
| Ejecución accidental en una base no descartable | El SQL crea cientos de movimientos financieros ficticios | Entorno aislado, nombre aleatorio, advertencias y eliminación de base completa |

## 12.3 MEDIO

| Riesgo | Motivo | Mitigación |
|---|---|---|
| `JUSTIFICADO` no cabe en `VARCHAR(10)` | Defecto productivo de V1 | No usarlo en el seed; crear migración posterior |
| Recibos sin PDF físico | Metadatos demo pueden apuntar a un archivo inexistente | Tratar 404 como limitación documentada o generar archivos mediante servicio real |
| Eventos y auditoría ausentes en datos iniciales | El seed no falsifica tablas derivadas | Generar evidencia mediante operaciones reales durante validación |
| Timeout global fijo | Entornos Windows/Docker fríos pueden superar 35 minutos | Precalentar dependencias o ajustar sólo con evidencia, sin ocultar fallos |
| Cobertura HTTP no exhaustiva | Puede quedar un endpoint con anotación incorrecta | Suites focalizadas y matriz RBAC complementaria |

## 12.4 BAJO

| Riesgo | Motivo | Mitigación |
|---|---|---|
| Carrera en asignación de puertos | Un proceso externo podría ocuparlos antes del bind | Reintento controlado si aparece |
| Hashes BCrypt visibles en argumentos de proceso | Administradores locales podrían inspeccionarlos | Host de confianza; hashes efímeros; nunca passwords |
| Regex estática limitada a DML cualificado | Una variante sintáctica podría eludirla | Snapshot SQL completo y revisión manual |
| Fecha ancla extrema | Fechas derivadas podrían rozar límites | Rango validado y uso real cercano al presente |

## 12.5 ACEPTADO

| Riesgo o limitación | Justificación |
|---|---|
| `PROFESOR` no operativo | Falta ownership seguro; activarlo sería peor que omitirlo |
| Profesores demo sin usuario | Coherente con el estado productivo del rol |
| No crear archivos PDF por SQL | El almacenamiento físico pertenece al servicio |
| No poblar tablas append-only derivadas | Preserva semántica y trazabilidad |
| Reejecución sólo con misma fecha y hashes | Garantiza determinismo; otra fecha requiere otra base |
| Limpieza mediante eliminación de base/volumen | Es más segura que borrar selectivamente historia y relaciones |
| Dataset no apto para producción | Es una restricción esencial, no una capacidad pendiente |

---

# 13. Criterios de aceptación para avanzar

El segmento 7 deberá demostrar, con resultados y exit codes reales:

1. parser PowerShell sin errores;
2. `git diff --check` limpio;
3. backend `clean verify` completo;
4. pruebas focalizadas de Flyway, esquema, RBAC, bootstrap, tarifas, condiciones, cargos, pagos, créditos, stock, recibos y auditoría;
5. frontend con instalación reproducible, lint, tests y build;
6. validador integrado `Scope All` verde;
7. smoke canónico verde e independiente del seed;
8. validador específico del demo seed verde;
9. aplicación de las seis migraciones desde PostgreSQL vacío;
10. V6 productiva intacta;
11. ninguna migración demo en el classpath;
12. Hibernate validate exitoso;
13. cinco logins válidos;
14. 401, 403, 400 y 200 según contrato;
15. 914 filas gestionadas directamente y conteos exactos;
16. conciliaciones financieras y de stock sin inconsistencias;
17. segunda ejecución idéntica;
18. RBAC sin cambios;
19. ausencia de secretos en artefactos y temporales;
20. ausencia de recursos Docker residuales.

Si cualquiera falla, el seed no puede declararse utilizable hasta corregir la causa y repetir la suite completa afectada.

---

# 14. Veredicto provisional

## **PENDIENTE DE VALIDACIÓN INTEGRADA**

### Fundamento

La reconstrucción propuesta corrige conceptualmente los defectos graves del seed anterior y presenta controles sólidos de aislamiento, seguridad, idempotencia, RBAC e integridad contable. Sin embargo:

- el repositorio remoto auditado todavía contiene la versión anterior;
- no se ha ejecutado en este segmento la validación completa;
- no hay resultados reales de backend, frontend, smoke, Flyway, HTTP ni reejecución;
- las limitaciones de esquema y recibos siguen abiertas o aceptadas explícitamente.

No corresponde usar todavía ninguno de los veredictos finales de utilización. El estado sólo podrá cambiar después de completar el segmento 7 con evidencia reproducible.

---

# 15. Próximo paso obligatorio

Ejecutar exclusivamente el **segmento 7 — Validaciones completas y correcciones**. No comenzar commit ni push mientras exista un gate fallido o evidencia incompleta.
