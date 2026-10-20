# Validación local del manual de usuarios

Esta guía comprueba el manual sin modificar datos de negocio. Las capturas se obtienen con consultas de solo lectura sobre las cuentas sintéticas de la demo.

## 1. Revisar el estado del repositorio

Trabajá sobre `main` y revisá los cambios antes de continuar. No descartes, mezcles ni ocultes trabajo local para generar el manual.

```powershell
git branch --show-current
git rev-parse HEAD
git rev-parse origin/main
git status --short --branch
```

Si existen cambios locales, no ejecutes una actualización automática. Inventarialos y continuá únicamente cuando sean compatibles con la generación documental.

## 2. Comprobar las fuentes

```powershell
$manifest = Get-Content .\docs\manual-usuarios\manifest.json -Raw | ConvertFrom-Json
if ($manifest.version -ne 3) { throw 'Versión de manifiesto inesperada.' }
if ($manifest.items.Count -ne 40) { throw 'El manual debe contener 40 capítulos.' }

$missing = foreach ($item in $manifest.items) {
    $path = Join-Path .\docs\manual-usuarios $item.content
    if (-not (Test-Path -LiteralPath $path)) { $path }
}
if ($missing) { throw "Faltan capítulos: $($missing -join ', ')" }

$accounts = Get-Content .\docs\manual-usuarios\data\demo-accounts.json -Raw | ConvertFrom-Json
if ($accounts.accounts.Count -ne 9) { throw 'Deben existir nueve cuentas demo autorizadas.' }
```

## 3. Comprobar la sintaxis del generador

```powershell
node --check .\scripts\manual\flows\capture-manual.cjs
node --check .\scripts\manual\flows\render-manual.cjs
node --test .\scripts\manual\flows\manual-diagnostics.test.cjs .\scripts\manual\flows\manual-accounts.test.cjs

@(
  '.\scripts\manual\Manual.Common.ps1',
  '.\scripts\manual\Capture-Manual.ps1',
  '.\scripts\manual\Render-Manual.ps1',
  '.\scripts\manual\Validate-Manual.ps1'
) | ForEach-Object {
  [void][scriptblock]::Create((Get-Content -LiteralPath $_ -Raw))
}
```

## 4. Obtener capturas actuales

La demo pública debe estar disponible. Esta etapa inicia y cierra sesión con las nueve cuentas autorizadas, no crea alumnos, pagos, egresos ni otros registros y no imprime contraseñas, cookies ni códigos de autenticación.

```powershell
$output = Join-Path (Get-Location) 'artifacts\manual'
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\manual\Capture-Manual.ps1 `
  -BaseUrl 'https://gestudio-demo-jere-287b8c90.pages.dev/' `
  -OutputDirectory $output
```

Resultado esperado: 36 imágenes PNG legibles en `artifacts/manual/screenshots` y ningún error de navegación o permiso.

## 5. Generar HTML y PDF

```powershell
$output = Join-Path (Get-Location) 'artifacts\manual'
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\manual\Render-Manual.ps1 `
  -BaseUrl 'https://gestudio-demo-jere-287b8c90.pages.dev/' `
  -BackendUrl 'https://gestudio-demo-jere-287b8c90.pages.dev/api' `
  -OutputDirectory $output
```

El resultado queda en:

- `artifacts/manual/manual.html`
- `artifacts/manual/Manual_Gestudio_Usuarios_Nuevos.pdf`
- `artifacts/manual/metadata.json`

## 6. Ejecutar la validación automática

```powershell
$output = Join-Path (Get-Location) 'artifacts\manual'
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\manual\Validate-Manual.ps1 `
  -OutputDirectory $output
```

La validación debe comprobar:

- 40 capítulos en el orden esperado;
- HTML, CSS e imágenes presentes y ausencia de scripts en el manual offline;
- enlaces internos y destinos de navegación válidos;
- 36 capturas actuales;
- ausencia de rutas locales, `localhost` y referencias técnicas ajenas al cliente;
- presencia exclusiva de las contraseñas demo autorizadas;
- ausencia de proxy tokens, JWT, cookies, recovery codes, credenciales de base de datos y secretos de infraestructura;
- ausencia de UUID internos en el contenido visible.

Para capturas locales, usá el recorrido con `-CredentialManifestPath` de
README.md. El resultado debe declarar el origen local y el perfil real usado,
sin publicar contraseñas privadas ni la clave privada de segundo factor.

## 7. Revisión visual

Abrí `artifacts/manual/manual.html` en Chrome y recorré el índice completo. Abrí también el PDF y comprobá portada, índice, capturas, tablas, saltos de página y legibilidad.

La revisión es satisfactoria cuando no existen capítulos vacíos, imágenes cortadas, texto desbordado, enlaces rotos ni páginas en blanco.

## 8. Control final de Git

```powershell
git diff --check
git diff -- docs/manual-usuarios scripts/manual
git status --short --branch
```

Los artefactos generados deben permanecer fuera de Git. No hagas commit ni push mientras el repositorio contenga cambios ajenos o no resulte seguro cerrar la intervención.

## Resultado esperado

```text
MANUAL_HTML=PASS
MANUAL_PDF=PASS
INTERNAL_LINKS=PASS
IMAGES=PASS
PROXY_TOKEN_IN_MANUAL=NO
RECOVERY_CODES_IN_MANUAL=NO
INFRASTRUCTURE_SECRETS_IN_MANUAL=NO
AUTHORIZED_DEMO_PASSWORDS_IN_MANUAL=YES
```

## Evidencia de la integración del 20/10/2026

En esta revisión se reconstruyeron el HTML, el PDF y la metadata **sin conexión
a la aplicación**, a partir de las 36 capturas que ya existían en el equipo.
No se tomaron capturas nuevas ni se verificó el estado actual de la demo pública.
La fecha de generación del documento corresponde a esta reconstrucción y no
debe interpretarse como fecha de las capturas.

Resultados comprobados:

- 40 capítulos, 36 imágenes y enlaces internos válidos;
- PDF de 95 páginas, renderizadas a PNG y revisadas visualmente;
- `Validate-Manual.ps1`: aprobado, incluido el control de contenido sensible;
- `node --test scripts/manual/flows/*.test.cjs`: 14 pruebas aprobadas;
- sintaxis de los ocho scripts PowerShell y los flujos JavaScript: aprobada;
- `git diff --check -- docs/manual-usuarios scripts/manual`: aprobado.

El uso de credenciales locales se probó con manifiestos sintéticos: las pruebas
comprueban el reemplazo en memoria, el perfil real utilizado, la conservación
de la fuente pública y el rechazo de destinos externos. No se leyeron
credenciales privadas reales para esta validación.

Queda pendiente ejecutar el recorrido local completo con Docker y la aplicación
en funcionamiento. La validación offline no demuestra el funcionamiento actual
de ese recorrido ni de los inicios de sesión.
