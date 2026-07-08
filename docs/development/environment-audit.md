# Auditoría de entorno de desarrollo

Fecha: 2026-06-28  
Repositorio: `C:\laburo\gestudio`  
Rama inicial: `main`  
Commit inicial: `b7b04461f2aec2f788976674451d310ff32cdf62` (`Merge pull request #10 from JerePrograma/feature/kiro-agents`)

## Alcance

Se auditó configuración, tooling, variables, perfiles Spring, builds, Docker, Compose, CI, scripts y documentación. No se modificaron migraciones ni comportamiento financiero. El cambio local previo en `AutenticacionControlador.java` y los archivos no versionados `.codex/` y `AGENTS.md` se preservaron.

## Herramientas requeridas y detectadas

| Herramienta | Declarada/requerida | Detectada inicialmente | Estado inicial |
| --- | --- | --- | --- |
| PowerShell | Windows PowerShell 5.1 o 7 | 7.6.3 en el shell de auditoría | disponible |
| Git | 2.x | 2.48.1.windows.1 | disponible |
| JDK | 21 | `java`: 1.8.0_251; `javac`: 21.0.7 | PATH inconsistente |
| `JAVA_HOME` | JDK 21 válido | `C:\Program Files\Eclipse Adoptium\jdk-21` | ruta inválida para Maven |
| Maven | Wrapper 3.9.10 | Maven global 3.9.10, bloqueado por `JAVA_HOME` | no reproducible |
| Node.js | 22.14.0 | 22.14.0 | disponible |
| npm | 10.x | 10.9.2 | disponible |
| Docker CLI | actual compatible | 29.3.1 | disponible |
| Docker Compose | v2+ | 5.1.1 | disponible |
| Docker Engine | Linux containers | no accesible | bloqueo de entorno |
| PostgreSQL | 15.12 vía Compose | listener externo en 5432 | puerto ocupado |

Sistema: Windows 64 bits, AMD64. Puertos iniciales: 5432 ocupado por PID 7164; 8080 y 8081 libres. No existe un componente Python necesario.

El `PATH` inicial tenía 40 entradas. Resoluciones relevantes: Git desde `C:\Program Files\Git`, `java` desde el shim Oracle Java 8, `javac` desde Corretto 21.0.7, Maven global desde Chocolatey 3.9.10, Node desde NVM for Windows y Docker desde Docker Desktop. Los scripts dejaron de depender del `java` incorrecto de `PATH` y validan el JDK bajo `JAVA_HOME`.

Versiones finales declaradas: Java 21, Maven Wrapper 3.9.10, Spring Boot 3.4.1, Node 22.14.0, PostgreSQL 15.12 Alpine, Temurin JRE 21.0.7+6 y Nginx 1.27.4 Alpine.

## Inventario inicial

- Backend Maven con Java 21 en `pom.xml`, Spring Boot parent 3.4.1 y un override innecesario de `spring-boot-starter-web` 3.4.0.
- Sin Maven Wrapper.
- Docker backend Java 17 y dependencia de `target/backend-1.0.jar` precompilado.
- Frontend sin lockfile versionado; `.gitignore` ignoraba `package-lock.json` y todos los `*.lock`.
- `package.json` contenía dependencia autorreferencial `frontend: file:` y React Query, usado en runtime, dentro de `devDependencies`.
- Docker frontend usaba `npm install` e imágenes flotantes.
- Vite usaba `process.env.NODE_ENV`; Axios contenía una IP productiva HTTP fija.
- CORS backend contenía orígenes/IP productivos fijos.
- `application.properties` mezclaba desarrollo con configuración común y contenía credenciales/secretos ficticios hardcodeados.
- `ecosystem.config.js` contenía credenciales y secreto JWT hardcodeados.
- Compose usaba credenciales fijas, imágenes `latest`, `container_name`, puertos rígidos y sin healthchecks.
- Email real y no-op podían registrarse simultáneamente fuera de producción.
- Schedulers estaban activos en todos los perfiles y no declaraban zona horaria.
- CI construía/publicaba/desplegaba sin `clean verify`, `npm ci`, lint ni build previo.
- README describía un stack aspiracional Java 17/Gradle/Next.js que no coincidía con la implementación.

No se reproduce ningún valor sensible encontrado. Los patrones detectados fueron contraseñas de datasource/Compose/PM2, secreto JWT y credenciales SMTP/IMAP ficticias pero inseguras como defaults.

## Comandos soportados después de la corrección

