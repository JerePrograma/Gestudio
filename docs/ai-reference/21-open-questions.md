# Preguntas abiertas

> Estado: PENDIENTE  
> Última revisión: 2026-07-24  
> Fuentes principales: huecos detectados durante la inspección remota

| Pregunta | Por qué importa | Área afectada |
|---|---|---|
| ¿Cuál es la plataforma autorizada de staging y producción? | define TLS, DNS, secretos, storage y rollback | operaciones |
| ¿Quién opera alertas, métricas y retención de logs? | evita observabilidad sin respuesta | operaciones |
| ¿Cuándo se habilitará transporte Gestudio → Jere Platform? | el emisor existe pero no hay E2E desplegado | integración |
| ¿Cuál es la política de retención de snapshots Jere? | tablas append-only pueden crecer | datos/privacidad |
| ¿SMTP/IMAP reales están provisionados y monitoreados? | envío no fue validado en ambiente real | email |
| ¿Qué semántica se desea si SMTP envía pero IMAP Sent falla? | evita reenvíos/estado ambiguo | email |
| ¿El job de cumpleaños debe correr a las 08:00 o 10:00? | comentario y cron contradicen | scheduler |
| ¿Se retirará `ObservacionProfesorControlador` o se habilitará? | hoy existe pero siempre responde 403 | API/seguridad |
| ¿`PERM_AUDITORIA_SEGURIDAD_LEER` tendrá endpoint? | está en catálogo sin ruta observada | RBAC |
| ¿`PERM_TARIFAS_HISTORICAS` debe proteger una operación? | está catalogado sin matcher observado | RBAC |
| ¿Cuál es el plan de versionado para `PageImpl`? | cambiar JSON rompe consumidores | API/frontend |
| ¿Cuándo se deprecian las respuestas legacy? | texto, String y status heterogéneos | API |
| ¿Puede separarse generación y consulta de cumpleaños? | GET produce side effect | API/dominio |
| ¿Qué cobertura mínima se exige por módulo? | JaCoCo existe, umbral no confirmado | testing |
| ¿Cuáles son los índices críticos bajo volumen productivo? | rendimiento no se deduce del demo | persistencia |
| ¿Qué políticas de backup/restore productivas se aprobaron? | scripts no definen retención/RPO/RTO organizacional | continuidad |
| ¿Qué documentación `.kiro` debe archivarse? | puede contradecir arquitectura real | gobernanza |
| ¿Hay consumidores externos además del frontend y Jere Platform? | condiciona deprecaciones API | compatibilidad |
| ¿Cómo se rotan credenciales demo tras certificación pública? | docs exigen rotación, operación debe asignarse | seguridad |
| ¿Cuál es el proceso formal de aprobación de producción? | evita confundir repositorio verde con GO | release |

## Regla de cierre

Al responder una pregunta, registrar evidencia y actualizar el documento temático, [22-source-index.md](22-source-index.md) y [23-ai-working-context.md](23-ai-working-context.md).
