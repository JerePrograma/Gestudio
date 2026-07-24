# Modelo de dominio

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: `README.md`, controladores backend, migraciones Flyway

## Conceptos confirmados

Alumno, profesor, usuario, rol, permiso, disciplina, salón, inscripción, asistencia diaria/mensual, tarifa, condición económica, matrícula, mensualidad, cargo, liquidación, pago, método de pago, crédito, bonificación, recargo, egreso, caja, concepto, subconcepto, stock, recibo, reporte, notificación y observación.

## Reglas críticas

- Tarifas y condiciones se resuelven por vigencia.
- Cada cargo conserva snapshot histórico en `cargo_liquidaciones`.
- Fuentes financieras legacy son rechazadas.
- Roles/permisos operan fail-closed.
- V1–V7 son inmutables y forward-only.
- `GESTUDIO_STUDENT` contiene ID, nombre visible y activo.

## INFERIDO

Alumno ↔ inscripción ↔ disciplina; alumno ↔ asistencia; alumno ↔ cargos/pagos; rol ↔ permisos; caja ↔ pagos/egresos. Confirmar cardinalidades en entidades y migraciones.