- `backend\mvnw.cmd clean verify`
- `frontend\npm ci`
- `frontend\npm run lint`
- `frontend\npm run build`
- `docker compose config`
- `scripts\codex\setup.ps1`
- `scripts\codex\status.ps1`
- `scripts\codex\validate.ps1`
- scripts de inicio/detención bajo `scripts\dev\`.

## Estado inicial de validaciones

| Comando | Resultado inicial |
| --- | --- |
| `mvn clean verify` con entorno heredado | FAIL 1: `JAVA_HOME` inválido |
| `mvn clean verify` con JDK 21 y `GESTUDIO_HOME` corregidos sólo para diagnóstico | FAIL 1: 15 tests, 3 fallos preexistentes por separadores de ruta Windows |
| `npm ci` | FAIL 1: no existía `package-lock.json` |
| `npm run lint` | FAIL 1: dependencias ausentes; `eslint` no encontrado |
| `npm run build` | FAIL 1: dependencias ausentes; `tsc` no encontrado |
| `docker compose config` | PASS 0 con warning por atributo `version` obsoleto |
| `docker info` | FAIL 1: Docker Engine no disponible |

## Correcciones aplicadas

- Java 21 coherente en Maven, Wrapper, Docker, CI y documentación.
- Maven Wrapper 3.9.10 y lockfile npm versionables.
- Perfiles Spring YAML comunes/dev/test/prod sin secretos productivos por defecto.
- Propiedades tipadas para JWT y configuración de aplicación; CORS, duraciones, issuer, recibos y zona horaria externalizados.
- Email real sólo en `prod`; email no-op fuera de producción; schedulers deshabilitados por defecto en dev/test.
- URL y zona horaria Vite centralizadas; producción exige URL explícita y HTTPS salvo localhost.
- Compose local con builds, healthchecks, dependencias saludables, puertos variables y recursos aislados por proyecto.
- Override Compose de producción con variables críticas obligatorias.
- Scripts PowerShell reproducibles y acciones Codex delegadas a scripts versionados.
- CI valida antes de publicar/desplegar y etiqueta imágenes por SHA además de `latest`.
- La firma requerida por recibos/email se incorporó al contexto backend y se verificó legible en `/app/imgs` por el usuario no root.

## Validación final

| Comando | Resultado final |
| --- | --- |
| `scripts/codex/status.ps1` | PASS 0; JDK 21.0.7, Wrapper 3.9.10, Node 22.14.0, npm 10.9.2, Docker 29.3.1/Compose 5.1.1; 5432 ocupado, 8080/8081 libres |
| `scripts/codex/setup.ps1` | PASS 0; `dependency:go-offline` PASS y `npm ci` agregó 476 paquetes |
| `scripts/codex/validate.ps1` | FAIL 1 por lint; backend PASS, test frontend SKIP sin script, build frontend PASS, Compose PASS |
| `backend\mvnw.cmd clean verify` | PASS 0; 17 tests, 0 fallos, 0 errores, 0 omitidos; build 34.418 s |
| `frontend\npm ci` | PASS 0; lockfile v3 reproducible en Windows y Linux |
| `frontend\npm run lint` | FAIL 1; 235 problemas preexistentes: 216 errores y 19 warnings |
| `frontend\npm run build` | PASS 0; Vite build 11.11 s, con dos warnings PostCSS preexistentes por orden de `@import` |
| `docker compose config --quiet` | PASS 0 |
| Compose local + override prod con placeholders no sensibles | PASS 0 |
| `docker build --no-cache -t gestudio-backend:config-test .\backend` | PASS 0; 17 tests dentro de la etapa de build |
| rebuild backend final tras incorporar asset | PASS 0; asset legible, 57.051 bytes, owner `gestudio:gestudio` |
| `docker build --no-cache -t gestudio-frontend:config-test .\frontend` | PASS 0 final; el primer intento reveló un lock inválido, corregido con pin directo de `picomatch` 4.0.4 |
| healthcheck tools en imágenes | PASS 0; `nc` backend y `wget` frontend disponibles |
| `scripts/codex/cleanup.ps1` dos veces | PASS 0 ambas; idempotente |
| parse de todos los `.ps1` | PASS; 0 errores de sintaxis |
| `git diff --check` | PASS; sólo avisos informativos CRLF de Git for Windows |

## Fallos y riesgos pendientes

- Lint frontend: deuda previa amplia. No se desactivaron reglas ni se editaron 50+ archivos funcionales fuera de alcance.
- El frontend no declara script de tests; el gate lo informa como `SKIP`, no como éxito.
- El build frontend emite dos warnings PostCSS por imports CSS preexistentes.
- Maven conserva warnings MapStruct/Lombok, APIs deprecadas y carga dinámica de Mockito preexistentes.
- No se ejecutó una migración Flyway contra PostgreSQL: no hubo cambios de migración y el puerto 5432 estaba ocupado por una instancia ajena. No se tocó esa instancia.
- Docker Engine no estaba disponible al inicio, pero pasó a estar operativo y permitió completar ambos builds. No se levantó producción ni se ejecutó el job de despliegue.
- El asset de firma existe en raíz y en el contexto backend; deben mantenerse sincronizados mientras el resolver heredado siga usando `GESTUDIO_HOME`.
