# Seguridad

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: Spring Security/JWT, README y configuración

## Confirmado

Spring Security, JWT Auth0 y RBAC fail-closed con 32 permisos. Health mínimo público; Prometheus protegido por `X-Gestudio-Metrics-Token`, separado de `JWT_SECRET`.

## Reglas

No enviar token de métricas al navegador; header repetido responde 401; producción falla seguro si faltan secretos; no versionar `.env`, credenciales, backups, dumps ni recibos.

## PENDIENTE

Auditar matriz rol-permiso, expiración/rotación JWT, CORS por perfil, CSRF, sanitización de logs y exposición de archivos. TLS/CORS/cookies reales requieren ambiente autorizado.