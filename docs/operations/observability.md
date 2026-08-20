# Observabilidad mínima y diagnóstico operativo

## Estado y alcance

Este runbook cubre la observabilidad técnica integrada en Gestudio. No reemplaza un servicio externo de monitoreo ni constituye por sí solo un SLA productivo.

Incluye:

- liveness y readiness de Spring Boot Actuator;
- métricas de la frontera de email sin PII;
- métricas de negocio y seguridad del control plane con cardinalidad acotada;
- readiness vinculada a PostgreSQL y espacio en disco;
- métricas Prometheus protegidas por token externo;
- correlación `X-Request-ID`;
- logs HTTP sanitizados;
- healthchecks Docker basados en readiness real;
- drill automatizado y evidencia en GitHub Actions.

No incluye todavía:

- servidor Prometheus administrado;
- Grafana;
- alertas remotas;
- retención centralizada de logs;
- tracing distribuido;
- on-call ni responsables de escalamiento;
- validación en staging o producción.

## Endpoints

| Endpoint | Acceso | Objetivo |
|---|---|---|
| `GET /actuator/health/liveness` | público | confirmar que el proceso puede continuar ejecutándose |
| `GET /actuator/health/readiness` | público | confirmar que la aplicación y PostgreSQL están listas para recibir tráfico |
| `GET /actuator/prometheus` | token obligatorio | exponer métricas para un scraper autorizado |

Los endpoints de health responden sin detalles de componentes. Sólo exponen el estado agregado.

Todos los demás endpoints Actuator quedan fuera de la exposición web o denegados por seguridad.

## Token de métricas

Variable requerida en producción:

```text
APP_OBSERVABILITY_METRICS_TOKEN=<valor-aleatorio-independiente-de-al-menos-32-bytes-UTF-8>
```

Cabecera requerida:

```text
X-Gestudio-Metrics-Token: <valor exacto>
```

Reglas:

- no reutilizar `JWT_SECRET`;
- no versionar el token;
- no incluirlo en URLs;
- no imprimirlo en logs;
- no enviarlo desde el navegador;
- suministrarlo solamente al backend y al scraper;
- rotarlo mediante el mecanismo de secretos del ambiente destino.

Un token ausente, vacío, incorrecto o excesivamente largo devuelve `401 Unauthorized`.

## Consultas rápidas

### PowerShell

```powershell
$base = 'http://localhost:8080'

Invoke-RestMethod "$base/actuator/health/liveness"
Invoke-RestMethod "$base/actuator/health/readiness"

$headers = @{
    'X-Gestudio-Metrics-Token' = $env:APP_OBSERVABILITY_METRICS_TOKEN
}
Invoke-WebRequest "$base/actuator/prometheus" -Headers $headers
```

### curl

```bash
curl --fail http://localhost:8080/actuator/health/liveness
curl --fail http://localhost:8080/actuator/health/readiness
curl --fail \
  -H "X-Gestudio-Metrics-Token: $APP_OBSERVABILITY_METRICS_TOKEN" \
  http://localhost:8080/actuator/prometheus
```

## Correlación de solicitudes

El backend acepta la cabecera:

```text
X-Request-ID
```

Formato admitido:

- entre 1 y 128 caracteres;
- primer carácter alfanumérico;
- resto limitado a letras, números, punto, guion, guion bajo y dos puntos.

Cuando el valor falta o es inseguro, el backend genera un UUID. El valor efectivo siempre se devuelve en la respuesta.

Para los orígenes CORS configurados, el navegador puede enviar `X-Request-ID` y leerlo en la respuesta. El contrato mantiene `Access-Control-Allow-Credentials: true`, por lo que las cookies de sesión siguen sujetas al origen explícitamente permitido; no se habilita un origen comodín.

Ejemplo:

```powershell
$response = Invoke-WebRequest `
  'http://localhost:8080/api/alumnos' `
  -Headers @{ 'X-Request-ID' = 'soporte-20260720-001' } `
  -SkipHttpErrorCheck

