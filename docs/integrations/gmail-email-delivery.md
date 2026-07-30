# Entrega de email controlada

## Estado certificado

```text
EMAIL_NOOP=EXECUTED_PASS
EMAIL_FAKE=EXECUTED_PASS
GMAIL_SMTP_ADAPTER=IMPLEMENTED_NOT_CONNECTED
GMAIL_OAUTH2=NOT_IMPLEMENTED
GMAIL_REAL_DELIVERY=BLOCKED_EXTERNAL_CREDENTIALS
PRODUCTION_EMAIL=NOT_DEPLOYED
```

No se usaron credenciales ni se realizó tráfico hacia Gmail para implementar o
validar esta frontera.

## Arquitectura

`IEmailService` es la única frontera consumida por cumpleaños y por la outbox de
recibos. La propiedad `APP_EMAIL_PROVIDER` selecciona exactamente una
implementación:

| Proveedor | Implementación | Red | Resultado de éxito |
|---|---|---|---|
| `NOOP` | `NoOpEmailService` | nunca | `NOOP` |
| `FAKE` | `FakeEmailService` | nunca | `SIMULATED` |
| `GMAIL_SMTP` | `GmailSmtpEmailService` | sólo con todas las guardas abiertas | `PROVIDER_ACCEPTED` |

`EmailDeliveryPolicy` aplica las guardas antes de crear el MIME o llamar a
`JavaMailSender`. `EmailDeliveryConfigurationGuard` valida en startup sólo el
modo Gmail efectivamente habilitado para red. `EmailDeliveryResult` devuelve una
clasificación tipada a los consumidores y `EmailDeliveryMetrics` registra el
resultado sin PII.

No se agregó otra cola, base, migración ni dependencia. La outbox de recibos y
la deduplicación diaria de cumpleaños existentes siguen siendo las autoridades.

## Guardas fail-closed

Los valores predeterminados son:

```dotenv
APP_EMAIL_ENABLED=false
APP_EMAIL_PROVIDER=NOOP
APP_EMAIL_DRY_RUN=true
APP_EMAIL_REAL_NETWORK_ALLOWED=false
APP_EMAIL_KILL_SWITCH=true
APP_EMAIL_FROM_ADDRESS=
APP_EMAIL_FROM_NAME=Gestudio
APP_EMAIL_SENT_COPY_MODE=DISABLED
```

Una entrega SMTP real sólo podría ejecutarse si todas estas condiciones se
cumplen simultáneamente:

1. perfil `prod` activo;
2. `APP_EMAIL_ENABLED=true`;
3. `APP_EMAIL_PROVIDER=GMAIL_SMTP`;
4. `APP_EMAIL_DRY_RUN=false`;
5. `APP_EMAIL_REAL_NETWORK_ALLOWED=true`;
6. `APP_EMAIL_KILL_SWITCH=false`;
7. sender y configuración SMTP completos y válidos;
8. TLS, autenticación y timeouts explícitos;
9. mensaje válido.

`prod` y `APP_SCHEDULING_ENABLED=true` no abren ninguna de esas guardas. El
entorno puede volver a bloquear una configuración menos restrictiva con el kill
switch, dry-run o la política de red.

## Modos locales

### NOOP

Es el default de todos los perfiles, incluido `prod`. Valida el contrato del
mensaje, no crea conexiones, no exige secretos y devuelve `NOOP`. Cumpleaños y
recibos registran el resultado técnico, pero un recibo no obtiene `enviadoAt`.

### FAKE

Se selecciona explícitamente con `APP_EMAIL_PROVIDER=FAKE`. Nunca usa
`JavaMailSender` ni IMAP. `APP_EMAIL_FAKE_OUTCOME` admite:

- `SUCCESS` → `SIMULATED`;
- `TEMPORARY_FAILURE` → `PROVIDER_TEMPORARY_FAILURE`;
- `PERMANENT_FAILURE` → `PROVIDER_PERMANENT_FAILURE`.

El fake conserva sólo el último resultado sanitizado para pruebas; no guarda
destinatario, subject, HTML, adjuntos ni secretos. `SIMULATED` no equivale a
entrega externa y no marca `enviadoAt`.

