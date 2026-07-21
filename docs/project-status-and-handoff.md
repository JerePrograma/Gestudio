# Estado del proyecto y handoff

> Fecha: 21 de julio de 2026  
> Rama operativa: `main`  
> Merge funcional GATE-2: `7d8872a59acb923fae664f806b01e459f372dc1c`  
> Estado externo: **NO-GO para demo humana, demo comercial, staging y producción**

Git y GitHub son autoridad. El backlog vigente está en `docs/codex/gestudio-release-hardening/12_ESTADO_ACTUAL_Y_BACKLOG.md` y la evidencia de esta iteración en `21_GATE_2_UX_OPERATIVA_2026-07-21.md`.

## Capacidades integradas

| Área | Estado |
|---|---|
| RBAC fail-closed y 32 permisos | integrado/probado |
| Finanzas por vigencia e idempotencia | integrado/probado |
| Flyway V1-V7 | integrado/probado |
| Demo automatizada | PASS sobre SHA `52175e49...` |
| Backup/restore | PASS técnico |
| Rollback | PASS técnico |
| Observabilidad source-owned | PASS técnico, PR `#20` |
| Emisor Jere Platform | integrado y apagado |
| Receptor Jere Platform | integrado mediante PR `#60` |
| Transporte desplegado | no demostrado |
| Búsqueda humana de alumnos | integrada mediante PR `#21` |
| Pagos sin ID técnico visible | integrado mediante PR `#21` |
| Demo humana | pendiente |
| Staging/producción | no provistos/no autorizados |

## Evidencia final PR #21

SHA candidato: `52175e49b03a2fc7b4e1c729a0f8a4a7f1c30113`.

- backend: **172/172 PASS**;
- frontend: **142/142 PASS**;
- lint: PASS;
- build frontend: PASS;
- Scope All: PASS;
- Compose local/productivo: PASS;
- imágenes backend/frontend: PASS;
- smoke GATE: PASS;
- smoke CI aislado: PASS;
- seed doble: PASS;
- hilos pendientes: ninguno;
- merge protegido: `7d8872a59acb923fae664f806b01e459f372dc1c`.

## Correcciones GATE-2 integradas

1. Alumnos se buscan por nombre, apellido, ambos órdenes, documento y fragmentos, sólo activos.
2. Pagos deja de exponer el ID interno como referencia comercial y usa fecha/monto en el nombre accesible.
3. La primera ejecución CI detectó una colisión de sesión causada por un segundo truncate en la prueba; se corrigió sin tocar lógica productiva.
4. La documentación dejó de presentar observabilidad `#20` o `jere-platform#59` como pendientes.

## Recorridos humanos

| Rol | Estado |
|---|---|
| SUPERADMIN | PENDIENTE |
| DIRECCION | PENDIENTE |
| ADMINISTRADOR | PENDIENTE |
| SECRETARIA | PENDIENTE |
| CAJA | PENDIENTE |

La ausencia de navegador operativo en esta ejecución impide cerrar accesibilidad, responsive y operación visual. Una suite verde no equivale a demo humana aprobada.

## Operación local

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\codex\setup.ps1

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\codex\validate.ps1 `
  -Scope All

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Start
```

Estado y detención:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Status

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Stop
```

Runbook: `docs/operations/local-runbook.md`.

## Próximos pasos exactos

1. levantar la demo con datos sintéticos;
2. ejecutar `SUPERADMIN` completo;
3. ejecutar `DIRECCION` y probar URL directas prohibidas;
4. ejecutar `ADMINISTRADOR`;
5. ejecutar `SECRETARIA`: alumno → inscripción → asistencia;
6. ejecutar `CAJA`: cargo → pago → recibo → caja → stock/reversión;
7. repetir en 360, 390, 768 y escritorio;
8. validar foco, tabulación, labels, modales, contraste y errores;
9. registrar evidencia con SHA exacto;
10. mantener staging y producción en NO-GO hasta que existan ambientes y autorización.

## Riesgos abiertos

- GATE-2 humano no cerrado;
- accesibilidad y móvil sin evidencia completa;
- búsqueda amplia puede requerir optimización futura por volumen;
- políticas de backup, imágenes y secretos incompletas;
- monitoreo externo no provisto;
- staging inexistente;
- producción no autorizada;
- transporte Jere Platform no desplegado.
