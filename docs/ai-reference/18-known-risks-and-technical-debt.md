# Riesgos conocidos y deuda técnica

> Estado: CONFIRMADO  
> Última revisión: 2026-07-26  
> Fuentes principales: código, pruebas, handoff, configuración e issues de GitHub

## Registro priorizado

| Prioridad | Hallazgo | Evidencia | Impacto | Recomendación |
|---|---|---|---|---|
| Alta | Producción no acreditada | handoff / [#23](https://github.com/JerePrograma/Gestudio/issues/23) | seguridad/operación | validar TLS, secretos, storage, monitorización y restore |
| Alta | Transporte Jere no desplegado | integración v1 / [#25](https://github.com/JerePrograma/Gestudio/issues/25) | integración | smoke autorizado y runbook operativo |
| Alta | SMTP real no probado | handoff / `EmailService` / [#23](https://github.com/JerePrograma/Gestudio/issues/23) | comunicación | prueba controlada y observabilidad |
| Alta | Controller de observaciones existe pero está denegado | Security config | superficie dormante | decidir retirar o habilitar con diseño/pruebas |
| Media | GET cumpleaños genera estado/efecto | `NotificacionControlador` | semántica/idempotencia | separar comando/consulta o documentar explícito |
| Media | Job cumpleaños comenta 08:00 pero cron ejecuta 10:00 | `ScheduledTasks` | operación | corregir comentario o cron tras decisión |
| Media | SMTP y append IMAPS no son atómicos | `EmailService` | duplicado/estado Sent | definir semántica y reintento del append |
| Media | Respuestas y status HTTP heterogéneos | controladores legacy | consumidores | inventario y versión gradual |
| Media | Dos rutas de baja de método de pago | `MetodoPagoControlador` | ambigüedad | deprecar una con compatibilidad |
| Media | Selector de subconcepto por ID o descripción | `ConceptoControlador` | ambigüedad | mantener test y plan de deprecación |
| Media | Permisos catalogados sin matcher funcional observado | `AUDITORIA_SEGURIDAD_LEER`, `TARIFAS_HISTORICAS` | gobernanza | confirmar reserva o implementar uso |
| Media | Retención de snapshots Jere pendiente | docs integración | crecimiento/privacidad | política operativa |
| Media | Monitoreo externo/alertas ausentes del repo | handoff / [#24](https://github.com/JerePrograma/Gestudio/issues/24) | detección | desplegar plataforma, alertas y responsables |
| Media | Dependencias mayores incompatibles disponibles | `npm outdated` / [#26](https://github.com/JerePrograma/Gestudio/issues/26) | mantenimiento | migración separada con regresión completa |
| Baja | Imports duplicados y comentarios legacy | varios controladores | mantenibilidad | limpieza enfocada con tests |
| Baja | Logging de nombre de alumno a INFO | `AlumnoControlador` | PII | preferir ID/resultado |
| Baja | `String` para saldo de crédito | `CreditoControlador` | tipo de contrato | DTO versionado |
| Baja | Manejo de errores local en inscripción/PDF | controladores | inconsistencia | migrar gradualmente a advice |

## Riesgo cerrado desde 2026-07-26

`API-PAGE-001` quedó cerrado: los controladores paginados exponen `PageResponse<T>`
y el adaptador común tiene prueba unitaria. `PageImpl` permanece como detalle
interno de Spring Data, no como contrato JSON público.

## Vulnerabilidades

El release registró auditoría npm sin vulnerabilidades después de actualización controlada de lockfile. Eso es evidencia fechada; debe reejecutarse. No se detectaron ni documentaron valores secretos en esta base.

## Riesgos estructurales

- Contratos RBAC duplicados deliberadamente entre config y test: reducen omisiones, pero requieren actualización coordinada.
- Rollback acoplado al historial Flyway.
- Recibos repartidos entre DB y filesystem.
- Seed/demo tiene conteos contractuales que deben cambiar coordinadamente.
- `.kiro` puede inducir refactors incorrectos si se lee sin `AGENTS.md`.

## Deuda no confirmada cuantitativamente

Cobertura JaCoCo/Vitest actual, volumen de datos, performance con páginas máximas, índices reales y tiempo de jobs en producción.