$response.Headers['X-Request-ID']
```

Ese ID permite correlacionar la respuesta del usuario con la línea de log correspondiente.

## Contrato de logs HTTP

Para rutas `/api/**` se registra una sola línea al finalizar la solicitud:

```text
requestId=<id> http_request method=<método> path=<ruta> status=<código> durationMs=<milisegundos> outcome=<completed|exception>
```

No se registran deliberadamente:

- query strings;
- cuerpos de solicitud o respuesta;
- cabecera `Authorization`;
- cookies;
- refresh tokens;
- token de métricas;
- claves de base de datos;
- secretos de integraciones;
- datos personales enviados en formularios.

Saltos de línea y tabulaciones se sustituyen para impedir inyección de líneas de log.

## Métricas de email

La frontera controlada publica estos contadores Prometheus:

```text
gestudio_email_attempts_total
gestudio_email_blocked_total
gestudio_email_simulated_total
gestudio_email_provider_failures_total
gestudio_email_sent_copy_failures_total
```

Los tags son únicamente `provider`, `result` y `message_type`. No se usan
destinatario, IDs, subject ni excepción arbitraria como labels. Los logs tampoco
incluyen email completo, HTML, PDF, adjuntos o secretos. Gmail no participa en
liveness/readiness; un bloqueo externo no baja la salud general.

`pwsh -NoProfile -File .\scripts\ops\verify-email-delivery.ps1` valida métricas y
sanitización sin red Gmail y deja evidencia fuera del repositorio.

## Métricas del control plane

El backend publica el contrato mínimo del control plane en estos contadores:

```text
gestudio_platform_tenant_events_total
gestudio_platform_membership_events_total
gestudio_platform_bootstrap_events_total
gestudio_platform_mfa_events_total
gestudio_platform_auth_failures_total
gestudio_platform_authorization_denials_total
gestudio_platform_provisioning_failures_total
```

Cubren creación y cambios de estado de tenants; creación, cambio de estado y
cambio de roles de memberships; bootstrap inicial; MFA; fallos de autenticación;
cruces de scope rechazados; y fallos atómicos de provisioning. Un replay
idempotente no vuelve a incrementar una métrica de éxito. Los éxitos se emiten
después de que la transacción retorna confirmada y cada fallo se registra una
sola vez por operación.

Las únicas etiquetas posibles son valores allowlist de:

```text
event, result, method, operation, reason, source_scope, target_scope, resource
```

No se usan como etiquetas: tenant ID o código, membership ID, usuario,
correlation ID, IP, user-agent, excepción, password, token, código de
recuperación ni secreto MFA. El correlation ID permanece en auditoría y logs
sanitizados para investigar una señal sin convertirlo en una dimensión
Prometheus de alta cardinalidad.

Consultas PromQL iniciales:

```promql
sum by (event) (rate(gestudio_platform_tenant_events_total[5m]))
sum by (result) (increase(gestudio_platform_bootstrap_events_total[15m]))
sum by (method, result) (rate(gestudio_platform_mfa_events_total[5m]))
sum by (operation, reason) (rate(gestudio_platform_auth_failures_total[5m]))
sum by (source_scope, target_scope) (
  rate(gestudio_platform_authorization_denials_total{reason="cross_scope"}[5m])
)
sum by (resource, reason) (increase(gestudio_platform_provisioning_failures_total[15m]))
```

Alertas recomendadas cuando exista un Alertmanager o equivalente real:

- cualquier bootstrap `failed` o más de un bootstrap `success` en una ventana;
- provisioning failure sostenido o cualquier failure `database`;
- aumento abrupto de MFA `rate_limited` o auth failures;
- cruces de scope sostenidos en cualquiera de las dos direcciones.

Estas son reglas de diseño; no se afirma entrega de alertas hasta configurar y
probar el backend de alertas del ambiente destino.

## Comandos Docker

Estado:

```powershell
docker compose --env-file .env -p gestudio ps
```

Logs recientes:

```powershell
docker compose --env-file .env -p gestudio logs --tail 200 backend db
```

Seguimiento:

```powershell
docker compose --env-file .env -p gestudio logs -f --tail 100 backend
```

Inspección del healthcheck:

```powershell
$backend = docker compose --env-file .env -p gestudio ps -q backend
docker inspect --format '{{json .State.Health}}' $backend
```

## Drill automatizado

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\verify-observability.ps1
```

El drill crea un proyecto Compose aislado y demuestra:

1. Docker disponible;
2. PostgreSQL y backend healthy;
3. liveness `UP`;
4. readiness `UP`;
5. ausencia de detalles internos en health;
6. Prometheus rechazado sin token;
7. Prometheus rechazado con token incorrecto;
8. Prometheus accesible con token exacto;
9. métricas JVM y de proceso presentes;
10. los siete contadores obligatorios del control plane presentes aun en cero;
11. request ID seguro propagado;
12. request ID ausente generado;
13. request ID inseguro reemplazado;
14. línea HTTP correlacionada;
15. secretos conocidos ausentes de logs;
16. cleanup sin contenedores, redes ni volúmenes residuales.

Workflow permanente:

```text
Observability verification
```

## Diagnóstico

### Liveness DOWN

Interpretación: el proceso no debe seguir recibiendo tráfico y normalmente debe reiniciarse.

Acciones:

1. capturar logs y estado del contenedor;
2. registrar SHA e imagen exactos;
3. comprobar memoria, disco y errores fatales;
4. reiniciar una vez;
5. si vuelve a fallar, retirar la versión o ejecutar rollback compatible.

### Readiness DOWN con liveness UP

Interpretación: el proceso vive, pero no debe recibir tráfico.

Acciones:

1. comprobar PostgreSQL;
2. comprobar espacio en disco;
3. revisar migraciones Flyway;
4. revisar pool de conexiones;
5. no forzar el servicio a healthy mediante un healthcheck de puerto;
6. restaurar la dependencia o retirar temporalmente la instancia.

### Prometheus 401

Comprobar:

1. nombre exacto de la cabecera;
2. token configurado en backend;
3. token configurado en scraper;
4. ausencia de espacios agregados;
5. rotación reciente del secreto.

No habilitar Prometheus públicamente para resolver el incidente.

### Errores HTTP sostenidos

Usar:

- `http_server_requests_seconds_count`;
- `http_server_requests_seconds_sum`;
- códigos de estado;
- `X-Request-ID`;
- logs del backend;
- estado de PostgreSQL.

El request ID debe ser el vínculo entre soporte, respuesta HTTP y logs.

## Umbrales iniciales recomendados

Estos valores son una base operativa, no un SLA contractual:

| Señal | Advertencia | Crítica |
|---|---:|---:|
| readiness DOWN | 30 segundos | 2 minutos |
| respuestas 5xx | >1% durante 5 min | >5% durante 5 min |
| p95 HTTP | >1 segundo durante 10 min | >3 segundos durante 5 min |
| uso de heap | >80% durante 10 min | >90% durante 5 min |
| espacio libre | <20% | <10% |
| PostgreSQL no disponible | inmediata | >1 minuto |

Los umbrales deben revisarse con carga real antes de producción.

## Criterio de rollback

Considerar rollback cuando:

- readiness no se recupera después de corregir dependencias;
- la tasa de 5xx aparece inmediatamente después de un despliegue;
- la nueva versión agota memoria o conexiones;
- Flyway es compatible con el artefacto anterior aprobado;
- existe backup previo válido.

Usar:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\ops\rollback-backend.ps1 `
  -TargetImage '<imagen-aprobada>' `
  -EnvFile .\.env `
  -ProjectName gestudio `
  -ConfirmRollback
```

Nunca ejecutar down migrations para adaptar la base a una imagen vieja.

## Límites para staging y producción

El gate técnico se considera cerrado únicamente cuando código, pruebas y drill están verdes. Para habilitar staging todavía se requiere:

- ambiente real;
- scraper Prometheus o equivalente;
- almacenamiento y retención;
- alertas entregadas a responsables identificados;
- TLS y segmentación de red;
- secret manager;
- prueba de rotación del token;
- ventana y procedimiento de incidentes;
- evidencia de carga y ajuste de umbrales.

Producción permanece en `NO-GO` hasta una autorización separada.

## Evidencia histórica 2026-07-22

`pwsh -NoProfile -File .\scripts\ops\verify-observability.ps1` terminó con
8/8 pasos, 0 fallos, exit 0 y 39,8 s. Validó readiness/liveness, Prometheus
fail-closed y autenticado, request ID generado/saneado, redacción, perfil hostil
y cleanup sin contenedores, redes o volúmenes residuales.

El script, las métricas del control plane, las migraciones y el runtime cambiaron
después de esa fecha. La corrida se conserva como antecedente y no certifica el
árbol ni el SHA actuales; el drill debe repetirse en un proyecto Compose aislado.
