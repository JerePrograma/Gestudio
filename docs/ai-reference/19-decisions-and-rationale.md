# Decisiones y rationale

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: `AGENTS.md`, código, pruebas y ADR/documentación vigente

| Decisión | Evidencia | Motivo/consecuencia | Certeza |
|---|---|---|---|
| Monolito modular por capas | `AGENTS.md`, paquetes | menor complejidad operativa; no microservicios | CONFIRMADO |
| Autorización deny-by-default | `SecurityConfigurations` | ruta omitida no queda pública | CONFIRMADO |
| APP + permiso funcional | config y tests | separar acceso general de capacidad | CONFIRMADO |
| Inventario dinámico de API | Security test | detectar endpoints sin política | CONFIRMADO |
| JWT access + refresh cookie | auth controller | access para API y refresh protegido | CONFIRMADO |
| Validar Origin en refresh/logout | auth controller | mitigar abuso de cookie cross-origin | CONFIRMADO |
| Flyway forward-only | `AGENTS.md`, runbooks | evitar down migrations inseguras | CONFIRMADO |
| Baseline canónico V1 | migraciones/docs | eliminar historia legacy no soportada | CONFIRMADO |
| Vigencias y snapshot de liquidación | tarifas/V4 | reproducibilidad histórica | CONFIRMADO |
| Reversión/anulación explícita | pagos/stock/egresos | conservar auditoría | CONFIRMADO |
| `PageResponse` gradual | controladores/handoff | estabilizar paginación sin ruptura total | INFERIDO |
| Email no-op fuera de prod | perfiles | evitar envíos accidentales | CONFIRMADO |
| Scheduler por property | `ScheduledTasks` | desactivar efectos en dev/test | CONFIRMADO |
| Jere Platform por pull administrativo | integración v1 | evitar acoplamiento y push automático | CONFIRMADO |
| Una academia por deployment | integración v1 | no introducir multitenancy ficticio | CONFIRMADO |
| Bytes firmados persistidos | exportador | replay determinista | CONFIRMADO |
| Demo y certificación fuera de datos reales | scripts/docs | seguridad y repetibilidad | CONFIRMADO |
| Imágenes con metadata | CI | trazabilidad y freshness | CONFIRMADO |

## Alternativas descartadas explícitamente

Microservicios, event sourcing, CQRS global, mensajería distribuida, interfaces por cada servicio, duplicación sistemática dominio/JPA, `ddl-auto=update`, down migrations y cálculos financieros en frontend.

## Motivos no confirmados

Cuando una motivación no está escrita —por ejemplo, por qué ciertos endpoints legacy devuelven 200 o texto— se preserva como compatibilidad, no se inventa su rationale.
