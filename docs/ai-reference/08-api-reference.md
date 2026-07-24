# Referencia API

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: controladores `@RestController`, `README.md`

## Base

Local: `http://localhost:8080/api`; demo: `http://localhost:18080/api`.

## Familias confirmadas

Autenticación, alumnos, usuarios, roles, permisos, profesores, disciplinas, salones, inscripciones, asistencias, tarifas, condiciones, matrículas, mensualidades, cargos, pagos, caja, créditos, egresos, conceptos, stock, reportes, notificaciones y exportación Jere Platform.

## Operativos

| Método | Ruta | Auth | Resultado |
|---|---|---|---|
| GET | `/actuator/health/liveness` | pública | salud |
| GET | `/actuator/health/readiness` | pública | preparación |
| GET | `/actuator/prometheus` | token de métricas | 200 o 401 |

## Restricción

Extraer rutas exactas de `@RequestMapping`/`@*Mapping`; no inferirlas por nombre de controlador.