## Gmail SMTP

El adaptador construye MIME multipart UTF-8 con sender configurado, HTML,
inline y adjunto opcional. Exige STARTTLS, autenticación, protocolos TLS
permitidos y timeouts positivos. No conecta durante startup y una política
bloqueada no llega a `createMimeMessage()` ni `send()`.

El sender sale únicamente de `APP_EMAIL_FROM_ADDRESS` y
`APP_EMAIL_FROM_NAME`. Para la habilitación actual, la dirección debe coincidir
con el usuario SMTP; no se aceptan aliases libres enviados por consumidores.

La validación rechaza:

- destinatario ausente, múltiple, con display name o CR/LF;
- subject vacío, con CR/LF o mayor a 200 caracteres;
- HTML vacío o mayor a 256 KB UTF-8;
- inline vacío o mayor a 2 MB, MIME inválido o content ID inseguro;
- adjunto vacío o mayor a 10 MB, MIME inválido, nombre mayor a 128 caracteres,
  con separadores de ruta o caracteres de control.

No se aplica una reescritura destructiva del HTML. Los datos variables de la
plantilla de cumpleaños se escapan antes de interpolarlos.

## Autenticación y secretos

OAuth2/XOAUTH2 es el mecanismo preferido para una conexión futura. Google
documenta XOAUTH2 para IMAP, POP y SMTP y el scope de correo correspondiente en
[OAuth 2.0 Mechanism](https://developers.google.com/workspace/gmail/imap/xoauth2-protocol).
`GMAIL_OAUTH2=NOT_IMPLEMENTED`: este repositorio no inventa autorización,
refresh, scopes ni almacenamiento de tokens en esta entrega.

El adaptador configurable actual admite una contraseña de aplicación como
alternativa explícita y transitoria. Google indica que las contraseñas de
aplicación requieren verificación en dos pasos y no son recomendables salvo que
la aplicación las necesite; véase [Sign in with app passwords](https://support.google.com/accounts/answer/185833?hl=en).
Una contraseña normal de la cuenta no está admitida ni documentada.

Los secretos deben inyectarse desde el secret manager del entorno. No deben
aparecer en `.env`, Compose versionado, argumentos de shell, logs, dumps,
evidencias ni tickets.

## SMTP y copia Sent

La aceptación SMTP y el append IMAPS son operaciones separadas:

| `APP_EMAIL_SENT_COPY_MODE` | Semántica |
|---|---|
| `DISABLED` | default; no abre IMAP |
| `BEST_EFFORT` | intenta append después de SMTP; el fallo devuelve `SENT_COPY_FAILED` sin reenviar |
| `REQUIRED` | rechazado en startup para Gmail porque no existe atomicidad SMTP/IMAP segura |

Un `SENT_COPY_FAILED` cuenta como proveedor aceptado para la outbox de recibos:
confirma `enviadoAt`, incrementa su métrica específica y evita un segundo SMTP.
Antes de usar `BEST_EFFORT` debe verificarse con la cuenta real si el proveedor
ya conserva los enviados para no duplicar copias.

Timeouts configurables, todos con default 5000 ms:

- `APP_EMAIL_SMTP_CONNECTION_TIMEOUT_MS`;
- `APP_EMAIL_SMTP_READ_TIMEOUT_MS`;
- `APP_EMAIL_SMTP_WRITE_TIMEOUT_MS`;
- `APP_EMAIL_SENT_COPY_CONNECTION_TIMEOUT_MS`;
- `APP_EMAIL_SENT_COPY_READ_TIMEOUT_MS`.

## Recibos

`ReciboStorageService` mantiene el claim, lease, máximo de cinco intentos,
generación/almacenamiento una sola vez y confirmación existente.

| Resultado email | `enviadoAt` | retry email | estado del trabajo |
|---|---:|---:|---|
| `NOOP`, `SIMULATED` o bloqueo de política | no | no | completado localmente |
| `PROVIDER_TEMPORARY_FAILURE` | no | sí, con backoff existente | pendiente hasta límite |
| rechazo/permanente/`INVALID_MESSAGE` | no | no | error terminal |
| `PROVIDER_ACCEPTED` | sí | no | completado |
| `SENT_COPY_FAILED` | sí | no | completado; alerta separada |

El modo seguro no programa envíos históricos para una activación posterior. Un
operador debe crear un procedimiento explícito si alguna vez necesitara
reprocesar trabajos completados sin entrega real.

## Cumpleaños

El job diario sigue condicionado por `APP_SCHEDULING_ENABLED`. Consulta sólo
personas activas y omite alumnos sin email. La notificación se deduplica por
persona y fecha en PostgreSQL y el email se dispara after-commit. El proveedor
vuelve a aplicar todas las guardas; habilitar el scheduler no habilita red.

La garantía real es una deduplicación diaria del disparo de aplicación, no
exactly-once externo: no existe una segunda outbox de cumpleaños. Un proceso que
termine después del commit y antes del executor puede perder ese efecto. Los
fallos quedan contenidos y no generan retry infinito.

## Observabilidad

Micrometer expone:

```text
gestudio_email_attempts_total
gestudio_email_blocked_total
gestudio_email_simulated_total
gestudio_email_provider_failures_total
gestudio_email_sent_copy_failures_total
```

Los únicos tags son `provider`, `result` y `message_type`. Los logs incluyen un
evento técnico por operación con esos campos y una causa acotada; no incluyen
email, alumno/pago como tag, subject, HTML, adjuntos, credenciales ni mensajes de
excepción arbitrarios. Gmail no participa en liveness ni readiness.

## Validación sin red

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\verify-email-delivery.ps1
```

El gate ejecuta los dobles SMTP/IMAP, NOOP, FAKE, selección de beans, cumpleaños,
recibos, métricas, sanitización, secret scan y los tres Compose. Rechaza destinos
Gmail reales versionados y deja evidencia en `%TEMP%\GestudioEmailDelivery`,
fuera de Git. No requiere ni acepta una cuenta Gmail.

## Habilitación futura controlada

1. Completar revisión de seguridad, cuenta Workspace, OAuth2 preferido y gestión
   de secretos.
2. Configurar un staging aislado con sender único, destinatario sintético
   autorizado y monitoreo.
3. Mantener `APP_EMAIL_KILL_SWITCH=true` mientras se valida startup/configuración.
4. Cargar host, puerto, usuario, secreto, sender, TLS y timeouts desde secretos.
5. Elegir `GMAIL_SMTP`; conservar dry-run y red bloqueada para una primera
   comprobación sin socket.
6. Abrir todas las condiciones sólo dentro de una ventana autorizada y ejecutar una
   entrega controlada única.
7. Confirmar aceptación, no duplicación, métricas, logs y política Sent antes de
   ampliar alcance.

Esta misión no ejecutó esos pasos externos.

## Bloqueo, rollback y troubleshooting

Para cortar inmediatamente, establecer cualquiera de estas combinaciones y
reiniciar el backend:

```dotenv
APP_EMAIL_KILL_SWITCH=true
APP_EMAIL_REAL_NETWORK_ALLOWED=false
APP_EMAIL_DRY_RUN=true
APP_EMAIL_ENABLED=false
APP_EMAIL_PROVIDER=NOOP
```

No hay rollback de base: no se agregó migración. El rollback de aplicación debe
mantener email bloqueado y seguir el runbook general. Diagnóstico:

- startup falla: revisar nombres/formatos requeridos; el error no muestra valores;
- `BLOCKED_*`: revisar guardas efectivas, sin abrirlas todas fuera de una ventana;
- temporal: conservar retry acotado de recibos y revisar métricas;
- permanente/rechazo: corregir configuración o mensaje, no reintentar en loop;
- `SENT_COPY_FAILED`: no reenviar; revisar únicamente la estrategia de copia;
- ausencia de métricas: verificar token Prometheus y que haya existido un intento.

## Riesgos residuales externos

Faltan credenciales autorizadas, implementación/autorización OAuth2, definición
de la cuenta Workspace, DNS SPF/DKIM/DMARC, staging, prueba real controlada,
despliegue productivo y monitoreo externo. Nada de eso se acredita con los tests
locales.
