# Riesgos conocidos y deuda técnica

> Estado: CONFIRMADO  
> Última revisión: 2026-08-13
> Fuentes principales: código, pruebas, handoff, configuración e issues de GitHub

## Registro priorizado

| Prioridad | Hallazgo | Evidencia | Impacto | Recomendación |
|---|---|---|---|---|
| Alta | Control plane V12/B12 sin gate integrado actual | contrato vivo / ADR-0009 | seguridad/release | ejecutar PostgreSQL, Gherkin, PIT, E2E y drills sobre el SHA definitivo |
| Alta | Docker local indisponible y demo protegida no inspeccionable | `desktop-linux` sin daemon | evidencia operativa | no mutar la demo; recuperar el daemon de forma autorizada y usar proyectos efímeros |
| Alta | SAST y secret scan pendientes del SHA final | workflows no publicados | supply chain | ejecutar CodeQL/TruffleHog y revisar resultados del mismo SHA |
| Alta | Producción no acreditada | handoff / [#23](https://github.com/JerePrograma/Gestudio/issues/23) | seguridad/operación | validar TLS, secretos, storage, monitorización y restore |
| Alta | Transporte Jere no desplegado | integración v1 / [#25](https://github.com/JerePrograma/Gestudio/issues/25) | integración | smoke autorizado y runbook operativo |
| Alta | Gmail real no conectado ni desplegado | handoff / runbook email / [#23](https://github.com/JerePrograma/Gestudio/issues/23) | comunicación | OAuth2/credenciales autorizadas, staging, DNS y prueba controlada |
| Alta | Controller de observaciones existe pero está denegado | Security config | superficie dormante | decidir retirar o habilitar con diseño/pruebas |
| Media | GET cumpleaños genera estado/efecto | `NotificacionControlador` | semántica/idempotencia | separar comando/consulta o documentar explícito |
| Media | Cumpleaños deduplica el disparo pero no posee outbox propia | `NotificacionService` | pérdida entre commit y executor | aceptar garantía o diseñar outbox sólo ante requisito operativo |
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

Desde 2026-07-30 quedó cerrada la activación implícita de correo por perfil
`prod`: NOOP es el default, FAKE no abre red, Gmail exige guardas simultáneas y
un append Sent fallido no dispara un segundo SMTP. También se alineó el
comentario del cron de cumpleaños con su ejecución real a las 10:00.

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
