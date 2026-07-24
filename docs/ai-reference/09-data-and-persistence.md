# Datos y persistencia

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: `backend/pom.xml`, migraciones, runbooks

## Confirmado

PostgreSQL 15, JPA/Hibernate y Flyway. V1–V7 forward-only e inmutables. Puerto local 5432; demo 15432.

## Datos críticos

Identidad/RBAC, alumnos/oferta, inscripciones/asistencias, finanzas/caja, inventario y snapshots.

## Evolución

Agregar migración nueva; nunca editar una aplicada. La imagen backend debe contener todas las migraciones ya aplicadas.

## Backup/restore

`scripts/ops` genera/verifica backup PostgreSQL/recibos con manifiesto SHA-256. No versionar dumps, backups ni recibos.

## Riesgos

Vigencias, constraints o snapshots pueden alterar historia financiera; revisar índices, FK, nulabilidad y transacciones.