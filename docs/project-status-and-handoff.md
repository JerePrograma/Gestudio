# Estado del proyecto y handoff

> Fecha: 20 de julio de 2026  
> Rama operativa: `main`  
> Estado externo: **NO-GO para demo comercial, staging y producción**

Git y GitHub son autoridad si este documento queda desactualizado. El estado funcional vigente está en `docs/codex/gestudio-release-hardening/12_ESTADO_ACTUAL_Y_BACKLOG.md`.

## Snapshot

| Campo | Valor |
|---|---|
| Baseline inicial de la continuidad | `15481e38f0cf714607d0f7d5c3279a46315d7b5d` |
| Merge GATE-1B | `23546e025177ff810944808d468a60b91cf621eb` |
| Registro final GATE-1B | `ef4f9c31dab9a3dfce43f913177089f80ae0205a` |
| Merge integración V7 | `e1afec960ddeb72d61932a1eb1f4a83a65899540` |
| Scripts de recuperación en main | `b10ce3c0d6b218423fe513ed1c328d1d3abeb790` |
| PR de cierre operativo | `#18` |
| Siguiente gate | rollback forward-compatible |

## Capacidades integradas

| Área | Estado |
|---|---|
| RBAC y 32 permisos | integrado y probado |
| Liquidación por vigencia | integrado y probado |
| Flyway V1-V7 | integrado y probado |
| Demo automatizada | PASS |
| Emisor firmado de estudiantes | integrado, deshabilitado por defecto |
| Backup PostgreSQL/recibos | implementado y probado |
| Restore aislado | implementado y probado |
| Runbook local | publicado |
| Demo humana | pendiente |
| Rollback | pendiente |
| Observabilidad | pendiente |
| Staging/producción | no autorizados |

## Evidencia vigente

- backend: 162/162 PASS;
- frontend: 142/142 PASS;
- lint/build: PASS;
- imágenes: PASS;
- Scope All: PASS;
- smoke V1-V7: PASS;
- seed doble V1-V7: PASS;
- backup/restore drill: 9 pasos PASS, 0 fallos, `00:02:17`;
- recursos Docker residuales: ninguno.

## Integración Jere Platform

Gestudio materializa referencias mínimas `GESTUDIO_STUDENT` con:

- ID;
- nombre de visualización;
- activo;
- snapshots/páginas inmutables;
- SHA-256 y HMAC-SHA256;
- mapping explícito de tenant;
- secreto externo;
- permisos administrativos dobles.

La función está deshabilitada por defecto y no realiza transporte automático. El receptor multipágina sigue bloqueado por `JerePrograma/jere-platform#59`; no declarar operación end-to-end.

## Recuperación

Runbooks:

- `docs/operations/backup-restore.md`;
- `docs/operations/local-runbook.md`.

Scripts:

- `scripts/ops/backup-postgres.ps1`;
- `scripts/ops/restore-postgres.ps1`;
- `scripts/ops/verify-backup-restore.ps1`.

El restore seguro se prueba primero en una base alternativa. V1-V7 permanecen forward-only y no se ejecutan down migrations.

## Siguiente trabajo exacto

1. fusionar PR `#18` después de los workflows finales;
2. construir un artefacto de rollback que conserve V1-V7;
3. arrancar versión actual y crear datos sintéticos;
4. cambiar al artefacto rollback sin tocar la base;
5. verificar health, datos y Flyway V7;
6. volver al artefacto actual;
7. verificar nuevamente health y datos;
8. limpiar infraestructura descartable;
9. documentar resultados;
10. continuar con observabilidad mínima.

## Riesgos abiertos

- rollback no ensayado;
- observabilidad y alertas ausentes;
- GATE-2 y recorridos humanos incompletos;
- política real de backup sin destino, cifrado, retención ni RPO/RTO;
- ambiente staging inexistente;
- producción no autorizada.

## Restricciones

- no usar bases reales para drills;
- no editar V1-V7;
- no habilitar Profesor;
- no reintroducir STOMP;
- no habilitar Observaciones;
- no activar el emisor V7 como integración productiva;
- no desplegar.
