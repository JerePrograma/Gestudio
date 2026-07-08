# Smoke local de baseline canónica

## Alcance

`scripts/smoke-local.ps1` valida V1–V5 desde una base vacía en un proyecto Docker
Compose único. Genera en memoria credenciales PostgreSQL, JWT y un usuario
temporal con rol efectivo `SUPERADMIN`.

El stack usa puertos host libres, red propia, volumen PostgreSQL propio y volumen
de recibos propio. El puerto PostgreSQL se publica sólo para probar el aislamiento:
el script nunca lo usa y todas las consultas se ejecutan con `docker compose exec
-T db`.

## Ejecución

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
```

Opciones:

- `-SkipBuild`: reutiliza las imágenes `gestudio-backend:smoke-check` y
  `gestudio-frontend:smoke-check`.
- `-VerboseHttp`: muestra método, URL y status; nunca bodies ni tokens.
- `-KeepStack`: conserva el proyecto para diagnóstico y muestra sólo comandos
  seguros para inspeccionarlo o eliminarlo.

El default siempre ejecuta `docker compose -p <proyecto> down --volumes
--remove-orphans` en `finally` y comprueba por labels que no quedaron
contenedores, volúmenes ni redes. El archivo de variables vive en `%TEMP%`, se
elimina al finalizar y las variables de proceso originales se restauran.

## Contratos validados

Por API:

- 401 anónimo, login, perfil, refresh por cookie HttpOnly y separación
  access/refresh;
- recreación del backend con bootstrap deshabilitado y un solo usuario;
- salón, profesor, disciplina, subconcepto, concepto y método de pago;
- alumno, listado/búsqueda, inscripción sin duplicado y matrícula automática;
- cargo, pago parcial, retry idempotente, conflicto y pago total;
- caja, egreso/reversión, stock, venta idempotente y reversión;
- persistencia completa después de otro reinicio.

Por SQL de solo lectura:

- exactamente cinco migraciones Flyway exitosas, V1–V5;
- rol/usuario bootstrap activo, vínculo en `usuario_roles`, BCrypt y ninguna
  contraseña plana;
- pagos, aplicaciones, caja, stock y outbox sin duplicados;
- saldos no negativos, FKs y relaciones usadas sin huérfanos;
- auditorías canónicas `03-orphans.sql`, `04-financial-inconsistencies.sql` y
  `05-state-inconsistencies.sql` en cero.

La respuesta de venta devuelve el cargo pero no el ID de `ventas_stock`; el
script lee ese ID para invocar el endpoint real de reversión. No escribe datos de
negocio por SQL.

## Outbox y SMTP

Cada pago crea un `recibo` y un trabajo `GENERAR_Y_ENVIAR` único y pendiente.
Runtime no ofrece un disparador HTTP ni un worker operativo para procesarlo; el
smoke valida creación/unicidad y la suite PostgreSQL cubre claim, lease y
concurrencia. No se configura SMTP/IMAP y no se promete entrega exactly-once.
