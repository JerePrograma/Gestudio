param([string]$BaseUrl='http://localhost:18081',[string]$BackendUrl='http://localhost:18080',[switch]$AllowNonLocalUrl)
Set-StrictMode -Version Latest;$ErrorActionPreference='Stop';$repo=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
foreach($p in @('.git','frontend\package.json','scripts\demo-local.ps1','docs\manual-usuarios\manifest.json')){if(!(Test-Path (Join-Path $repo $p))){throw "No existe $p."}}
foreach($c in @('git','docker','node','npm')){if(!(Get-Command $c -ErrorAction SilentlyContinue)){throw "Falta la herramienta requerida: $c"}}
docker compose version|Out-Null;if($LASTEXITCODE-ne 0){throw 'Falta Docker Compose v2.'};$branch=git -C $repo branch --show-current;if($LASTEXITCODE-ne 0-or$branch-ne'main'){throw 'La rama local debe ser main.'}
foreach($u in @($BaseUrl,$BackendUrl)){if(!$AllowNonLocalUrl-and([uri]$u).Host-notin@('localhost','127.0.0.1','::1')){throw 'La URL indicada no es local y requiere autorización explícita.'}}
foreach($n in @('GESTUDIO_DEMO_SUPERADMIN_PASSWORD','GESTUDIO_DEMO_DIRECCION_PASSWORD','GESTUDIO_DEMO_ADMINISTRADOR_PASSWORD','GESTUDIO_DEMO_SECRETARIA_PASSWORD','GESTUDIO_DEMO_CAJA_PASSWORD')){if([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($n,'Process'))){throw "Falta la variable $n."}}
Write-Host 'Preflight correcto. No se mostraron secretos.'