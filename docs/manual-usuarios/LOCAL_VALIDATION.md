# Validación local obligatoria

```powershell
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop';Set-Location 'C:\laburo\Gestudio';if(git status --porcelain){throw 'El árbol contiene cambios locales.'};git fetch origin;if($LASTEXITCODE-ne 0){throw 'Falló fetch.'};git checkout main;if($LASTEXITCODE-ne 0){throw 'Falló checkout main.'};git pull --ff-only origin main;if($LASTEXITCODE-ne 0){throw 'Falló pull --ff-only.'};git branch --show-current;git rev-parse HEAD;git status
```

```powershell
function Read-SecretValue([string]$Prompt){$s=Read-Host $Prompt -AsSecureString;[System.Net.NetworkCredential]::new('',$s).Password};$env:GESTUDIO_DEMO_SUPERADMIN_PASSWORD=Read-SecretValue 'Clave demo-superadmin';$env:GESTUDIO_DEMO_DIRECCION_PASSWORD=Read-SecretValue 'Clave demo-direccion';$env:GESTUDIO_DEMO_ADMINISTRADOR_PASSWORD=Read-SecretValue 'Clave demo-administrador';$env:GESTUDIO_DEMO_SECRETARIA_PASSWORD=Read-SecretValue 'Clave demo-secretaria';$env:GESTUDIO_DEMO_CAJA_PASSWORD=Read-SecretValue 'Clave demo-caja'
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\manual\Preflight-Manual.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\validate-demo-seed.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\manual\Build-Manual.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\manual\Validate-Manual.ps1 -OutputDirectory .\artifacts\manual
Start-Process (Resolve-Path '.\artifacts\manual\Manual_Gestudio_Usuarios_Nuevos.pdf')
git status --short
$tracked=git ls-files -- 'artifacts/manual/**' 'docs/manual-usuarios/screenshots/**' 'playwright-report/**' 'test-results/**';if($tracked){$tracked;throw 'Hay artefactos versionados.'}
```

Revisar portada, capturas legibles, páginas vacías o cortadas, numeración, datos ficticios, ausencia de claves y coherencia de permisos.

```powershell
'GESTUDIO_DEMO_SUPERADMIN_PASSWORD','GESTUDIO_DEMO_DIRECCION_PASSWORD','GESTUDIO_DEMO_ADMINISTRADOR_PASSWORD','GESTUDIO_DEMO_SECRETARIA_PASSWORD','GESTUDIO_DEMO_CAJA_PASSWORD'|ForEach-Object{Remove-Item "Env:$_" -ErrorAction SilentlyContinue}
```