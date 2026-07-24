# Decisiones y justificación

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: código, configuraciones y runbooks

1. **Monorepo backend/frontend/operación.** Consecuencia: validar contratos extremo a extremo.
2. **Flyway forward-only e inmutable.** Evolución solo mediante migración nueva.
3. **RBAC fail-closed.** Ausencia de permiso/configuración deniega.
4. **Snapshots financieros.** Conservan historia frente a cambios futuros.
5. **Prometheus con secreto separado.** No reutilizar JWT ni exponer al navegador.
6. **Jere Platform deshabilitada/pull-style.** Motivo probable INFERIDO: reducir acoplamiento y riesgo.

No presentar motivaciones no documentadas como CONFIRMADAS.