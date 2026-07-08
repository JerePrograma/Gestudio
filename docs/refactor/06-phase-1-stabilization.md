# Fase 1 - Estabilización de configuración y CI (snapshot histórico)

> Evidencia previa al reset canónico. No describe el runtime actual; consultar
> 00-05 y 11-20.

Fecha de cierre local: 2026-06-28.

Estado: gate local completo. No se realizó commit, push, despliegue ni conexión a una base de datos real.

## Diagnóstico

La línea base no era reproducible por cuatro causas confirmadas:

1. el frontend tenía 216 errores y 19 warnings de ESLint;
2. no existía un runner de tests frontend;
3. el perfil `dev` se activaba implícitamente desde el artefacto común;
4. Docker, PM2 y GitHub Actions mantenían contratos productivos parciales o contradictorios.

También se confirmaron dos fallos ocultos por el entorno:

- `FilePathResolverTest` exigía `GESTUDIO_HOME` externo y no era autocontenido;
- `frontend/src/index.css` referenciaba `diseño/layout.css`, que no existe. PostCSS ignoraba ese `@import` por estar después de las directivas de Tailwind y sólo emitía un warning.

## Cambios aplicados

### Frontend

- ESLint queda en cero errores y cero warnings sin deshabilitar reglas ni excluir código.
- Se agregaron Vitest, Testing Library, `jsdom` y el script `npm test -- --run`.
- Se agregaron 8 pruebas para resolución de entorno, login y comportamiento Axios ante 401, 403, refresh concurrente, fallo de refresh y prevención de loops.
- El refresh de autenticación usa una única promesa compartida; 403 conserva la sesión; el fallo de refresh elimina sólo las claves propias.
- `VITE_API_BASE_URL` es obligatorio en producción y rechaza HTTP remoto.
- Se reemplazaron `any`, catches vacíos, hooks inválidos y contratos DTO inconsistentes detectados por TypeScript.
- Los contextos React separan provider y hook para cumplir Fast Refresh.
- Se eliminó el import inexistente de `layout.css`; `global.css` continúa entrando por `main.tsx`.
- Los modelos de vista de caja conservan el comportamiento financiero heredado; esta fase no modificó cálculos, persistencia ni reglas de negocio monetarias.

### Backend y perfiles

- El artefacto común ya no define `spring.profiles.default=dev`.
- `ActiveProfileGuard` exige exactamente uno de `dev`, `test` o `prod`.
- Se agregaron pruebas de contexto para los tres perfiles, selección de `EmailPort`, schedulers, secreto JWT y ausencia de perfil.
- CORS se verifica mediante un preflight real con MockMvc.
- `FilePathResolverTest` usa un directorio temporal. La propiedad de sistema `gestudio.home` permite el override controlado del test y `GESTUDIO_HOME` sigue siendo el mecanismo de ejecución normal.

### Scripts y variables locales

- Se eligió la política B: los scripts no importan `.env`. Compose sí lo hace; Maven, Spring y Vite reciben variables del proceso.
- `status.ps1` lee y valida `POSTGRES_PORT`, `BACKEND_PORT` y `FRONTEND_PORT`.
- Los starters locales definen `dev` sólo para ejecución local y respetan puertos configurables.
- Se verificaron los tres puertos alternativos `5433`, `8090` y `5180` como configuraciones válidas.
- Todos los archivos PowerShell parsean sin errores.

### Docker y despliegue

- Producción elimina completamente `db.ports`; PostgreSQL queda sólo en la red Docker.
- No existen `container_name`; los recursos se aíslan por nombre de proyecto Compose.
- Backend y frontend usan exposición explícita y healthchecks; el puerto del backend es coherente con `SERVER_PORT`.
- Los secretos productivos no tienen fallback.
- `APP_SCHEDULING_ENABLED` respeta la variable productiva.
- Los volúmenes de PostgreSQL y recibos son persistentes y no se eliminan durante deploy o rollback.
- PM2 dejó de ser un mecanismo soportado y se eliminó `ecosystem.config.js`; Docker Compose es el único mecanismo productivo.

### GitHub Actions

- Permisos mínimos, concurrency y timeouts.
- Actions oficiales fijadas por SHA.
- Backend verify, lint, tests frontend, build frontend, validación de ambos Compose y builds Docker actúan como gates.
- Deploy sólo en push a `main` después de `validate`.
- Las imágenes se publican primero por SHA; `latest` se publica sólo después de un despliegue saludable.
- El deploy exige configuración, valida Compose remoto, espera healthchecks, muestra diagnóstico y restaura las imágenes anteriores si falla. No elimina volúmenes.

## Archivos modificados por área

