# Runbook operativo del control plane de plataforma

- Estado del runbook: `IMPLEMENTED_NOT_RUN`
- Estado de evidencia operativa: `PARTIAL`
- Fecha de revisión: 2026-08-13
- Alcance: acceso `SUPERADMIN`, activación, tenants, administradores,
  step-up, auditoría, bootstrap, recuperación e incidentes

## Qué acredita y qué no acredita

Este runbook refleja las rutas, controles y herramientas presentes en el
checkout. En esta revisión no se ejecutaron Docker, PostgreSQL, browser E2E,
bootstrap, backup/restore, rollback ni CI sobre el SHA candidato. Por eso su
existencia no habilita `RELEASE_READINESS=PASS` ni autoriza producción.

Documentos complementarios:

- [ADR-0009: arquitectura del control plane](../architecture/adr-0009-platform-control-plane.md)
- [Threat model del control plane](../architecture/threat-model-platform-control-plane.md)
- [Despliegue idempotente en Windows](../deployment-windows.md)
- [Variables de entorno](../development/environment-variables.md)
- [Observabilidad y diagnóstico](observability.md)
- [Backup y restore](backup-restore.md)
- [Rollback compatible con Flyway](rollback.md)
- [Flujo local general](local-runbook.md)

Las guías enlazadas son la autoridad para sus operaciones. Este documento no
duplica ni reemplaza sus confirmaciones de seguridad.

## Reglas de operación

1. Trabajar desde el checkout y proyecto Compose expresamente autorizados.
   Nunca usar `gestudio-remote-demo`, protegido por contrato.
2. No poner passwords, JWT, secreto TOTP, recovery codes, cookies ni
   credenciales DB en Git, tickets, chat, línea de comandos, screenshots o
   logs.
3. No consultar ni modificar manualmente tablas para saltar MFA, step-up,
   protección del último administrador, RLS o lifecycle.
4. No editar `flyway_schema_history`, no aplicar down migrations y no borrar
   volúmenes para recuperar servicio.
5. Antes de una mutación operativa, capturar SHA/imagen, proyecto, ambiente,
   estado health y un identificador de cambio. Antes de un cambio de datos o
   rollback, seguir el gate de [backup/restore](backup-restore.md).
6. Usar la UI para acciones de plataforma. No improvisar requests directos a
   la API: idempotencia, proof de step-up, versiones y target forman parte del
   contrato.
7. Tratar toda activación y recovery code como secreto one-shot. La API no
   vuelve a exponerlos después de un replay.

## Estado mínimo antes de operar

| Comprobación | Resultado exigido | Estado de esta revisión |
|---|---|---|
| Checkout, rama, SHA e imagen identificados | Coinciden con el cambio autorizado | `NOT_EXECUTED` |
| `deploy.cmd --verify-only` | Exit code `0`, Flyway/ACL/RLS/health sin drift | `NOT_EXECUTED` |
| Frontend y backend accesibles sólo por el origen esperado | URLs y TLS del ambiente confirmados | `NOT_EXECUTED` |
| Bootstrap ordinario | `APP_BOOTSTRAP_SUPERADMIN_ENABLED=false` | `IMPLEMENTED_NOT_RUN` |
| Backup previo cuando corresponde | Paquete validado y custodiado | `NOT_EXECUTED` |
| Observabilidad | Correlación, logs y métricas accesibles sin secretos | `NOT_EXECUTED` |
| Segundo platform admin operativo | Recomendado antes de cambios de MFA/admin | `NOT_EXECUTED` |

En el despliegue Windows documentado, el chequeo de sólo lectura es:

```cmd
deploy.cmd --verify-only
```

