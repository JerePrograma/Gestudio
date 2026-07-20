# Seed integral de demostración de Gestudio

## Estado del documento

| Campo | Valor |
|---|---|
| Repositorio | `JerePrograma/Gestudio` |
| Rama auditada | `main` |
| HEAD auditado | `6443dbd735befbc0f9d05e78c03ef975bdd5156d` |
| Fecha de auditoría | 2026-07-15 |
| Seed manual | `scripts/gestudio_demo_seed_full.sql` |
| Validador integral | `scripts/validate-demo-seed.ps1` |
| Última versión Flyway auditada | `7` |
| Migración productiva más reciente auditada | `V7__jere_platform_student_source_exports.sql` |
| Estado | Seed reconstruido y validación automatizada disponible |

Este documento describe el mecanismo soportado para construir y validar un dataset comercial ficticio de Gestudio sobre una base PostgreSQL descartable.

La migración `V6__rbac_permission_catalog_and_base_roles.sql` **no es un seed de demostración**. Es una migración productiva forward-only que define el catálogo RBAC y las matrices de los roles base. El seed manual exige que V6 haya sido aplicada correctamente, pero no la sustituye, no la copia y no modifica sus datos.

---

## 1. Propósito

El seed crea una academia ficticia suficientemente completa para demostrar:

- usuarios, roles y permisos;
- alumnos activos e inactivos;
- profesores, salones, disciplinas y horarios;
- inscripciones activas, inactivas y finalizadas;
- tarifas y condiciones económicas con vigencia;
- mensualidades y matrículas;
- cargos pendientes, parciales, pagados y anulados;
- pagos simples, pagos distribuidos y anulaciones;
- crédito generado, consumido, ajustado y revertido;
- caja, egresos y reversos;
- stock, ventas y reversión de ventas;
- asistencias mensuales y diarias;
- recibos y outbox de recibos;
- reportes y permisos diferenciados por rol.

La identidad narrativa utilizada es **Academia Movimiento Sur**. El esquema actual no posee una entidad `institucion`, por lo que ese nombre sólo aparece en descripciones y datos ficticios; no se crea una tabla nueva.

---

## 2. Separación obligatoria entre Flyway y datos demo

### Flyway productivo

Ubicación:

```text
backend/src/main/resources/db/migration
```

Responsabilidades:

- crear y evolucionar el esquema;
- realizar backfills productivos necesarios;
- definir catálogos obligatorios;
- definir el RBAC productivo;
- conservar un historial forward-only.

### Seed manual

Ubicación:

```text
scripts/gestudio_demo_seed_full.sql
```

Responsabilidades:

- cargar datos sintéticos de demostración;
- reutilizar roles y permisos existentes;
- validar integridad del dataset;
- poder reejecutarse de forma controlada;
- permanecer fuera del classpath de migraciones.

El archivo manual:

- no tiene prefijo `V`;
- no debe renombrarse como migración;
- no debe copiarse a `db/migration`;
- no crea ni altera tablas;
- no inserta, actualiza o elimina roles;
- no inserta, actualiza o elimina permisos;
- no modifica `rol_permisos`;
- no activa el rol `PROFESOR`;
- no contiene contraseñas en texto plano;
- no debe ejecutarse en producción.

---

## 3. Prerrequisitos

### Herramientas

- Windows PowerShell 5.1 o PowerShell 7.
- Git 2.x.
- JDK 21 completo, con `java` y `javac`.
- Docker Desktop con Engine iniciado.
- Docker Compose v2.
- Maven Wrapper versionado en el backend.

El flujo automatizado no necesita Maven, PostgreSQL ni `psql` instalados globalmente. Usa Maven Wrapper, el contenedor PostgreSQL del proyecto y el cliente `psql` incluido en ese contenedor.

### Estado del repositorio

Antes de ejecutar:

```powershell
Set-Location C:\laburo\Gestudio

git status --short --branch
git branch --show-current
git rev-parse HEAD
git diff --exit-code
git diff --cached --exit-code
```

La guía fue preparada contra:

```text
6443dbd735befbc0f9d05e78c03ef975bdd5156d
```

Si el HEAD es posterior, debe verificarse que:

- `scripts/gestudio_demo_seed_full.sql` siga siendo compatible;
- la última migración productiva continúe incluyendo V7;
- no exista una migración Flyway de demostración;
- las entidades y endpoints utilizados por el validador no hayan cambiado.

### Docker

Comprobar:

```powershell
docker info
docker compose version
```

