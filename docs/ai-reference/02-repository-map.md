# Mapa del repositorio

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: `README.md`, `backend/pom.xml`, `frontend/package.json`

## Árbol resumido

```text
backend/                 Spring Boot, Maven, JPA, seguridad, Flyway y pruebas
frontend/                React, TypeScript, Vite, pruebas y nginx
docs/                    runbooks, pruebas, integraciones, manual y cierres
scripts/                 desarrollo, demo, validación, operaciones y manual
.env.local.example       plantilla de entorno
README.md                entrada operativa vigente
```

## Puntos de entrada

- Backend: clase `@SpringBootApplication` bajo `backend/src/main/java/gestudio`.
- API: `backend/src/main/java/gestudio/controladores`, `gestudio/tarifas/api` y `gestudio/integraciones/jereplatform/api`.
- Frontend: `frontend/src`; scripts en `frontend/package.json`.
- Migraciones: `backend/src/main/resources/db/migration`.
- Pruebas: `backend/src/test`, frontend y checks nginx.
- Operación: `scripts/codex`, `scripts/dev`, `scripts/ops`, `scripts/manual`.

## No modificar sin análisis

Migraciones aplicadas, seguridad/RBAC, contratos API, scripts de recuperación, plantillas de entorno y configuración de imágenes/Compose.