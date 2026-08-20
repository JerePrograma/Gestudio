# Estado remoto y evidencia de release

> Estado: CONFIRMADO  
> Última revisión: 2026-07-26  
> Fuentes principales: GitHub remoto, historial, issues, PRs y `../project-status-and-handoff.md`

> **Evidencia histórica — reemplazada.** Este archivo conserva la inspección
> remota del 2026-07-26. No describe V12/B12, el control plane, el working tree
> actual ni CI del candidato. La matriz viva está en
> [`GESTUDIO_FINALIZACION_SUPERADMIN_MEGAPROMPT.md`](../../GESTUDIO_FINALIZACION_SUPERADMIN_MEGAPROMPT.md#estado-vivo).

## Repositorio

- Repositorio: `JerePrograma/Gestudio`.
- Rama predeterminada y de publicación: `main`.
- Permisos disponibles durante la inspección: lectura y escritura.
- Repositorio público y no archivado.
- HEAD remoto inspeccionado antes de esta actualización: `90a68b6c96660ea58facbcbc558d856029bb1d98`.
- No se creó ninguna rama ni se reescribió historial.

## Trabajo remoto gestionado

No hay pull requests abiertos. `main` se mantiene como fuente única de publicación.

Issues abiertos y asignados:

- `#23`: staging y promoción productiva (`P0`, `OPS-ENV-001`).
- `#24`: observabilidad operativa y alertas (`P1`).
- `#25`: smoke desplegado Gestudio → Jere Platform (`P1`, `INT-001`).
- `#26`: dependencias mayores del frontend (`P3`, `DEP-MAJOR-001`).

## Cambios remotos del 26-07-2026

- `SalonControlador` y `AsistenciaDiariaControlador` pasaron a `PageResponse<T>`.
- Se añadió `PageResponseTest` para el contrato estable y el caso vacío.
- `API-PAGE-001` quedó cerrado en las fuentes vigentes.
- README, handoff, backlog y referencias de IA quedaron sincronizados con los issues `#23`–`#26`.

## Estado de CI del HEAD base

La consulta de status checks no devolvió estados para `90a68b6c...` y la acción
disponible para workflow runs sólo expone ejecuciones asociadas a pull requests.
Por tanto:

- el commit existe en remoto;
- el workflow `ci.yml` está configurado para `push` a `main`;
- no se puede afirmar desde este conector que el HEAD haya terminado verde;
- tampoco existe evidencia de fallo en la consulta disponible.

## Evidencia de release 22-07-2026

SHA de código validado documentado: `c1f88c7a2e3118bbbd7f770135815056dc6fcebb`.

Resultados documentados:

- backend 203 tests sin fallos;
- frontend 149 Vitest + 2 contratos Nginx;
- npm audit sin vulnerabilidades;
- smoke 20/20;
- observabilidad 8/8;
- backup/restore 12/12;
- rollback 8/8;
- demo 914 filas y 5 logins;
- recorrido real de 5 roles en escritorio y móvil;
- imágenes non-root y metadata.

## Cambios posteriores al SHA validado

El historial posterior incluye certificación API, correcciones de conceptos/subconceptos, launcher/demo remota, generador de manual, reanudación de capturas y la normalización paginada de 2026-07-26. La documentación se basa en el HEAD remoto actual, pero no convierte la evidencia del SHA de release en validación automática de cada commit posterior.

## Auto-referencia Git

El SHA del commit que contiene este documento se informa fuera del propio commit. Incrustarlo dentro generaría un contenido distinto y, por tanto, otro SHA.

## Próximo criterio de release

Confirmar el resultado de GitHub Actions para el HEAD final y, después, ejecutar los criterios externos de `#23`, `#24` y `#25` en ambientes autorizados.