### Java

Comprobar:

```powershell
java -version
javac -version
```

Ambos deben resolver un JDK 21. El validador también busca instalaciones conocidas de JDK 21 y configura `JAVA_HOME` sólo dentro de su proceso.

---

## 4. Ejecución recomendada

Desde la raíz del repositorio:

### Windows PowerShell 5.1

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-demo-seed.ps1
```

### PowerShell 7

```powershell
pwsh -NoProfile -File .\scripts\validate-demo-seed.ps1
```

El script:

1. valida su propia sintaxis;
2. valida estáticamente el contrato del seed;
3. compila el backend;
4. crea un proyecto Compose aislado;
5. asigna puertos aleatorios;
6. crea PostgreSQL con credenciales aleatorias;
7. inicia el backend real;
8. deja que Flyway aplique las migraciones;
9. exige V7 exitosa, V6 presente y ninguna migración demo;
10. ejecuta Hibernate con `ddl-auto=validate`;
11. genera cinco passwords aleatorias en memoria;
12. genera cinco hashes BCrypt con el codificador real del backend;
13. aplica el seed;
14. valida conteos, RBAC e integridad financiera;
15. arranca el backend sobre el dataset;
16. prueba login, perfiles, endpoints y denegaciones;
17. detiene el backend;
18. aplica el seed por segunda vez;
19. compara conteos, IDs, hashes y saldos;
20. reinicia el backend y repite el login;
21. elimina temporales, contenedores, red y volúmenes.

### Reutilizar un JAR existente

Sólo cuando ya exista un JAR actualizado en `backend/target`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\validate-demo-seed.ps1 `
  -SkipBackendBuild
```

El script falla si se usa `-SkipBackendBuild` y no encuentra un JAR utilizable.

### Mostrar solicitudes HTTP

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\validate-demo-seed.ps1 `
  -VerboseHttp
```

Este modo muestra método, ruta y código HTTP. Los secretos continúan redactados.

### Combinación

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\validate-demo-seed.ps1 `
  -SkipBackendBuild `
  -VerboseHttp
```

---

## 5. Aislamiento y limpieza del validador

Cada ejecución crea un nombre de proyecto semejante a:

```text
gestudio-demo-seed-<PID>-<sufijo aleatorio>
```

También genera:

- base PostgreSQL con nombre aleatorio;
- usuario PostgreSQL aleatorio;
- password PostgreSQL aleatoria;
- secreto JWT aleatorio;
- puerto PostgreSQL aleatorio;
- puerto backend aleatorio;
- directorio temporal aislado;
- directorio temporal de recibos.

El bloque `finally` intenta siempre:

- detener el backend Java;
- ejecutar `docker compose down --volumes --remove-orphans` sobre el proyecto aislado;
- eliminar contenedores residuales con las etiquetas del proyecto;
- eliminar la red aislada;
- eliminar los volúmenes aislados;
- eliminar el directorio temporal;
- restaurar las variables de entorno del proceso.

El script no usa la base local por defecto ni elimina volúmenes de otros proyectos Compose.

Ante una interrupción abrupta del proceso, buscar recursos residuales antes de eliminarlos:

```powershell
docker ps -a --filter "name=gestudio-demo-seed-"
docker volume ls --filter "name=gestudio-demo-seed-"
docker network ls --filter "name=gestudio-demo-seed-"
```

Eliminar únicamente el proyecto aislado exacto que se haya identificado:

```powershell
docker compose -p <nombre-exacto-del-proyecto> down --volumes --remove-orphans
```

No ejecutar `docker volume prune` ni comandos globales de limpieza como sustituto.

---

## 6. Credenciales demo

### Usuarios creados

| Usuario | Rol efectivo | Propósito |
|---|---|---|
| `demo-superadmin` | Rol técnico completo detectado desde el catálogo productivo | Recuperación y validaciones técnicas |
| `demo-direccion` | `DIRECCION` | Gestión de dirección |
| `demo-administrador` | `ADMINISTRADOR` | Compatibilidad con el rol legacy |
| `demo-secretaria` | `SECRETARIA` | Administración académica y cobros |
| `demo-caja` | `CAJA` | Cobros y consultas operativas |

No se crea un usuario con rol `PROFESOR`.

### Generación segura

El validador genera una password distinta para cada usuario mediante un generador criptográfico.

Las passwords:

- sólo existen en memoria;
- no se imprimen;
- no se guardan en `.env`;
- no se escriben en el SQL;
- no se guardan en los logs;
- se eliminan de las estructuras en memoria al finalizar.

