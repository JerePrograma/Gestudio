# Datos y persistencia

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: entidades JPA, migraciones Flyway, `AGENTS.md`, runbooks

## Tecnología

PostgreSQL 15, Spring Data JPA/Hibernate y Flyway. `open-in-view=false`; el mapeo a DTO debe ocurrir dentro del caso de uso. `ddl-auto=validate` es obligatorio; no usar `update`.

## Migraciones

- Baseline canónico: `V1__canonical_schema.sql`.
- V4: `V4__cargo_liquidations_and_events.sql`.
- V5: `V5__base_roles_permissions_seed.sql`.
- V6: catálogo de 32 permisos y matrices base.
- V7: snapshots/páginas del exportador Jere Platform.
- Los nombres y contenido de V2/V3 deben consultarse directamente en el directorio.
- Todas las migraciones publicadas son inmutables y forward-only.
- La siguiente evolución debe ser contigua; los scripts derivan versión y manifiesto dinámicamente.

## Entidades persistentes inspeccionadas

### Académico

`Alumno`, `Profesor`, `Disciplina`, `DisciplinaHorario`, `Salon`, `Inscripcion`, `AsistenciaMensual`, `AsistenciaAlumnoMensual`, `AsistenciaDiaria`, `ObservacionProfesor`.

### Financiero

`TarifaDisciplina`, `CondicionEconomicaInscripcion`, `Matricula`, `Mensualidad`, `Cargo`, `Pago`, `AplicacionPago`, `MetodoPago`, `MovimientoCredito`, `MovimientoCaja`, `Egreso`, `Bonificacion`, `Recargo`.

### Inventario y documentos

`MovimientoStock`, `VentaStock`, `Recibo`, `ReciboPendiente`, `Concepto`, `SubConcepto`, `Notificacion`.

### Seguridad

`Usuario`, `Rol`, `Permiso`, `RefreshSession`.

## Restricciones conocidas

`TratadorDeErrores` reconoce constraints para:

- inscripción activa duplicada;
- mensualidad o matrícula del período duplicada;
- vigencia económica duplicada;
- monto/aplicación inválidos;
- crédito o stock insuficiente;
- idempotency key duplicada.

Los nombres exactos de constraints son contrato operativo indirecto porque determinan códigos API.

## Transacciones

- Liquidación: cargo + snapshot.
- Pago: pago + aplicaciones + movimientos/recibo según caso.
- Exportación Jere: header + páginas + bytes/firma.
- Anulaciones/reversiones: registros compensatorios y estados.
- Side effects externos no deben dejar persistencia parcial.

## Archivos

Recibos se guardan fuera de PostgreSQL; DB conserva `storageKey`. `ReciboPathResolver` restringe rutas existentes al directorio configurado. Backup incluye DB y recibos con manifiesto SHA-256.

## Evolución segura

1. Inspeccionar todas las migraciones y entidades afectadas.
2. Reportar inconsistencias antes de normalizar.
3. Añadir migración contigua con precondiciones, backfill, índices y constraints.
4. Probar base limpia y upgrade soportado.
5. Ejecutar reconciliación y smoke.
6. Revisar compatibilidad de rollback de aplicación.

## Riesgos de integridad

Cascadas, `orphanRemoval`, colecciones administradas, vigencias solapadas, borrados históricos, duplicados, precisión monetaria, filesystem de recibos y retención de snapshots.