Un exit code distinto de cero es un STOP: consultar
[despliegue](../deployment-windows.md#códigos-de-salida) y
[observabilidad](observability.md#diagnóstico) sin mutar la base para ocultar el
problema.

## Superficie operativa

Las rutas de interfaz son:

| Función | Ruta |
|---|---|
| Login platform | `/platform/login` |
| Activación de identidad o MFA | `/platform/activate` |
| Tenants | `/platform/tenants` |
| Alta de tenant | `/platform/tenants/new` |
| Detalle, lifecycle y memberships | `/platform/tenants/:tenantId` |
| Administradores de plataforma | `/platform/admins` |
| Auditoría | `/platform/audit` |

El backend protege `/api/platform/**` con un principal de plataforma. El login,
refresh, logout y la activación tienen contratos propios; que una ruta sea
anónima en la security chain no significa que acepte un token o una operación
sin sus verificaciones de origen, propósito y vigencia.

## Bootstrap del primer administrador

### Precondiciones

- Deploy healthy y `deploy.cmd --verify-only` en cero.
- Configuración efectiva ignorada por Git y proyecto distinto de
  `gestudio-remote-demo`.
- No existe un claim de bootstrap previo.
- Operador interactivo, username aprobado, password fuerte, secreto Base32
  generado por canal autorizado, dispositivo TOTP disponible y una ruta nueva
  fuera del checkout para recovery codes.
- El archivo de destino no existe. El script se niega a sobrescribirlo.

### Ejecución canónica

Desde PowerShell, seguir el comando de
[despliegue](../deployment-windows.md#bootstrap-inicial):

```powershell
$recoveryCodes = 'C:\ruta-segura\gestudio-platform-recovery-codes.txt'
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\bootstrap-platform-admin.ps1 `
  -EnvFile .\.gestudio-deploy\config\deploy.env `
  -ProjectName gestudio-windows `
  -Username '<superadmin-inicial>' `
  -RecoveryCodesPath $recoveryCodes `
  -ConfirmBootstrap
```

El script pide password, secreto TOTP y código actual como `SecureString`. No
pasarlos como argumentos ni pegarlos en una terminal registrada.

El comando crea un job Compose one-shot externo. Sólo dentro de ese proceso
habilita el `ApplicationRunner` condicional de bootstrap; el backend ordinario
permanece deshabilitado. Identidad global, capacidad platform, TOTP verificado,
diez recovery codes y claim se confirman en la misma transacción de plataforma.
Si falla la escritura del artefacto one-shot de recovery, la transacción se
revierte.

Después del commit, el script exige la postcondición persistida: una identidad,
un admin activo con MFA verificado, diez códigos sin usar y cero memberships
tenant. Recién entonces copia el archivo fuera del job, limita el ACL al usuario
Windows actual y elimina el contenedor temporal.

### Cierre de la ceremonia

1. Confirmar éxito del script sin copiar su salida a un ticket público.
2. Mover/custodiar el archivo según la política organizacional aprobada, fuera
   del checkout y del backup ordinario de la aplicación.
3. Verificar login en `/platform/login` con TOTP.
4. Abrir `/platform/audit` y correlacionar el bootstrap sin esperar secretos en
   el evento.
5. Crear cuanto antes un segundo administrador de plataforma independiente y
   probar su acceso antes de considerar recuperable el plano de control.

## Recuperación del job de bootstrap

Si PostgreSQL confirmó el bootstrap pero falló la copia o el ACL local, el
script conserva detenido únicamente ese job y devuelve error. No ejecutar de
nuevo `-ConfirmBootstrap`.

1. Usar exactamente el comando sanitizado que emitió el error, con el mismo
   env file/proyecto, el ID completo en `-RecoverJobId`, un destino todavía
   inexistente y `-ConfirmRecovery`.
2. No inspeccionar `docker inspect`, el entorno ni los logs del job retenido:
   contienen los secretos de la ceremonia.
3. El modo recovery no solicita ni acepta username, password, secreto TOTP o
   código TOTP. Valida ID, labels, nombre del job y postcondiciones DB.
4. Si vuelve a fallar, conservar el job y escalar el problema. El script sólo
   lo elimina después de publicar exactamente diez códigos con ACL restringida.
5. Una vez recuperado, completar el [cierre de la ceremonia](#cierre-de-la-ceremonia).

El detalle contractual y los exit codes permanecen en
[Despliegue idempotente en Windows](../deployment-windows.md#bootstrap-inicial).

## Login de plataforma

1. Ir directamente a `/platform/login`; no usar el login tenant.
2. Ingresar username, password y un TOTP actual. Si se usa recuperación,
   seleccionar explícitamente recovery code; cada código sirve una sola vez.
3. Un error de credenciales, MFA, rate limit o cuenta revocada no se resuelve
   con retries automáticos. Registrar hora y `X-Request-ID` si está disponible,
   esperar el período indicado o iniciar el procedimiento de recuperación.
4. Tras el acceso, confirmar que se ve el control plane y no el dominio de un
   tenant. La sesión platform no otorga lectura funcional cross-tenant.
5. Al finalizar, usar logout. Cerrar la pestaña elimina el access token en
   memoria, pero logout es la acción que revoca la sesión refresh conocida.

El access token no se persiste en storage del navegador. El refresh token se
mantiene en una cookie dedicada `HttpOnly`; nunca debe aparecer en JSON ni ser
copiado por el operador.

## Activación de identidad y MFA

El link one-shot canónico abre `/platform/activate#token=...`. Las pantallas que
lo emiten muestran y copian el enlace completo; no entregan el token crudo como
si fuera una URL. El fragmento no forma parte del request HTTP. En el primer
`useLayoutEffect`, antes del primer paint, la UI lo captura sólo en memoria y
reemplaza query y fragmento por la ruta limpia `/platform/activate`.

Los tokens en query string no están soportados: `/platform/activate?token=...`
se limpia sin usar ese valor y la activación permanece deshabilitada. Tanto
Nginx como la plantilla de Cloudflare Pages endurecen la ruta canónica y su
variante con slash con `Referrer-Policy: no-referrer`; los demás headers de
seguridad siguen aplicando. Estos contratos de borde están implementados, pero
su verificación HTTP en el ambiente candidato continúa `NOT_EXECUTED`.

Entregar el enlace completo por un canal externo aprobado y con vencimiento
útil mínimo.

La página ofrece dos modos que no son intercambiables:

- **Activar identidad tenant (`IDENTITY`)**: definir y confirmar una contraseña
  nueva. No genera recovery codes de plataforma.
- **Configurar MFA de plataforma (`PLATFORM_MFA`)**: generar por un canal
  autorizado un secreto Base32 de al menos 20 bytes, incorporarlo a la app TOTP
  e ingresar el código actual. La contraseña es opcional para una identidad ya
  activa; si se define una nueva, debe confirmarse.

Al completar `PLATFORM_MFA`, guardar inmediatamente los diez recovery codes que
la pantalla muestra una sola vez. No continuar al login hasta confirmar la
custodia. Un token vencido, purpose incorrecto o ya usado requiere emitir una
nueva activación desde un flujo autorizado; no se repara en la base.

La activación de plataforma aprovisiona MFA y consume el token mediante dos
transacciones coordinadas, con compensación que revoca MFA si el cierre de la
activación falla. Esto es distinto del bootstrap inicial, que crea
identidad/admin/MFA/claim dentro de una sola transacción.

## Operación de tenants

### Crear tenant e administrador inicial

1. Iniciar en `/platform/tenants/new`.
2. Definir código y nombre. El código es identidad estable y no se cambia
   después del alta.
3. Elegir un administrador inicial:
   - identidad global existente, seleccionada por ID; o
   - identidad nueva con username aprobado.
4. Completar el step-up cuando la UI lo solicite. El proof queda ligado a
   usuario, sesión, acción, target e idempotency key y sólo sirve una vez.
5. Enviar una sola vez. Ante timeout, conservar la pantalla y reintentar desde
   el flujo de UI para reutilizar el contrato de idempotencia; no crear otra
   solicitud manual.
6. Verificar el detalle creado: tenant `ACTIVE`, roles base, membership
   `ADMINISTRADOR` y evento de auditoría.
7. Si la identidad inicial era nueva, copiar el link de activación one-shot que
   aparece en la respuesta y entregarlo por canal seguro. Un replay de la misma
   alta devuelve el recurso, pero no vuelve a exponer el token.

La operación persiste tenant, matriz de roles base, identidad/membership
inicial, idempotencia y auditoría dentro de una transacción. Una colisión con la
misma key y payload diferente debe tratarse como conflicto, nunca como éxito.

### Lifecycle

La UI define este flujo canónico:

- `ACTIVE` → `SUSPENDED`;
- `SUSPENDED` → `ACTIVE`;
- `SUSPENDED` → `ARCHIVED`;
- `ARCHIVED` no ofrece otra acción.

Suspender o archivar preserva datos; no es borrado. Cada cambio requiere
step-up, motivo cuando la UI lo solicita, versión esperada y confirmación
explícita. Después de mutar:

1. confirmar el nuevo estado y versión en el detalle;
2. validar el efecto de acceso esperado sin asumir que se borraron sesiones o
   historia;
3. correlacionar actor, target, resultado y request en `/platform/audit`;
4. revisar métricas de tenant lifecycle en [observabilidad](observability.md#métricas-del-control-plane).

No usar la API para inventar otra transición aunque el backend reconozca el
valor de estado. El grafo completo está impuesto hoy por la UI, no por una
máquina de estados exhaustiva del backend.

### Memberships y roles tenant

Desde `/platform/tenants/:tenantId` se puede:

- agregar una identidad existente o crear una nueva;
- asignar/reemplazar roles válidos del tenant;
- suspender, reactivar o revocar una membership según las acciones ofrecidas;
- emitir una activación one-shot para una identidad nueva.

Revisar antes el ID global, tenant, roles, vigencia y versión mostrados. La
protección del último `ADMINISTRADOR` activo es un control de seguridad: si una
operación es denegada, crear y probar otro administrador antes de retirar el
último. Una membership revocada se trata como terminal desde la UI; no saltar
esa decisión por SQL o API manual.

## Administradores de plataforma y step-up

Abrir `/platform/admins`. Todas las mutaciones críticas pasan por la ceremonia
de step-up de la UI, que solicita un TOTP reciente y crea un proof one-shot para
la acción exacta.

### Conceder acceso

1. Buscar y confirmar el ID de la identidad global; no inferirlo desde un nombre
   parecido.
2. Elegir conceder acceso y completar step-up.
3. Si la identidad no tiene MFA verificado, copiar el link de activación
   one-shot y entregarlo por canal seguro. No queda recuperable desde un replay.
4. Esperar que complete `/platform/activate` y confirme custodia de sus recovery
   codes.
5. Probar un login independiente y revisar auditoría.

### Revocar acceso

1. Confirmar identidad, estado y que seguirá existiendo al menos otro admin
   activo y probado.
2. Revocar mediante la UI y completar step-up.
3. Verificar estado `REVOKED`, incremento de versión y revocación de familias
   refresh; correlacionar auditoría.

El backend protege al último administrador activo. Una denegación no autoriza
un bypass DB. La UI actual no ofrece reactivación de un admin revocado; seguir
el procedimiento de alta soportado para otra identidad o escalar una mejora de
producto.

### Reset de MFA

1. Confirmar la identidad con un segundo canal.
2. Desde otro administrador activo, elegir reset y completar step-up.
3. Entregar el link one-shot resultante por canal seguro.
4. La persona completa `PLATFORM_MFA`, guarda nuevos recovery codes y prueba
   login.
5. Confirmar que las sesiones anteriores ya no funcionan y revisar auditoría.

Si no existe otro administrador activo y se perdieron TOTP y todos los recovery
codes, detenerse: no hay una ceremonia break-glass operativa certificada en
este runbook.

## Auditoría y revisión diaria

`/platform/audit` permite filtrar por actor, acción, resultado, tenant, rango de
fecha y correlación. Los eventos registran `SUCCESS`, `DENIED` o `FAILED`, pero
no deben contener password, token, secreto MFA, recovery code, cookie, request
body ni credencial DB.

Para cada cambio privilegiado:

1. conservar el `X-Request-ID` o correlation ID visible en la respuesta/error;
2. buscar el evento por correlación;
3. confirmar actor, acción, target, tenant cuando aplique, resultado y hora;
4. tratar la ausencia, duplicación inesperada o metadata sensible como
   incidente;
5. cruzar picos con las métricas y logs definidos en
   [observabilidad](observability.md#métricas-del-control-plane).

La tabla de auditoría es append-only para el runtime mediante grants y trigger.
Eso no sustituye exportación/custodia externa ni protege contra un owner,
migrador o DBA comprometido.

## Recuperación de acceso

Aplicar en orden, sin SQL manual:

1. **TOTP disponible:** iniciar login normal.
2. **TOTP perdido y recovery disponible:** usar un recovery code one-shot y, ya
   autenticado, coordinar un reset controlado desde otro admin.
3. **Recovery agotado/perdido y existe otro admin:** ese admin verifica la
   identidad por segundo canal y ejecuta [reset de MFA](#reset-de-mfa).
4. **Único admin sin TOTP/recovery:** STOP. Preservar logs, SHA, imagen, backup y
   estado; escalar un procedimiento break-glass diseñado, revisado y probado.
   No reactivar bootstrap, no editar tablas y no reutilizar un token vencido.

Para pérdida de datos o incompatibilidad de aplicación, seguir
[backup/restore](backup-restore.md) y [rollback](rollback.md). Restore y rollback
son decisiones separadas; el rollback de código no revierte Flyway.

## Respuesta a incidentes

### Triage y contención

1. Registrar hora UTC/local, ambiente, proyecto, SHA, digest/metadata de imagen,
   health y correlation IDs afectados.
2. Preservar logs sin copiar tokens, cookies, cuerpos o secretos. Usar las
   consultas de [observabilidad](observability.md#correlación-de-solicitudes).
3. Detener cambios administrativos no esenciales. Si corresponde bloquear
   tráfico externo, hacerlo en el edge autorizado sin borrar contenedores,
   volúmenes o DB.
4. Ejecutar `deploy.cmd --verify-only` sólo si el host/proyecto son confiables y
   documentar su exit code. No usar un redeploy para destruir evidencia.
5. Crear un backup según [backup/restore](backup-restore.md) antes de una acción
   correctiva que pueda mutar datos.

### Cuenta o sesión platform comprometida

1. Desde otro admin activo, revocar el admin comprometido mediante step-up.
2. Confirmar revocación de refresh sessions/security version y eventos de
   auditoría.
3. Rotar credenciales externas potencialmente expuestas mediante el proceso de
   despliegue aprobado; no editar secretos en Git ni imprimirlos.
4. Revisar altas/cambios de tenants, memberships, admins, activaciones y MFA
   durante la ventana de compromiso.
5. Recuperar la identidad sólo después de determinar el alcance y usando un
   nuevo flujo de MFA soportado.

### Tenant comprometido

1. Confirmar el tenant exacto y suspenderlo desde la UI con step-up si esa
   contención es proporcional y autorizada.
2. La suspensión preserva datos. No archivar ni borrar como forma de contener.
3. Revisar memberships/roles y auditoría; coordinar recuperación tenant con el
   owner funcional.
4. Reactivar sólo después del criterio de salida aprobado y un smoke de acceso.

### Sospecha de alteración, migración o supply chain

1. Detener publicación y comparar SHA, imagen/SBOM/checks y Flyway contra la
   fuente autorizada.
2. No reparar schema history ni ejecutar DDL ad hoc.
3. Si el artefacto es incompatible pero la DB está íntegra, evaluar el
   [rollback compatible con Flyway](rollback.md).
4. Si la integridad de datos está comprometida, restaurar primero a un destino
   nuevo siguiendo [backup/restore](backup-restore.md#restaurar-primero-a-una-base-nueva).
5. Mantener `RELEASE_READINESS` fuera de `PASS` hasta repetir todos los gates
   sobre un SHA definitivo confiable.

## Limitaciones conocidas y STOP conditions

- Los gates PostgreSQL/Testcontainers, Docker, E2E browser, backup/restore,
  rollback, bootstrap y CI están `NOT_EXECUTED` en esta revisión.
- No hay evidencia actual de staging/producción para TLS, proxy, DNS, CORS,
  cookies, CSP, correo ni storage externo.
- No están provistos/validados un collector central, alertas administradas,
  on-call, tracing ni retención externa de auditoría.
- El backup no aporta por sí solo cifrado externo, custodia, retención o RPO/RTO
  contractuales.
- Tokens de activación y recovery codes se muestran una vez y requieren entrega
  externa segura; el producto no puede reconstruirlos.
- No existe un break-glass certificado para el caso en que el único platform
  admin pierde TOTP y recovery codes. Las protecciones del último admin son
  intencionales.
- La UI no ofrece reactivar un platform admin revocado ni una membership
  revocada.
- `ARCHIVED` es terminal en la UI. El backend valida valores de estado, pero no
  implementa por sí solo todo el grafo canónico de transiciones tenant.
- Spring CSRF está deshabilitado; bearer tokens, `SameSite` y origin checking
  reducen exposición, pero el E2E adversarial de navegador no fue ejecutado.
- La configuración de cookie platform es segura por defecto y rechaza
  `SameSite=None` sin `Secure`; no se evidenció un guard de producción que exija
  explícitamente `Secure=true` para todas las demás combinaciones.
- La auditoría usa metadata construida por el servidor, pero no se demostró un
  clasificador recursivo genérico que detecte cualquier secreto futuro.
- No hay evidencia actual de performance, resiliencia o recuperación bajo
  carga del control plane.

Cualquiera de estas situaciones exige detener la declaración de release, no
maquillarla con una prueba parcial. El criterio final permanece en el
[threat model](../architecture/threat-model-platform-control-plane.md#criterios-para-cerrar-esta-revisión)
y en los gates del SHA definitivo.
