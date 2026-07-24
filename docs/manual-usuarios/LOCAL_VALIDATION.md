# Validación local del generador del manual

Estas comprobaciones deben ejecutarse en el equipo que dispone de Docker Desktop, navegador, demo persistente y acceso a `C:\laburo\Gestudio`.

No comparta la salida de variables sensibles. El informe final puede incluir versiones, estados, tamaños, hashes y metadata no secreta.

## Bloque 1: sincronizar `main` de forma segura

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\laburo\Gestudio'

git status
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo consultar el estado de Git.'
}

$pending = git status --porcelain
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo comprobar el árbol de trabajo.'
}

if ($pending) {
    throw 'El árbol de trabajo contiene cambios locales. No continúe hasta revisarlos.'
}

git fetch origin
if ($LASTEXITCODE -ne 0) {
    throw 'Falló git fetch origin.'
}

git checkout main
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo cambiar a main.'
}

git pull --ff-only origin main
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo actualizar main mediante fast-forward.'
}

git branch --show-current
git rev-parse HEAD
git status
```

## Bloque 2: comprobar archivos implementados

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\laburo\Gestudio'

$required = @(
    '.\scripts\manual\Manual.Common.ps1'
    '.\scripts\manual\Build-Manual.ps1'
    '.\scripts\manual\Preflight-Manual.ps1'
    '.\scripts\manual\Start-Gestudio.ps1'
    '.\scripts\manual\Seed-ManualDemo.ps1'
    '.\scripts\manual\Capture-Manual.ps1'
    '.\scripts\manual\Render-Manual.ps1'
    '.\scripts\manual\Validate-Manual.ps1'
    '.\scripts\manual\flows\capture-manual.cjs'
    '.\scripts\manual\flows\render-manual.cjs'
    '.\docs\manual-usuarios\README.md'
    '.\docs\manual-usuarios\LOCAL_VALIDATION.md'
    '.\docs\manual-usuarios\manifest.json'
    '.\docs\manual-usuarios\templates\manual.html'
    '.\docs\manual-usuarios\templates\manual.css'
)

$missing = $required | Where-Object {
    -not (Test-Path -LiteralPath $_)
}

if ($missing) {
    $missing | ForEach-Object {
        Write-Host "FALTA: $_"
    }

    throw 'Faltan archivos requeridos.'
}

Write-Host 'Todos los archivos requeridos existen.'
```

## Bloque 3: verificar herramientas

Primero, el preflight real:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\laburo\Gestudio'

powershell -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\manual\Preflight-Manual.ps1 `
    -SkipCredentialCheck

if ($LASTEXITCODE -ne 0) {
    throw 'Falló el preflight del manual.'
}
```

Diagnóstico directo:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$PSVersionTable.PSVersion

git --version
if ($LASTEXITCODE -ne 0) { throw 'Git no está disponible.' }

docker --version
if ($LASTEXITCODE -ne 0) { throw 'Docker no está disponible.' }

docker compose version
if ($LASTEXITCODE -ne 0) { throw 'Docker Compose v2 no está disponible.' }

node --version
if ($LASTEXITCODE -ne 0) { throw 'Node no está disponible.' }

npm --version
if ($LASTEXITCODE -ne 0) { throw 'npm no está disponible.' }

java -version
if ($LASTEXITCODE -ne 0) { throw 'Java no está disponible.' }

javac -version
if ($LASTEXITCODE -ne 0) { throw 'javac no está disponible.' }

npx --yes playwright@1.54.1 --version
if ($LASTEXITCODE -ne 0) { throw 'Playwright 1.54.1 no pudo resolverse.' }
```

## Bloque 4: suministrar credenciales de forma segura

Los nombres corresponden al contrato del generador. No escriba valores en scripts, historial, `.env` ni comandos persistidos.

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-SecretValue {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    $secureValue = Read-Host $Prompt -AsSecureString

    try {
        return [System.Net.NetworkCredential]::new(
            '',
            $secureValue
        ).Password
    }
    finally {
        $secureValue.Dispose()
    }
}

$env:GESTUDIO_DEMO_SUPERADMIN_PASSWORD = Read-SecretValue `
    'Contraseña para demo-superadmin'
$env:GESTUDIO_DEMO_DIRECCION_PASSWORD = Read-SecretValue `
    'Contraseña para demo-direccion'
$env:GESTUDIO_DEMO_ADMINISTRADOR_PASSWORD = Read-SecretValue `
    'Contraseña para demo-administrador'
$env:GESTUDIO_DEMO_SECRETARIA_PASSWORD = Read-SecretValue `
    'Contraseña para demo-secretaria'
$env:GESTUDIO_DEMO_CAJA_PASSWORD = Read-SecretValue `
    'Contraseña para demo-caja'

Write-Host 'Credenciales cargadas sólo en el proceso actual.'
```

Al finalizar, eliminarlas del proceso:

```powershell
Remove-Item Env:GESTUDIO_DEMO_SUPERADMIN_PASSWORD -ErrorAction SilentlyContinue
Remove-Item Env:GESTUDIO_DEMO_DIRECCION_PASSWORD -ErrorAction SilentlyContinue
Remove-Item Env:GESTUDIO_DEMO_ADMINISTRADOR_PASSWORD -ErrorAction SilentlyContinue
Remove-Item Env:GESTUDIO_DEMO_SECRETARIA_PASSWORD -ErrorAction SilentlyContinue
Remove-Item Env:GESTUDIO_DEMO_CAJA_PASSWORD -ErrorAction SilentlyContinue
```

## Bloque 5: validación canónica del proyecto

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\laburo\Gestudio'

powershell -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\codex\validate.ps1 `
    -Scope Frontend

