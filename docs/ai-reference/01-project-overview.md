# Visión general del proyecto

> Estado: CONFIRMADO  
> Última revisión: 2026-07-24  
> Fuentes principales: `../../README.md`, `../../AGENTS.md`, `../project-status-and-handoff.md`

## Propósito

Gestudio centraliza la operación de una academia o institución educativa/deportiva: padrón de alumnos y profesores, oferta de disciplinas, inscripciones, asistencia, liquidación financiera, cobranzas, caja, inventario, reportes y administración de accesos.

## Problema que resuelve

Evita operar cada proceso en herramientas separadas y conserva relaciones entre:

- alumno, inscripción, disciplina y profesor;
- vigencias económicas, cargos y aplicaciones de pago;
- pago, recibo, movimiento de caja, crédito y stock;
- usuario, rol y permiso;
- operación diaria, trazabilidad y recuperación.

## Actores confirmados

Los roles demostrativos y su contrato observado son:

| Rol | Alcance observado |
|---|---|
| `SUPERADMIN` | Acceso total, usuarios y roles |
| `DIRECCION` | Gestión y usuarios; roles denegados |
| `ADMINISTRADOR` | Gestión y usuarios; roles denegados |
| `SECRETARIA` | Alumnos, inscripciones, asistencia, pagos, caja y reportes |
| `CAJA` | Alumnos, pagos, caja, stock y métodos de pago en lectura |

La autorización no depende del nombre del rol: el backend suma permisos activos de roles activos y exige `PERM_APP_ACCESO` más el permiso funcional.

## Alcance funcional

1. **Identidad y seguridad**: login, refresh, logout, usuarios, roles y permisos.
2. **Académico**: alumnos, profesores, disciplinas, salones, horarios e inscripciones.
3. **Asistencia**: planillas mensuales y registros diarios.
4. **Economía**: tarifas por vigencia, condiciones económicas, matrículas, mensualidades y cargos.
5. **Cobranza**: pagos, aplicaciones, crédito, recibos y anulaciones.
6. **Caja e inventario**: egresos, movimientos, stock, ventas y reversiones.
7. **Comunicación y reportes**: cumpleaños, PDF y reportes de liquidación.
8. **Integración**: exportación mínima firmada de estudiantes a Jere Platform.
9. **Operación**: demo, certificación, manual visual, observabilidad y recuperación.

## Límites confirmados

- Una academia por deployment; no existe un tenant de negocio seleccionable por usuario.
- Jere Platform usa transporte administrativo/manual; no hay push automático.
- Observaciones de profesores tienen controlador, pero la familia completa está denegada.
- Staging y producción no se consideran desplegados por el contenido del repositorio.
- SMTP real, TLS, DNS, secret manager, monitoreo externo y retención dependen del ambiente.
- Flyway no ofrece down migrations; rollback de aplicación exige compatibilidad con el esquema actual.

## Estado general

El handoff del 22-07-2026 registra validaciones locales completas sobre un SHA anterior al HEAD documental actual. El `main` remoto inspeccionado no tenía PRs abiertos y ya contenía las correcciones posteriores del manual visual. Ver [27-remote-state-and-release-evidence.md](27-remote-state-and-release-evidence.md).

## Terminología central

Consultar [20-glossary.md](20-glossary.md). Los términos sensibles para cambios son **vigencia**, **liquidación**, **aplicación de pago**, **reversión**, **baja lógica**, **checkpoint**, **permiso funcional** y **fecha de negocio**.