Los hashes:

- son BCrypt;
- usan el `BCryptPasswordEncoder` del backend;
- usan el strength configurado para la aplicación;
- se envían al seed como variables `psql`;
- se redactan en cualquier diagnóstico.

El validador comprueba al finalizar que passwords, hashes, tokens y secretos no hayan quedado en archivos temporales.

### Uso humano de una demo persistente

El validador integral es un gate automatizado y destruye su entorno al terminar. No está diseñado para dejar una instancia comercial persistente ni para revelar las passwords generadas.

Para preparar una demo persistente:

1. crear una base PostgreSQL exclusivamente descartable;
2. elegir cinco passwords aleatorias y almacenarlas en un gestor de secretos;
3. generar sus hashes con el mismo `BCryptPasswordEncoder` del backend;
4. conservar las passwords sólo en el gestor de secretos;
5. pasar únicamente los hashes al seed;
6. eliminar la base completa al terminar la demostración.

No usar generadores BCrypt públicos en línea.

---

## 7. Aplicación manual avanzada

La aplicación directa del SQL es secundaria. El método soportado para validar el resultado continúa siendo `validate-demo-seed.ps1`.

### Variables obligatorias

```text
demo_anchor_date
demo_superadmin_password_hash
demo_direccion_password_hash
demo_administrador_password_hash
demo_secretaria_password_hash
demo_caja_password_hash
```

`demo_anchor_date` debe tener formato:

```text
YYYY-MM-DD
```

Ejemplo de estructura del comando, usando valores ya generados de forma segura:

```powershell
psql "host=127.0.0.1 port=<puerto> dbname=<base-demo> user=<usuario-demo>" `
  -v ON_ERROR_STOP=1 `
  -v "demo_anchor_date=<YYYY-MM-DD>" `
  -v "demo_superadmin_password_hash=<bcrypt>" `
  -v "demo_direccion_password_hash=<bcrypt>" `
  -v "demo_administrador_password_hash=<bcrypt>" `
  -v "demo_secretaria_password_hash=<bcrypt>" `
  -v "demo_caja_password_hash=<bcrypt>" `
  -f .\scripts\gestudio_demo_seed_full.sql
```

El comando recibe hashes, nunca passwords en texto plano.

### Condiciones previas obligatorias

La base debe:

- ser descartable;
- tener todas las migraciones productivas aplicadas;
- incluir `V6__rbac_permission_catalog_and_base_roles.sql` con `success=true`;
- no contener migraciones Flyway demo;
- no tener migraciones fallidas;
- conservar 32 permisos activos de sistema;
- conservar las matrices productivas exactas;
- conservar `PROFESOR` inactivo, de sistema, no editable y sin permisos.

### Transacción

El seed usa:

```sql
BEGIN;
...
COMMIT;
```

También usa:

```text
\set ON_ERROR_STOP on
```

Una validación fallida aborta la ejecución y evita un commit parcial.

---

## 8. Fecha ancla y períodos relativos

La fecha ancla se calcula en:

```text
America/Argentina/Buenos_Aires
```

A partir de ella se construyen:

- período actual;
- período anterior;
- segundo período anterior;
- vencimientos;
- fechas de asistencia;
- edades y cumpleaños ficticios;
- fechas de pagos, ventas, egresos y reversos.

Esto evita que el dataset quede obsoleto por tener fechas fijas antiguas.

### Regla de reejecución

Para una reejecución determinista deben reutilizarse:

- la misma `demo_anchor_date`;
- los mismos cinco hashes BCrypt.

El seed rechaza una fecha ancla diferente cuando ya existe el namespace demo. No desplaza datos históricos ni acumula períodos silenciosamente.

Usar hashes distintos actualiza credenciales y deja de ser una comparación byte a byte del mismo dataset. El validador conserva los hashes entre la primera y segunda aplicación.

---

## 9. Namespace demo

Los datos se reconocen mediante claves naturales reservadas:

| Tipo | Convención |
|---|---|
| Usuarios | `demo-*` |
| Correos | `*@correo.local` |
| Alumnos | padrón exacto definido en `_demo_students_desired` |
| Catálogos visibles | nombres operativos exactos, sin prefijos técnicos |
| Códigos de stock | EAN ficticios `7790000000012` a `7790000000067` |
| Idempotencia | `demo-seed:v1:*` |
| Storage keys | `demo/recibos/*` |

