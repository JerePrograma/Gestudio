# Auditoría integral post-demo — corte histórico 2026-07-21

Este documento conserva el diagnóstico que originó el cierre del 22 de julio.
No es la fuente de estado vigente; los resultados definitivos están en
[23_CIERRE_RELEASE_2026-07-22.md](23_CIERRE_RELEASE_2026-07-22.md).

## Hallazgos que motivaron el cierre

- cumpleaños demo ligado al ancla persistida y no al día comercial;
- consultas de cumpleaños que incluían personas inactivas;
- comparación operativa de Flyway contra una versión fija;
- stack healthy capaz de reutilizar imágenes antiguas;
- restore con bordes insuficientes ante archivos manipulados;
- configuración productiva con defaults demasiado permisivos;
- API de autorización de métricas obsoleta y headers ambiguos;
- OSIV implícito, fechas UTC en frontend y logs con payloads;
- logout no montado y notificaciones sin estado de carga/error;
- imágenes/workflows/documentación que necesitaban hardening.

## Resultado del seguimiento

Todos esos hallazgos fueron corregidos y cubiertos por la matriz local del
22 de julio: backend 203 pruebas, frontend 149+2, smoke 20/20,
observabilidad 8/8, backup/restore 12/12 en ambas versiones de PowerShell,
rollback 8/8 en ambas y navegador con cinco roles.

Los límites que dependen de infraestructura real —TLS, SMTP, storage,
observabilidad externa y transporte Jere Platform— se documentan como
precondiciones de despliegue, no como evidencia simulada.