- Configuración/CI: `.github/workflows/github.-actions-demo.yml`, `docker-compose.yml`, `docker-compose.prod.yml`, `backend/Dockerfile`, `backend/src/main/resources/application.yml`, `README.md`, documentación de desarrollo y scripts PowerShell.
- Backend: `ActiveProfileGuard`, pruebas de perfiles/JWT/CORS y `FilePathResolver` con su test.
- Frontend: manifiesto y lockfile, configuración Vitest, tests, Axios/environment, contextos, tipos y archivos alcanzados por la corrección completa de lint/TypeScript.
- Eliminado deliberadamente: `ecosystem.config.js`.
- Preservado sin intervención de esta fase: el cambio local previo de `AutenticacionControlador.java`, `.codex/` y `AGENTS.md`.

## Invariantes afectadas

- Seguridad de configuración: el perfil es explícito y producción falla cerrado ante secretos inválidos o ausentes.
- Sesión frontend: 401 y 403 tienen semánticas distintas; refresh concurrente es único.
- Persistencia: ninguna entidad, tabla, relación o migración fue modificada.
- Finanzas: ningún cálculo, importe persistido o transición financiera fue modificado.
- Historial: no se ejecutó eliminación física ni migración de datos.

## Migraciones

Ninguna. Las migraciones V1-V060 permanecen sin cambios.

## Comandos finales y resultados

| Comando | Resultado |
| --- | --- |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\setup.ps1` con JDK 21 | PASS; dependencias Maven resueltas y 560 paquetes npm instalados; no inició servicios. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1` con JDK 21 | PASS; backend, lint, tests, build y Compose local. |
| `backend\.\mvnw.cmd -B -ntp clean verify` | PASS; 25 tests, 0 fallos, 0 errores, 0 omitidos; JAR generado. |
| `frontend\npm run lint` | PASS; 0 errores, 0 warnings. |
| `frontend\npm test -- --run` | PASS; 3 archivos, 8 tests. |
| `frontend\npm run build` | PASS; 2295 módulos transformados, sin warnings de PostCSS. |
| `docker compose config --quiet` | PASS. |
| `docker compose -f docker-compose.yml -f docker-compose.prod.yml config --format json` con placeholders no secretos | PASS; `db` sin puertos y servicios de aplicación sin `build`. |
| `docker build --pull -t gestudio-backend:phase1-test .\backend` | PASS; 25 tests dentro del build. |
| `docker build --pull --build-arg VITE_API_BASE_URL=https://example.invalid/api --build-arg VITE_APP_TIME_ZONE=America/Argentina/Buenos_Aires -t gestudio-frontend:phase1-test .\frontend` | PASS. |
| parse de todos los `*.ps1` con el parser de PowerShell | PASS. |
| `status.ps1` con puertos 5433/8090/5180 | PASS; los tres puertos fueron leídos correctamente. |
| `git diff --check` | PASS; sin errores de whitespace. |

## Fallos observados y corregidos durante la fase

- El primer `clean verify` completo falló porque `FilePathResolverTest` exigía `GESTUDIO_HOME`; el test quedó autocontenido y el siguiente `clean verify` pasó.
- El primer build después de ordenar los imports CSS falló con `ENOENT` para `diseño/layout.css`; se confirmó que el archivo nunca existió y se eliminó la referencia muerta. Los builds posteriores pasaron sin warnings.
- El primer `git diff --check` detectó un espacio final y una línea vacía final; ambos fueron corregidos.

## Fallos y warnings preexistentes pendientes

El build exitoso conserva warnings que ya existían en la línea base:

- propiedades destino no mapeadas en varios mappers MapStruct;
- anotaciones Lombok `@Exclude` redundantes;
- uso deprecated en `MensualidadServicio`;
- operaciones unchecked en `DisciplinaServicio`;
- aviso de auto-attach de Mockito/Byte Buddy en JDK 21.

No se ocultaron ni se convirtieron en warnings artificialmente. Se mantienen en el registro de riesgos para fases posteriores porque corregirlos indiscriminadamente puede cambiar contratos o comportamiento financiero.

## Riesgos pendientes

- La autorización, JWT y recibos siguen en el estado heredado; corresponden a Fase 2.
- La cobertura frontend inicial protege configuración y auth, pero aún no cubre todos los formularios críticos.
- La efectividad del rollback de GitHub Actions sólo puede validarse integralmente en un entorno de staging con secretos y registro reales; no se ejecutó deploy.
- La política productiva aún depende de que el VPS conserve un `.env` válido y protegido.
- Los warnings MapStruct podrían representar campos omitidos reales y deben revisarse por caso de uso, no silenciarse en bloque.

## Gate

Fase 1 habilita el inicio de Fase 2. No hay compilación, tests, lint, Compose, Docker build, parse PowerShell ni whitespace checks fallidos.
