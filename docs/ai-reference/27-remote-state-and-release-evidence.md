# Estado remoto y evidencia de release

> Estado: CONFIRMADO  
> Última revisión: 2026-07-24  
> Fuentes principales: GitHub remoto, historial, PRs y `../project-status-and-handoff.md`

## Repositorio

- Repositorio: `JerePrograma/Gestudio`.
- Rama predeterminada y de publicación: `main`.
- Permisos disponibles durante la inspección: lectura y escritura.
- Repositorio no archivado.
- HEAD remoto inspeccionado antes de esta actualización: `af099c880b1f18db018111e8720fb5c2bcd9280a`.
- Commit anterior funcional: `0c96c8e55b3af891f78641cd449997e64a3adcc4`.

## Unificación

No había pull requests abiertos. Los PRs de implementación/release relevantes estaban cerrados y mayormente fusionados; un PR documental antiguo (`#17`) estaba cerrado sin merge y no se incorporó porque no representa trabajo abierto ni revisado contra el HEAD actual.

No se mezclaron ramas por nombre ni se reescribió historial. `main` se trató como fuente única. El conector de búsqueda de ramas no devolvió un inventario fiable, por lo que no se afirma que no existan refs remotas secundarias; sí se confirma que no había PRs abiertos hacia `main`.

## Estado de CI del HEAD base

La consulta de status checks y workflow runs asociada a `af099c...` no devolvió ejecuciones. Por tanto:

- el commit existe en remoto;
- no se puede afirmar CI verde para ese commit documental;
- la evidencia funcional vigente proviene del release validado y de los tests/config inspeccionados.

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

El historial posterior incluye certificación API, correcciones de conceptos/subconceptos, launcher/demo remota, generador de manual y reanudación de capturas. Esta documentación se basa en el HEAD remoto actual, pero no convierte la evidencia del SHA de release en validación automática de cada commit posterior.

## Auto-referencia Git

El SHA del commit que contiene este documento se informa fuera del propio commit. Incrustarlo dentro generaría un contenido distinto y, por tanto, otro SHA.

## Próximo criterio de release

Ejecutar CI y certificación integral sobre el nuevo HEAD; luego registrar runs, resultados y SHA en un informe externo o commit posterior.
