# Cierre técnico — rollback forward-compatible

> Fecha: 20 de julio de 2026  
> Zona horaria: `America/Argentina/Buenos_Aires`  
> Estado global: **NO-GO para demo comercial, staging y producción**

## 1. Objetivo

Demostrar que Gestudio puede cambiar a un artefacto funcional anterior y volver al actual sin down migrations, pérdida de datos ni desconocimiento de Flyway V7.

## 2. Contrato original

- migraciones aplicadas permanentes;
- V1-V7 inmutables;
- imagen objetivo contiene exactamente todas las migraciones aplicadas;
- imagen pre-V7 sólo válida si se reconstruye incluyendo V7;
- mitigación inicial de V7: feature flag apagada;
- confirmación explícita;
- backup previo salvo `-SkipBackup` deliberado;
- recuperación automática de imagen anterior si target no queda healthy.

## 3. Implementación original

Archivos:

- `backend/Dockerfile`;
- `scripts/ops/rollback-backend.ps1`;
- `scripts/ops/verify-application-rollback.ps1`;
- `.github/workflows/application-rollback-verification.yml`;
- `docs/operations/rollback.md`.

Metadata inicial:

```text
/app/build-metadata/flyway-latest
/app/build-metadata/git-revision
```

El script compara `flyway-latest` con `max(version)` exitoso de `flyway_schema_history` y rechaza diferencias antes de recrear backend.

## 4. Artefactos del drill original

1. imagen actual;
2. imagen funcional anterior desde `ef4f9c31dab9a3dfce43f913177089f80ae0205a`, incorporando Dockerfile actual y V7;
3. imagen incompatible sintética Flyway V6.

No se alteró historia Flyway.

## 5. Evidencia original

- workflow: `Application rollback verification`;
- branch head: `6ec180cee4fe69a5f0d60e9aa394f7893179dd24`;
- merge ref Actions: `235c26544b10c0aedbe6ab50463911462d7a9509`;
- runner Ubuntu 24.04.4;
- Git 2.54.0;
- Docker 28.0.4;
- Compose 2.38.2;
- PowerShell 7.6.3;
- duración `00:03:21`;
- 8 pasos PASS;
- 0 fallos;
- digest `sha256:7c00914e46ce19e5cb987c5fe7477ad7aa21800f9215823e2fc41dd49b9b14b1`.

Casos:

1. Docker disponible;
2. tres imágenes construidas;
3. actual healthy con V1-V7;
4. dato sintético persistido;
5. rechazo sin confirmación;
6. rechazo V6;
7. backup previo;
8. cambio a anterior compatible;
9. anterior healthy;
10. alumno, Flyway `7|7` y tablas V7 preservados;
11. retorno al actual;
12. cleanup completo.

## 6. Integración en main

- PR: `#19`;
- candidato final: `bb82ff1ddc7a6b319383185e76d5e598ecc1d744`;
- workflows finales: GATE-1B, CI, backup/restore y rollback en success;
- hilos/reviews pendientes: 0;
- merge: `2eb9a8442c9a0c329c7ddaea42d3ea5c5827f35c`.

Estado: **integrado y cerrado técnicamente**.

## 7. Regresión detectada al incorporar observabilidad

El nuevo Compose reemplazó el healthcheck de puerto por `/actuator/health/readiness`.

En el HEAD documental final de observabilidad `415fe9040f072440f997719bcf2b030cb47e453a`:

- Backend, Frontend, Scope All, smoke y seed: PASS;
- CI: PASS;
- backup/restore: PASS;
- observabilidad: PASS;
- rollback: FAIL.

Evidencia del fallo:

- artefacto anterior inició Spring, PostgreSQL y Flyway V7 correctamente;
- Compose lo marcó unhealthy;
- causa: ese código histórico es anterior a Actuator y no expone readiness;
- recuperación automática a imagen actual funcionó;
- datos, base y cleanup no fallaron;
- digest del artefacto de fallo: `sha256:cefdc52779c5ab3d0108f7a1b27fcc9f75e1d10d8a69936191a16ea007e7277e`.

La observabilidad no se fusionó con este fallo abierto.

## 8. Contrato ampliado de health

Se agregó:

```text
/app/build-metadata/health-contract
```

Valores:

| Contrato | Imagen | Verificación |
|---|---|---|
| `actuator-readiness-v1` | contiene Actuator | readiness debe responder `UP` |
| `legacy-api-401-v1` | anterior a Actuator | `/api/alumnos` debe responder HTTP `401` |

La sonda legacy demuestra que el proceso completó startup y que la capa web/seguridad responde. No se acepta una mera apertura TCP.

El Dockerfile deriva el contrato desde `pom.xml`. El healthcheck autocontenido lee la metadata. Compose recibe `BACKEND_HEALTHCHECK_MODE` y el script de rollback lo fija según la imagen objetivo.

Imágenes creadas antes de esta metadata, pero con Flyway válido, reciben con advertencia el contrato legacy.

Contratos desconocidos se rechazan.

## 9. Rollback ampliado

El script ahora:

1. identifica Flyway de base/target;
2. identifica health contract de imagen actual/target;
3. crea backup;
4. recrea target con su contrato;
5. valida imagen y variable efectivas;
6. si falla, recupera la anterior usando su propio contrato;
7. devuelve ambos contratos en el JSON final.

Esto conserva rollback hacia versiones anteriores a Actuator sin degradar readiness de imágenes actuales.

## 10. Riesgos residuales

- tag mutable en lugar de digest;
- artefacto rollback no probado;
- omitir backup;
- permanencia prolongada de un artefacto legacy sin readiness detallada;
- confundir 401 legacy con cobertura completa de dependencias;
- feature flag confundida con reversión de efectos externos;
- rollback sin monitoreo externo;
- down migrations.

## 11. Límites

No define:

- registry productivo;
- firma/promoción/retención;
- responsables y ventana;
- tiempo máximo;
- monitoreo externo;
- rollback coordinado frontend;
- reconciliación de efectos externos.

El contrato legacy es una mitigación temporal. Staging y producción continúan en NO-GO.