Los nombres, teléfonos, documentos y correos son completamente ficticios, pero
mantienen un formato operativo realista. El seed no utiliza IDs rígidos como
identidad del dataset y no mueve secuencias a rangos artificiales.

---

## 10. Escenarios incluidos

### Académicos

- alumnos menores y adultos;
- alumnos activos e inactivos;
- alumnos sin inscripción;
- inscripciones activas, inactivas y finalizadas;
- alumnos en una y varias disciplinas;
- profesores activos e inactivos;
- disciplinas con uno y dos días semanales;
- tarifas históricas y actuales;
- costo particular;
- descuentos porcentuales y fijos;
- historial de cambios en condiciones económicas;
- mensualidades de varios períodos;
- matrículas del año operativo;
- planillas de asistencia por disciplina;
- presentes y ausentes.

### Financieros

- cargo pendiente;
- cargo vencido;
- cargo parcialmente pagado;
- cargo completamente pagado;
- cargo anulado;
- pago aplicado a un cargo;
- pago distribuido entre varios cargos;
- pago anulado con aplicaciones revertidas;
- pago con excedente y generación de crédito;
- consumo de crédito;
- reversión de consumo;
- ajuste de crédito;
- ajuste de débito;
- recargo vinculado a otro cargo;
- egreso registrado;
- egreso anulado;
- ajustes manuales de caja;
- conciliación de movimientos de caja.

### Stock

- producto con control de stock;
- producto sin control de stock;
- ingreso de stock;
- ajuste positivo;
- ajuste negativo;
- venta pendiente;
- venta pagada;
- venta anulada y revertida;
- restauración del stock después de una reversión.

### Seguridad

- login de cinco roles;
- usuario anónimo rechazado con 401;
- acceso permitido según rol;
- acceso autenticado sin permiso rechazado con 403;
- `PROFESOR` fuera de roles asignables;
- catálogo RBAC sin modificaciones;
- matrices RBAC sin modificaciones.

---

## 11. Tablas pobladas directamente por el seed

| Tabla | Filas demo esperadas |
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

Los conteos se validan dentro de la misma transacción del seed.

---

## 12. Tablas consultadas pero no modificadas

El seed consulta las siguientes fuentes de verdad productivas:

```text
flyway_schema_history
roles
permisos
rol_permisos
```

Las utiliza para:

- verificar que el esquema es compatible;
- encontrar los roles existentes;
- resolver el rol técnico completo sin duplicarlo;
- comprobar el catálogo de 32 permisos;
- capturar y comparar las matrices RBAC.

El seed no ejecuta `INSERT`, `UPDATE` ni `DELETE` sobre esas tablas.

---

## 13. Tablas derivadas no pobladas por el seed

El seed captura el conteo inicial y exige no modificar:

```text
refresh_sessions
bootstrap_ejecuciones
auditoria_eventos
cargo_eventos
notificaciones
```

Motivos:

- `refresh_sessions` debe surgir de autenticación real;
- `bootstrap_ejecuciones` pertenece al bootstrap productivo;
- `auditoria_eventos` es append-only y debe reflejar operaciones reales;
- `cargo_eventos` es append-only y debe reflejar servicios reales;
- `notificaciones` debe surgir del servicio de notificaciones.

Durante la fase HTTP del validador sí pueden aparecer sesiones o auditorías generadas legítimamente por la aplicación. Eso ocurre después de validar que el SQL por sí solo no falsificó datos derivados.

---

## 14. Conteos y agregados esperados

La validación ejecutada durante la reconstrucción produjo:

```text
Usuarios demo:                    5
Alumnos demo:                    28
Inscripciones demo:              34
Mensualidades demo:              70
Matrículas demo:                 26
Cargos demo:                    115
Pagos demo:                      48
Aplicaciones demo:               82
Movimientos de caja:             61
Movimientos de crédito:          11
Movimientos de stock:            14
Recibos:                         48
Outbox de recibos:               48
```

Agregados financieros de referencia:

```text
Pagos registrados:            $1.956.700,00
Aplicaciones activas:         $1.938.700,00
Crédito activo de pagos:         $18.000,00
Crédito neto global:              $21.000,00
```

Conciliación principal:

```text
$1.938.700,00 + $18.000,00 = $1.956.700,00
```

Los valores son deterministas para la versión actual del seed y la misma fecha ancla.

---

## 15. Validaciones internas del SQL

Antes del `COMMIT`, el seed verifica:

- existencia de todas las tablas requeridas;
- V6 aplicada correctamente;
- ausencia de migraciones demo;
- ausencia de migraciones fallidas;
- presencia y actividad de roles operativos;
- estado exacto del rol `PROFESOR`;
- 32 permisos activos de sistema;
- conteos exactos por rol;
- protección de usuarios no demo;
- cardinalidad exacta del dataset;
- ausencia de FK huérfanas;
- origen exclusivo de cada cargo;
- una liquidación por cargo;
- pagos conciliados con aplicaciones y crédito;
- aplicaciones no superiores al pago;
- aplicaciones no superiores al cargo;
- saldos de cargos no negativos;
- estados de cargos coherentes;
- saldo de crédito no negativo;
- stock no negativo;
- stock materializado coherente con su libro;
- ventas con cargo y movimiento;
- ventas anuladas con reverso;
- recibos únicos;
- outbox única;
- claves de idempotencia únicas;
- un único reverso por operación original;
- catálogo RBAC sin cambios;
- matrices RBAC sin cambios;
- tablas derivadas sin cambios.

Cualquier incumplimiento provoca una excepción y evita el commit.

---

## 16. Validaciones del script PowerShell

Además de las validaciones SQL, `validate-demo-seed.ps1` comprueba:

- parser nativo de PowerShell sin errores;
- estructura esperada del repositorio;
- ausencia de operaciones prohibidas en el seed;
- ausencia de credenciales conocidas;
- Docker y Compose disponibles;
- JDK 21 disponible;
- compilación del backend;
- PostgreSQL aislado healthy;
- backend iniciado con Flyway y Hibernate validate;
- `flyway_schema_history` correcto;
- checksums presentes;
- V6 productiva presente;
- ninguna migración demo;
- login de los cinco usuarios;
- 32 permisos en el perfil técnico;
- roles asignables correctos;
- endpoints representativos;
- respuestas 401, 403, 200 y 400 esperadas;
- integridad financiera por SQL;
- idempotencia de una segunda ejecución;
- IDs estables;
- hashes de contenido estables;
- RBAC estable;
- login posterior a la reejecución;
- ausencia de secretos en temporales;
- limpieza de infraestructura.

El proceso devuelve un exit code distinto de cero ante cualquier fallo.

---

## 17. Reejecución e idempotencia

La segunda ejecución debe conservar:

- los mismos IDs;
- los mismos conteos;
- los mismos importes;
- los mismos estados;
- las mismas asociaciones;
- las mismas claves de idempotencia;
- los mismos saldos;
- las mismas matrices RBAC.

El validador toma un snapshot después de la primera ejecución y otro después de la segunda. Compara tanto conteos como huellas MD5 ordenadas de los datos demo.

Una segunda ejecución con otra fecha ancla no es un caso soportado sobre la misma base. Debe crearse otra base descartable.

---

## 18. Limpieza de una aplicación manual

La estrategia soportada es eliminar la base descartable completa.

No intentar limpiar selectivamente el dataset cuando la aplicación ya haya generado:

- auditorías;
- eventos de cargo;
- sesiones;
- recibos físicos;
- notificaciones;
- otras referencias históricas.

Esas tablas son históricas o append-only y una limpieza selectiva puede destruir trazabilidad.

En un proyecto Compose creado exclusivamente para la demo:

```powershell
docker compose -p <proyecto-demo-exacto> down --volumes --remove-orphans
```

Antes de ejecutar el comando, confirmar el nombre exacto del proyecto y que no corresponde al entorno habitual de desarrollo.

No usar:

```text
TRUNCATE
DROP SCHEMA public
docker volume prune
session_replication_role
DISABLE TRIGGER
DELETE sin filtros
```

---

## 19. Limitaciones conocidas

### Estado de asistencia `JUSTIFICADO`

La migración V1 define:

```sql
estado VARCHAR(10)
```

pero el `CHECK` admite `JUSTIFICADO`, que ocupa 11 caracteres. PostgreSQL rechaza el valor antes de evaluar el constraint.

El seed actual utiliza únicamente:

```text
PRESENTE
AUSENTE
```

hasta que una migración productiva posterior amplíe la columna. No modificar V1 retroactivamente.

### Recibos físicos

El seed crea metadatos de `recibos` y `recibos_pendientes`, pero no fabrica archivos PDF. Algunas filas contienen una `storage_key` ficticia bajo `demo/recibos/` para representar estados históricos.

El endpoint de descarga puede devolver 404 si no existe el archivo físico, lo cual es esperado para esos registros sintéticos.

