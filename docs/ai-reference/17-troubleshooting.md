# Troubleshooting

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: runbooks y condiciones de fallo codificadas

## Casos confirmados o preventivos

| Síntoma | Causa probable | Diagnóstico | Acción | Validación |
|---|---|---|---|---|
| Backend no inicia | Java distinto de 21 | `java -version`, `JAVA_HOME` | corregir JDK | `status.ps1` |
| Docker falla | Engine detenido | `docker info` | iniciar Docker Desktop | `docker compose ps` |
| Puerto ocupado | colisión local | revisar `.env` y listeners | cambiar puerto | health/SPA |
| Flyway checksum | migración aplicada editada | historial y Git diff | restaurar archivo; crear nueva migración | limpia + upgrade |
| Hibernate valida mal | esquema/config desalineado | logs datasource/Flyway | corregir config/migración | `clean verify` |
| Bootstrap falla tras crear admin | flag sigue activo | propiedades de arranque | apagar flag y recrear | login |
| Tarifa histórica ausente | falta vigencia efectiva | API/DB de tarifas | crear vigencia, no usar legacy | liquidación |
| Pago conflicto | idempotencia/sobreaplicación | error code estándar | corregir request/estado | prueba PostgreSQL |
| Stock conflicto | cantidad insuficiente | `INSUFFICIENT_STOCK` | ajustar stock o venta | movimiento/cargo |
| Refresh 401 | cookie/token inválido | cookie, Origin, sesión | volver a autenticar | perfil |
| Refresh 403 | Origin no permitido | CORS config | agregar origen autorizado | preflight + refresh |
| Prometheus 401 | token ausente/repetido | headers | enviar exactamente uno | HTTP 200 |
| Recibo 404 | metadata o archivo ausente | DB `storageKey` y receipts path | restaurar/conciliar | descarga |
| Restore rechazado | destino/confirmación insegura | salida del script | usar base alternativa y parámetros explícitos | drill 12/12 |
| Rollback rechazado | imagen no conoce esquema | metadata Flyway | usar imagen compatible | drill 8/8 |
| Demo `Status` falla | imagen/hash/Flyway/seed obsoleto | detalle de freshness | ejecutar `Start`, no `Reset` | `Status` exit 0 |
| Manual no reanuda | captura previa faltante | nombre y directorio | restaurar captura o reiniciar recorrido | validador manual |
| SPA rompe al refrescar | fallback/headers | checks Nginx | corregir configuración | `npm test`, build |
| API nueva devuelve 403 | ruta sin política | test dinámico | declarar permiso | Security test |

## Logs y evidencia

```powershell
docker compose --env-file .env -p gestudio ps
docker compose --env-file .env -p gestudio logs --tail 200 db backend frontend
```

Usar `X-Request-ID` para correlación. No compartir cuerpos, tokens ni secretos.

## Regla

Los casos no observados como incidentes se consideran preventivos. No ejecutar limpieza destructiva como “solución” predeterminada.
