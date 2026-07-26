# Preguntas abiertas

> Estado: PENDIENTE  
> Última revisión: 2026-07-26  
> Fuentes principales: huecos detectados durante la inspección remota e issues de GitHub

| Pregunta | Por qué importa | Área afectada | Seguimiento |
|---|---|---|---|
| ¿Cuál es la plataforma autorizada de staging y producción? | define TLS, DNS, secretos, storage y rollback | operaciones | [#23](https://github.com/JerePrograma/Gestudio/issues/23) |
| ¿Quién opera alertas, métricas y retención de logs? | evita observabilidad sin respuesta | operaciones | [#24](https://github.com/JerePrograma/Gestudio/issues/24) |
| ¿Cuándo se habilitará transporte Gestudio → Jere Platform? | el emisor existe pero no hay E2E desplegado | integración | [#25](https://github.com/JerePrograma/Gestudio/issues/25) |
| ¿Cuál es la política de retención de snapshots Jere? | tablas append-only pueden crecer | datos/privacidad | [#25](https://github.com/JerePrograma/Gestudio/issues/25) |
| ¿SMTP/IMAP reales están provisionados y monitoreados? | envío no fue validado en ambiente real | email | [#23](https://github.com/JerePrograma/Gestudio/issues/23) |
| ¿Qué semántica se desea si SMTP envía pero IMAP Sent falla? | evita reenvíos/estado ambiguo | email | pendiente de decisión funcional |
| ¿El job de cumpleaños debe correr a las 08:00 o 10:00? | comentario y cron contradicen | scheduler | pendiente de decisión funcional |
| ¿Se retirará `ObservacionProfesorControlador` o se habilitará? | hoy existe pero siempre responde 403 | API/seguridad | pendiente de decisión funcional |
| ¿`PERM_AUDITORIA_SEGURIDAD_LEER` tendrá endpoint? | está en catálogo sin ruta observada | RBAC | pendiente de decisión funcional |
| ¿`PERM_TARIFAS_HISTORICAS` debe proteger una operación? | está catalogado sin matcher observado | RBAC | pendiente de decisión funcional |
| ¿Cuándo se deprecian las respuestas legacy? | texto, `String` y status heterogéneos | API | pendiente de inventario/versionado |
| ¿Puede separarse generación y consulta de cumpleaños? | GET produce side effect | API/dominio | pendiente de decisión funcional |
| ¿Qué cobertura mínima se exige por módulo? | JaCoCo existe, umbral no confirmado | testing | pendiente de política |
| ¿Cuáles son los índices críticos bajo volumen productivo? | rendimiento no se deduce del demo | persistencia | requiere datos productivos |
| ¿Qué políticas de backup/restore productivas se aprobaron? | scripts no definen retención/RPO/RTO organizacional | continuidad | [#23](https://github.com/JerePrograma/Gestudio/issues/23) |
| ¿Qué documentación `.kiro` debe archivarse? | puede contradecir arquitectura real | gobernanza | pendiente de decisión documental |
| ¿Hay consumidores externos además del frontend y Jere Platform? | condiciona deprecaciones API | compatibilidad | pendiente de inventario |
| ¿Cómo se rotan credenciales demo tras certificación pública? | docs exigen rotación, operación debe asignarse | seguridad | [#23](https://github.com/JerePrograma/Gestudio/issues/23) |
| ¿Cuál es el proceso formal de aprobación de producción? | evita confundir repositorio verde con GO | release | [#23](https://github.com/JerePrograma/Gestudio/issues/23) |
| ¿Cuándo se abordarán las dependencias mayores incompatibles? | evita mezclar upgrades con promoción operativa | frontend | [#26](https://github.com/JerePrograma/Gestudio/issues/26) |

## Pregunta cerrada desde 2026-07-26

El versionado de `PageImpl` dejó de ser una pregunta abierta: la API pública usa
`PageResponse<T>` y el frontend ya consumía esa forma estable.

## Regla de cierre

Al responder una pregunta, registrar evidencia y actualizar el documento temático, [22-source-index.md](22-source-index.md) y [23-ai-working-context.md](23-ai-working-context.md).
