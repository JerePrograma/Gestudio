# Invariantes de negocio

## Seguridad

- Sólo login, refresh y preflight son públicos.
- Perfil propio requiere autenticación; toda ruta operativa requiere
  `PERM_APP_ACCESO` más su permiso funcional explícito y cualquier `/api/**`
  desconocida queda en `denyAll`.
- Access y refresh no son intercambiables; usuario/rol inactivo invalida el JWT.
- 401, 403, validación, conflicto, 404 y 500 comparten el contrato `ApiErrorResponse`.

## Dinero y obligaciones

- Todo dinero autoritativo es decimal exacto con escala explícita.
- `Cargo.importeOriginal` no se muta; saldo = original - aplicaciones activas -
  consumos de crédito aplicados.
- Un pago no sobreaplica cargos. El excedente sólo crea crédito si el request lo
  autoriza explícitamente.
- Anular compensa aplicaciones y ledgers; no borra historia.
- La caja calcula agregados en PostgreSQL y no suma una colección hidratada.

## Idempotencia y concurrencia

- Pago, egreso, venta y crédito comparan key única y request hash determinista.
- Misma key/mismo payload devuelve el resultado existente; misma key/payload
  distinto devuelve conflicto.
- Locks financieros se adquieren en orden estable; mensualidad y matrícula se
  protegen por locks de conjunto y uniques naturales.
- Un recibo por pago y un trabajo por pago/tipo; dos workers no reclaman la misma
  fila y un lease vencido se recupera.

## Historia

- No se eliminan físicamente pagos, aplicaciones, cargos, mensualidades,
  matrículas, inscripciones, asistencias, caja, crédito o movimientos de stock.
- Las descripciones son snapshots visuales, nunca claves foráneas.
- PDF/email no participan de la transacción financiera.
