# Cierre técnico — rollback forward-compatible

> Fecha: 20 de julio de 2026  
> Zona horaria: `America/Argentina/Buenos_Aires`  
> Estado global: **NO-GO para demo comercial, staging y producción**

## 1. Objetivo

Demostrar que Gestudio puede cambiar a un artefacto funcional anterior y volver al actual sin ejecutar down migrations, sin perder datos y sin desconocer Flyway V7.

## 2. Contrato de rollback

- las migraciones aplicadas son permanentes;
- V1-V7 permanecen inmutables;
- una imagen objetivo debe contener exactamente todas las migraciones ya aplicadas;
- una imagen pre-V7 sólo es válida si se reconstruye incluyendo V7;
- la primera mitigación de la integración V7 es mantener su feature flag apagada;
- el cambio de artefacto exige confirmación explícita;
- se crea backup consistente antes del cambio salvo `-SkipBackup` deliberado;
- si el artefacto objetivo no queda healthy, se intenta restaurar automáticamente la imagen anterior.

## 3. Implementación

Archivos:

- `backend/Dockerfile`;
- `scripts/ops/rollback-backend.ps1`;
- `scripts/ops/verify-application-rollback.ps1`;
- `.github/workflows/application-rollback-verification.yml`;
- `docs/operations/rollback.md`.

La imagen backend incorpora:

```text
/app/build-metadata/flyway-latest
/app/build-metadata/git-revision
```

El script compara `flyway-latest` con `max(version)` exitoso de `flyway_schema_history`. Cualquier diferencia bloquea el rollback antes de recrear el backend.

## 4. Artefactos del drill

El drill construyó:

1. imagen actual desde el HEAD del PR;
2. imagen funcional anterior desde `ef4f9c31dab9a3dfce43f913177089f80ae0205a`, incorporando Dockerfile actual y V7;
3. imagen incompatible sintética declarando Flyway V6.

No se alteró ni se eliminó historia Flyway.

## 5. Evidencia ejecutada

Workflow:

```text
Application rollback verification
```

Datos:

- branch head: `6ec180cee4fe69a5f0d60e9aa394f7893179dd24`;
- merge ref ejecutado por Actions: `235c26544b10c0aedbe6ab50463911462d7a9509`;
- runner: Ubuntu 24.04.4;
- Git: 2.54.0;
- Docker: 28.0.4;
- Docker Compose: 2.38.2;
- PowerShell: 7.6.3;
- duración: `00:03:21`;
- pasos aprobados: 8;
- fallos: 0;
- resultado global: PASS;
- artefacto digest: `sha256:7c00914e46ce19e5cb987c5fe7477ad7aa21800f9215823e2fc41dd49b9b14b1`.

## 6. Casos aprobados

1. Docker disponible;
2. imágenes actual, anterior-compatible e incompatible construidas;
3. versión actual healthy con V1-V7;
4. dato sintético persistido antes del rollback;
5. rollback sin confirmación rechazado;
6. imagen V6 rechazada sin alterar la activa;
7. backup previo generado;
8. cambio a versión anterior compatible;
9. backend anterior healthy;
10. alumno preservado;
11. historial Flyway `7|7` preservado;
12. tablas V7 preservadas;
13. retorno al artefacto actual;
14. dato e historial nuevamente verificados;
15. cleanup sin contenedores, volúmenes, redes, imágenes, worktrees ni temporales.

## 7. Resultado

**Rollback de aplicación queda cerrado técnicamente en infraestructura descartable.**

Esto demuestra compatibilidad de artefactos y esquema. No define todavía:

- registry productivo;
- firma y promoción de imágenes;
- retención de artefactos;
- responsables y ventana;
- tiempo máximo de decisión;
- monitoreo durante el cambio;
- rollback coordinado del frontend;
- efectos externos ya publicados.

## 8. Riesgos residuales

- usar una etiqueta mutable en lugar de digest;
- construir de urgencia un artefacto rollback no probado;
- omitir el backup previo;
- confundir feature flag con reversión de efectos externos;
- ejecutar el cambio sin observabilidad;
- intentar down migrations.

## 9. Próximo gate

Observabilidad mínima:

- health de aplicación y dependencias;
- readiness/liveness;
- métricas HTTP, JVM, pool y base;
- correlación de requests;
- logs sanitizados;
- alertas y runbook de incidentes.

Demo comercial, staging y producción continúan en NO-GO.
