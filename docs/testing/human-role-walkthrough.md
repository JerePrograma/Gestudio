# Recorrido real de los cinco roles

Estado: ejecutado y aprobado el 2026-07-22 sobre la demo recreada desde
volúmenes vacíos.

## Preparación reproducible

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Reset
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\demo-local.ps1 -Action Status
```

El lanzador solicita cinco claves por TTY. En automatización se usa el mecanismo
no interactivo del entorno efímero; las claves no se imprimen, no se copian a
archivos y no se versionan. Playwright se ejecutó como herramienta externa, sin
agregar una dependencia al producto. Screenshots y trazas quedaron fuera del
repositorio.

## Contrato común comprobado

Para cada usuario se verificó:

1. login real y rol esperado;
2. menú visible y opciones ocultas;
3. navegación a rutas permitidas y redirección a `/unauthorized` en denegadas;
4. estado con datos y búsqueda sin resultados;
5. foco conservado al filtrar;
6. primer Tab sobre `Saltar al contenido`;
7. refresh del navegador con sesión preservada;
8. modal `Cumpleañeros de hoy` con sólo Sofía Benítez activa;
9. viewport de escritorio 1440×1000 y móvil 390×844;
10. cierre de sesión desde la interfaz y retorno a `/login`.

## Resultado por rol

| Rol | Permitido observado | Denegado/oculto observado |
|---|---|---|
| `SUPERADMIN` | disciplinas, reporte por disciplina con datos, usuarios y roles | sin denegaciones del guion |
| `DIRECCION` | disciplinas, reporte, usuarios y caja | `/roles` |
| `ADMINISTRADOR` | disciplinas, reporte, usuarios y caja | `/roles` |
| `SECRETARIA` | alumnos, inscripciones, asistencia, reporte, pagos y caja | usuarios, roles y egresos |
| `CAJA` | alumnos, pagos, caja, stock y métodos de pago | inscripciones, reporte, profesores, usuarios y roles; alta de producto oculta |

El reporte de `SUPERADMIN` mostró a Sofía en Ballet, lo que cubre un estado con
datos reales. El filtro de alumnos también cubrió el estado vacío sin desmontar
el input ni perder foco. Disciplinas y horarios se visualizaron sin duplicados.

## Consola y red

La ejecución headed final terminó 1/1 en 16,0 s (89,3 s incluyendo la recreación
de la demo). No hubo errores inesperados de consola ni red. Antes de cada login
apareció un `POST /api/login/refresh` con
`401`; son cinco respuestas esperadas por el contrato de sesión anónima y no se
clasifican como regresión.

## Repetición

La prueba externa debe apuntar a `http://localhost:18081` y recibir las claves
por variables de proceso o TTY. Nunca se deben incrustar claves en el spec,
capturas, traces o comandos versionados. Tras la evidencia:

```powershell
docker compose -p gestudio-demo-local down --volumes --remove-orphans
```

Ese comando afecta únicamente al proyecto demo identificado.