if ($LASTEXITCODE -ne 0) {
    throw 'Falló la validación Frontend.'
}

powershell -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\smoke-local.ps1

if ($LASTEXITCODE -ne 0) {
    throw 'Falló el smoke local.'
}

powershell -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\validate-demo-seed.ps1

if ($LASTEXITCODE -ne 0) {
    throw 'Falló la validación del seed demo.'
}
```

## Bloque 6: generar el manual

Ejecución completa:

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\laburo\Gestudio'

powershell -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\manual\Build-Manual.ps1

if ($LASTEXITCODE -ne 0) {
    throw 'La generación del manual falló.'
}
```

Con una demo ya iniciada y validada:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\manual\Build-Manual.ps1 `
    -SkipApplicationStart

if ($LASTEXITCODE -ne 0) {
    throw 'La generación con demo preexistente falló.'
}
```

Con navegador visible:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\manual\Build-Manual.ps1 `
    -SkipApplicationStart `
    -Headed `
    -KeepApplicationRunning

if ($LASTEXITCODE -ne 0) {
    throw 'La ejecución headed falló.'
}
```

## Bloque 7: verificar artefactos

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\laburo\Gestudio'

$artifactRoot = '.\artifacts\manual'
$pdfPath = Join-Path $artifactRoot 'Manual_Gestudio_Usuarios_Nuevos.pdf'
$htmlPath = Join-Path $artifactRoot 'manual.html'
$metadataPath = Join-Path $artifactRoot 'metadata.json'

$files = @(
    $pdfPath
    $htmlPath
    $metadataPath
)

foreach ($file in $files) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "No existe el artefacto requerido: $file"
    }

    Get-Item -LiteralPath $file |
        Select-Object FullName, Length, LastWriteTime
}

powershell -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\manual\Validate-Manual.ps1 `
    -PdfPath $pdfPath

if ($LASTEXITCODE -ne 0) {
    throw 'La validación del manual falló.'
}

Get-ChildItem '.\artifacts\manual\screenshots' -Filter '*.png' -File |
    Sort-Object Name |
    Select-Object Name, Length
```

## Bloque 8: abrir el PDF para revisión humana

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\laburo\Gestudio'

$pdfPath = Resolve-Path `
    '.\artifacts\manual\Manual_Gestudio_Usuarios_Nuevos.pdf'

Start-Process $pdfPath
```

La revisión humana debe comprobar:

- portada e índice;
- capturas reales y textos legibles;
- ausencia de páginas completamente blancas;
- ausencia de contenido o tablas cortados;
- ausencia de contraseñas, tokens y datos reales;
- numeración de páginas;
- consistencia entre roles, menús y denegaciones;
- que los formularios de pagos y egresos no muestren operaciones nuevas generadas por el manual.

## Bloque 9: comprobar que no se versionen artefactos

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\laburo\Gestudio'

git status --short
if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo consultar git status.'
}

$trackedArtifacts = git ls-files -- `
    'artifacts/manual/**' `
    'docs/manual-usuarios/screenshots/**' `
    'docs/manual-usuarios/.tmp/**' `
    'playwright-report/**' `
    'test-results/**'

if ($LASTEXITCODE -ne 0) {
    throw 'No se pudo comprobar los artefactos versionados.'
}

if ($trackedArtifacts) {
    $trackedArtifacts
    throw 'Existen artefactos generados versionados accidentalmente.'
}

git check-ignore -v `
    '.\artifacts\manual\Manual_Gestudio_Usuarios_Nuevos.pdf'

if ($LASTEXITCODE -ne 0) {
    throw 'El PDF generado no está ignorado por Git.'
}

git check-ignore -v `
    '.\artifacts\manual\screenshots\01-login.png'

if ($LASTEXITCODE -ne 0) {
    throw 'Las capturas generadas no están ignoradas por Git.'
}
```

## Bloque 10: informe local para devolver

```powershell
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-Location 'C:\laburo\Gestudio'

Write-Host '=== Git ==='
git branch --show-current
if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar la rama.' }

git rev-parse HEAD
if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar HEAD.' }

git status --short
if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar el estado.' }

Write-Host '=== Demo ==='
powershell -NoProfile -ExecutionPolicy Bypass `
    -File .\scripts\demo-local.ps1 `
    -Action Status

if ($LASTEXITCODE -ne 0) {
    throw 'La demo no superó Status.'
}

Write-Host '=== Artefactos ==='
Get-ChildItem '.\artifacts\manual' -File |
    Select-Object Name, Length, LastWriteTime

Write-Host '=== Capturas ==='
Get-ChildItem '.\artifacts\manual\screenshots' -Filter '*.png' -File |
    Measure-Object |
    Select-Object Count

Write-Host '=== Metadata ==='
Get-Content '.\artifacts\manual\metadata.json' -Raw |
    ConvertFrom-Json |
    Select-Object `
        generatedAtUtc,
        sourceCommit,
        sourceBranch,
        screenshotCount,
        pageCount,
        pdfFileName,
        applicationStartedByGenerator
```

## Resultado esperado

La validación funcional total se completa únicamente cuando:

1. los bloques anteriores finalizan sin errores;
2. `Validate-Manual.ps1` aprueba;
3. el PDF fue revisado visualmente;
4. `git status --short` no muestra artefactos;
5. la salida no contiene secretos.

Devuelva el informe del Bloque 10 y los fallos exactos, sin contraseñas, tokens, cookies ni contenido de variables sensibles.
