# Generador reproducible del manual de usuarios

Este directorio contiene las fuentes versionadas del manual visual de Gestudio. Las pantallas operativas no se dibujan ni se recrean: se capturan desde la demo local real con los cinco roles documentados.

## Punto de entrada

Desde cualquier ubicación:

```powershell
& 'C:\laburo\Gestudio\scripts\manual\Build-Manual.ps1'
```

Desde la raíz del repositorio:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\manual\Build-Manual.ps1
```

El proceso ejecuta, en orden:

1. preflight de herramientas, Git, URLs y credenciales;
2. reutilización o inicio seguro de `scripts/demo-local.ps1`;
3. validación read-only del dataset demo;
4. recorridos reales con Playwright y capturas;
5. composición de HTML autocontenido;
6. impresión A4 a PDF mediante Chromium;
7. validación estructural, de metadata, rutas, capturas y secretos.

## Arquitectura

| Fuente | Responsabilidad |
|---|---|
| `scripts/manual/Build-Manual.ps1` | Orquestador único. |
| `scripts/manual/Preflight-Manual.ps1` | Herramientas, rama `main`, árbol limpio, URLs locales, credenciales y política de artefactos. |
| `scripts/manual/Start-Gestudio.ps1` | Consulta `Status`, inicia sólo cuando hace falta y espera frontend/readiness. |
| `scripts/manual/Seed-ManualDemo.ps1` | Valida el seed persistente existente sin `Reset` ni escrituras nuevas. |
| `scripts/manual/Capture-Manual.ps1` | Ejecuta Chromium con Playwright 1.54.1 fijado. |
| `scripts/manual/Render-Manual.ps1` | Lee manifest, incrusta capturas y genera HTML, PDF y metadata. |
| `scripts/manual/Validate-Manual.ps1` | Verifica manifest, PNG, PDF, metadata, secretos e ignores. |
| `docs/manual-usuarios/manifest.json` | Fuente de verdad de orden, roles, rutas, contenido y capturas. |
| `docs/manual-usuarios/content/` | Fragmentos editoriales versionados. |
| `docs/manual-usuarios/templates/` | Plantilla HTML y CSS de pantalla/impresión. |
| `scripts/manual/flows/` | Automatización Node ejecutada por el wrapper PowerShell. |

Playwright se conserva como herramienta externa de desarrollo, siguiendo la estrategia documentada por el repositorio. La versión está fijada en `1.54.1`; no se agrega una dependencia de producción ni se modifica `frontend/package.json`.

## Requisitos

- Windows PowerShell 5.1 o PowerShell 7.
- Git.
- Docker Desktop y Docker Compose v2.
- Node 22 o superior, npm y npx.
- JDK 21 completo.
- Acceso a npm para la primera resolución de Playwright y Chromium.
- Checkout limpio en la rama local `main`.

## Credenciales demo

El generador utiliza únicamente variables del proceso actual:

```text
GESTUDIO_DEMO_SUPERADMIN_PASSWORD
GESTUDIO_DEMO_DIRECCION_PASSWORD
GESTUDIO_DEMO_ADMINISTRADOR_PASSWORD
GESTUDIO_DEMO_SECRETARIA_PASSWORD
GESTUDIO_DEMO_CAJA_PASSWORD
```

Cuando falta alguna variable, `Build-Manual.ps1` la solicita mediante `Read-Host -AsSecureString` y la asigna sólo al proceso actual. Las claves se transmiten al mecanismo interactivo existente de `scripts/demo-local.ps1` por entrada estándar, sin incluirlas en argumentos, archivos, capturas, traces ni logs.

`Preflight-Manual.ps1`, cuando se ejecuta solo, falla si falta una variable y nunca muestra su valor.

## Ejecuciones útiles

### Demo administrada por el generador

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\manual\Build-Manual.ps1
```

Si la demo no estaba activa, el generador la detiene al terminar. Una demo preexistente no se detiene.

### Demo ya iniciada

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\manual\Build-Manual.ps1 `
  -SkipApplicationStart
```

### Navegador visible

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\manual\Build-Manual.ps1 `
  -Headed `
  -KeepApplicationRunning
```

## Resultados

```text
artifacts/manual/Manual_Gestudio_Usuarios_Nuevos.pdf
artifacts/manual/manual.html
artifacts/manual/metadata.json
artifacts/manual/screenshots/*.png
```

`metadata.json` incluye commit, rama, URLs, viewport, locale, zona horaria, roles, versiones de herramientas, cantidad de capturas, hashes SHA-256 y cantidad estructural de páginas. Nunca incluye cookies, tokens ni contraseñas.

## Datos y seguridad

- La demo utiliza datos sintéticos de Academia Movimiento Sur.
- Los recorridos del manual son read-only: no registran alumnos, inscripciones, asistencias, pagos ni egresos.
- La captura del login se realiza con campos vacíos.
- Traces, vídeos y reportes de Playwright permanecen desactivados.
- No se autoriza una URL externa salvo `GESTUDIO_MANUAL_ALLOW_NON_LOCAL_URL=1`.
- Esa autorización es explícita; no convierte el flujo en apto para producción.
- Las capturas muestran sólo el dataset ficticio documentado.

## Actualizar un flujo

1. Confirmar la ruta y el permiso en `frontend/src/rutas/routes.ts`.
2. Confirmar labels, headings y controles accesibles en el componente real.
3. Actualizar `scripts/manual/flows/capture-manual.cjs`.
4. Mantener nombres deterministas `NN-descripcion.png`.
5. Declarar cada captura exactamente una vez en `manifest.json`.
6. No añadir coordenadas ni sleeps arbitrarios.
7. Ejecutar el proceso completo y la revisión humana.

## Actualizar el manifest

Cada entrada exige:

- `id` único;
- `order` contiguo;
- `title`;
- `role`;
- `route` o `flow`;
- `content`;
- `required`;
- `screenshot` y, cuando corresponde, capturas adicionales en `screenshots`.

El renderer ordena por `order`, embebe cada imagen como data URI y no descarga recursos externos.

## Archivos versionados e ignorados

Se versionan scripts, flows, manifest, contenido, plantillas y documentación.

Se ignoran:

```text
artifacts/manual/
docs/manual-usuarios/screenshots/
docs/manual-usuarios/.tmp/
playwright-report/
test-results/
```

También quedan fuera traces, vídeos y temporales.

## Errores frecuentes

- **Falta Docker Desktop:** iniciar Docker Desktop y repetir Preflight.
- **Falta una variable de contraseña:** ejecutar el bloque seguro de `LOCAL_VALIDATION.md` o usar `Build-Manual.ps1`, que solicita la clave.
- **URL no local:** revisar `BaseUrl` y `BackendUrl`; no autorizar hosts externos por comodidad.
- **Demo desactualizada:** sincronizar `main`; `demo-local.ps1` valida metadata de imágenes.
- **No aparece una captura:** revisar que el rol tenga permiso y que el heading/label siga coincidiendo con el frontend.
- **PDF estructuralmente válido pero visualmente incorrecto:** abrirlo y realizar la revisión humana obligatoria.

## Limpieza segura

Para eliminar sólo resultados generados:

```powershell
Remove-Item -LiteralPath '.\artifacts\manual' -Recurse -Force
```

Para detener la demo sin borrar volúmenes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Stop
```

No usar `Reset`, `docker volume prune`, `git clean -fd` ni borrados globales como sustituto.

## Validación local obligatoria

Seguir [LOCAL_VALIDATION.md](LOCAL_VALIDATION.md). La comprobación estructural automatizada no reemplaza la revisión visual humana del PDF.
