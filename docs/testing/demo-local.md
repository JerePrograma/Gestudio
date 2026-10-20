# Demo local multitenant persistente

La demo canónica compone el control plane y el fixture funcional existentes. No
duplica Flyway ni el E2E: usa `scripts/e2e/run-control-plane.ps1` para el
aprovisionamiento real y `scripts/gestudio_demo_seed_full.sql` para datos de
negocio externos a Flyway.

Requisitos: Windows, PowerShell 7, Git, JDK 21, Node 22, Docker Compose v2 y un
daemon Docker Desktop local en modo Linux. El script rechaza un daemon remoto,
puertos ocupados y los proyectos protegidos.

## Operación canónica

Desde la raíz del repositorio:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Start

pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Status

pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Stop

pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Reset `
  -ConfirmReset
```

`Start` construye desde el checkout, crea o reutiliza configuración privada,
levanta PostgreSQL, verifica B12/Flyway/Hibernate, ejecuta el bootstrap one-shot
del primer `PLATFORM_SUPERADMIN`, exige MFA TOTP, aprovisiona Alpha y Beta por el
control plane, carga los fixtures tenant-aware y termina sólo si `Status` pasa.
Un segundo `Start` conserva IDs, datos, auditoría y secretos; no duplica el
escenario.

`Status` es estrictamente de sólo lectura. `Stop` baja contenedores pero conserva
los dos volúmenes y el estado privado. `Reset` no funciona sin `-ConfirmReset`;
elimina exclusivamente contenedores, red y volúmenes etiquetados con el proyecto
exacto, borra su configuración privada y reconstruye desde cero. Nunca ejecuta
una limpieza Docker global.

## Identidad y direcciones

- proyecto Compose: `gestudio-demo-local`;
- PostgreSQL: `127.0.0.1:15432`;
- backend/API: `http://127.0.0.1:18080` y
  `http://127.0.0.1:18080/api`;
- frontend: `http://127.0.0.1:18081`;
- control plane: `http://127.0.0.1:18081/platform/login`;
- liveness/readiness: `/actuator/health/liveness` y
  `/actuator/health/readiness` sobre el backend.

Los puertos se publican explícitamente en `127.0.0.1`; no se depende del binding
implícito del Compose productivo.

## Actores y tenants

Plataforma:

- `platform.demo.admin`: `PLATFORM_SUPERADMIN`, MFA verificado y cero
  memberships tenant.

Tenant Alpha, código `escuela-danza-marcos-paz`, nombre visible
`Escuela Danza Marcos Paz`:

- `alpha.demo.admin`, administrador inicial aprovisionado por control plane;
- `demo-superadmin`, `demo-direccion`, `demo-administrador`,
  `demo-secretaria` y `demo-caja`;
- fixture amplio de 914 filas con alumnos, profesores, disciplinas, horarios,
  inscripciones, tarifas, condiciones económicas, cargos, pagos, recibos, caja,
  egresos, stock, asistencias y reportes.

Tenant Beta, código `escuela-beta-demo`, nombre visible `Escuela Beta Demo`:

- `beta.demo.admin`;
- un alumno, profesor, salón, disciplina y stock mínimo;
- el mismo documento y código de barras representativos que Alpha para probar
  unicidad tenant-scoped sin compartir filas.

`SUPERADMIN` sigue siendo un rol tenant legacy. No equivale a
`PLATFORM_SUPERADMIN` y no autoriza `/api/platform/**`.

## Credenciales, MFA y recuperación

En la primera ejecución se generan secretos criptográficamente aleatorios y se
guardan fuera del checkout en:

```text
%LOCALAPPDATA%\Gestudio\gestudio-demo-local
```

El directorio, `e2e.env`, `credentials.json` y
`platform-recovery-codes.txt` reciben ACL para el usuario Windows actual. El
script nunca imprime passwords, secreto TOTP ni recovery codes. `Status` sólo
muestra la ruta del manifiesto privado.

Para la ceremonia de presentación:

1. el operador abre localmente `credentials.json` desde su sesión Windows;
2. importa el secreto TOTP sintético de `platform.demo.admin` en su autenticador;
3. inicia sesión con password y código actual en `/platform/login`;
4. custodia los recovery codes fuera de screenshots, tickets y grabaciones;
5. no copia el manifiesto al repositorio ni reutiliza sus valores fuera de la
   demo.

`Start` posterior a `Stop` reutiliza estos valores. Sólo `Reset -ConfirmReset`
los rota porque reconstruye toda la demo.

## Qué acredita Status

Un exit code cero exige, como mínimo:

- tres contenedores exactos, healthy, del proyecto exacto;
- puertos loopback, image ID, revisión Git, hash Compose y fingerprints de
  fuentes sin drift;
- Flyway válido en la última versión derivada, cero migraciones fallidas y
  ningún seed dentro de Flyway;
- `gestudio_multitenancy_health() = GREEN`;
- runtime tenant y control plane sin `SUPERUSER` ni `BYPASSRLS`;
- plataforma inicializada, MFA verificado y bootstrap platform-only sin
  membership;
- Alpha/Beta activos, memberships, datasets, claves naturales repetidas e
  integridad del libro de stock;
- RLS forzado en alumnos, pagos y stock; lectura Alpha sin filas Beta;
- control runtime sin lectura funcional global y auditoría append-only;
- logins sintéticos activos, auditoría presente y sin material sensible;
- frontend, API, liveness y readiness reales.

Ante cualquier diferencia imprime `Demo disponible: NO`, explica la condición
sin exponer secretos y devuelve un exit code distinto de cero.

## Recorrido sugerido

1. Plataforma: login MFA, tenants, detalle, memberships, administradores,
   auditoría, suspensión/reactivación y logout.
2. Alpha: dashboard, alumnos, profesores, disciplinas/horarios, inscripción,
   tarifa/condición, cargos, pagos/recibos, caja/egresos, stock, asistencias,
   reportes y logout.
3. Roles Alpha: verificar rutas permitidas y `403` para Secretaría/Caja donde
   corresponda.
4. Beta: login, datos propios, operación mínima e intento de recurso Alpha
   rechazado.
5. Persistencia: `Stop`, `Start`, `Status`; comprobar que no cambian tenants,
   datos, auditoría ni configuración.

SMTP/IMAP reales, DNS, TLS público, métricas externas, secret manager cloud y
Jere Platform desplegado no forman parte de la demo local. Permanecen
fail-closed o deshabilitados.

## Fixture nativo de compatibilidad

`-Action SeedNative` sigue disponible para validaciones locales controladas. El
flujo multitenant canónico ya aprovisiona tenant, roles y memberships mediante
el control plane antes de cargar negocio. El SQL conserva un modo compatible
para ambientes efímeros seedless, siempre limitado al tenant explícito y fuera
de Flyway.