### Eventos y auditoría

El SQL no crea `cargo_eventos` ni `auditoria_eventos`. Las pantallas que dependan exclusivamente de eventos posteriores pueden mostrar sólo aquello generado durante operaciones reales de la aplicación.

### Profesores sin usuario

Los seis profesores demo tienen `usuario_id = NULL`. El rol `PROFESOR` permanece deshabilitado hasta que exista ownership seguro en backend.

### Dataset descartable

El seed no es un instalador, una migración ni un mecanismo de restauración. No debe utilizarse para reparar datos productivos.

---

## 20. Advertencia de producción

> **PROHIBIDO EJECUTAR ESTE SEED EN PRODUCCIÓN.**
>
> El archivo crea identidades ficticias, pagos, cargos, movimientos de caja, crédito, stock y recibos. Aunque utiliza namespace reservado y protege RBAC, está diseñado únicamente para bases locales o efímeras de demostración.

No ejecutar contra:

- una base productiva;
- una copia con datos personales reales;
- un entorno compartido por usuarios;
- un entorno cuya eliminación completa no esté autorizada;
- una base que se use como respaldo o staging persistente.

La precondición del seed no puede determinar por sí sola si una base es comercialmente productiva. La responsabilidad de elegir una base descartable pertenece al operador.

---

## 21. Solución de problemas

### Docker no está disponible

```text
Docker no está disponible en PATH
```

Acciones:

1. iniciar Docker Desktop;
2. esperar a que el Engine esté operativo;
3. ejecutar `docker info`;
4. reintentar.

### No se encuentra JDK 21

Comprobar:

```powershell
$env:JAVA_HOME
java -version
javac -version
```

`JAVA_HOME` debe apuntar a un JDK, no a un JRE.

### `-SkipBackendBuild` falla

Ejecutar primero sin el switch o generar el JAR:

```powershell
Set-Location .\backend
.\mvnw.cmd -DskipTests package
Set-Location ..
```

### V6 no fue aplicada

No ejecutar el seed directamente. Iniciar el backend con Flyway habilitado y revisar `flyway_schema_history`.

Consulta de diagnóstico:

```sql
SELECT installed_rank, version, description, script, checksum, success
FROM flyway_schema_history
ORDER BY installed_rank;
```

### Se detectó una migración demo

Retirar la migración de demostración del classpath y reconstruir una base desde cero. No editar manualmente `flyway_schema_history`.

### La fecha ancla difiere

Eliminar la base descartable y crear otra. No actualizar en masa fechas históricas.

### La segunda ejecución cambia el snapshot

Revisar:

- que se reutilice la misma fecha ancla;
- que se reutilicen los mismos hashes;
- que no hayan corrido schedulers;
- que no haya procesos externos modificando la base;
- que el backend se haya detenido antes de la segunda ejecución.

### Quedaron recursos Docker

Listar recursos por nombre exacto y eliminar sólo el proyecto aislado. No usar limpiezas globales.

---

## 22. Criterios de aceptación

La validación se considera exitosa cuando:

- el script termina con exit code 0;
- todas las etapas relevantes aparecen como `PASS`;
- Flyway aplicó todas las migraciones productivas;
- V6 está presente y exitosa;
- no existe migración Flyway demo;
- Hibernate inicia con `ddl-auto=validate`;
- los cinco usuarios pueden iniciar sesión;
- los perfiles reflejan los roles esperados;
- las pruebas positivas y negativas de RBAC coinciden con V6;
- los conteos del dataset son exactos;
- no existen inconsistencias financieras;
- la segunda ejecución produce un snapshot idéntico;
- RBAC no cambia;
- no quedan secretos en temporales;
- no quedan contenedores, redes o volúmenes del proyecto aislado.

---

## 23. Archivos relacionados

```text
scripts/gestudio_demo_seed_full.sql
scripts/validate-demo-seed.ps1
docs/testing/demo-seed.md
docs/codex/gestudio-release-hardening/12_AUDITORIA_SEED_DEMO.md
backend/src/main/resources/db/migration/V6__rbac_permission_catalog_and_base_roles.sql
```

El informe de auditoría y evidencia final se mantiene separado de esta guía operativa.


## Actualización operativa 2026-07-20

El gate actual exige Flyway V1-V7. V6 continúa siendo la autoridad del catálogo RBAC y V7 agrega únicamente snapshots firmados de integración, deshabilitados por defecto. El seed no inserta datos en las tablas V7 y verifica que existan antes de operar.
