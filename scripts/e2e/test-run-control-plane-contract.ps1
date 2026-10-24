[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$runnerPath = Join-Path $PSScriptRoot 'run-control-plane.ps1'
$specPath = Join-Path $repoRoot 'frontend\e2e\control-plane.spec.ts'
$financialPath = Join-Path $repoRoot 'frontend\e2e\support\financial-flow.ts'

function Assert-Contains {
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $Marker,
        [Parameter(Mandatory)][string] $Failure
    )
    if ($Source.IndexOf($Marker, [StringComparison]::Ordinal) -lt 0) { throw $Failure }
}

function Assert-Ordered {
    param(
        [Parameter(Mandatory)][string] $Source,
        [Parameter(Mandatory)][string] $First,
        [Parameter(Mandatory)][string] $Second,
        [Parameter(Mandatory)][string] $Failure
    )
    $firstIndex = $Source.IndexOf($First, [StringComparison]::Ordinal)
    $secondIndex = $Source.IndexOf($Second, [StringComparison]::Ordinal)
    if ($firstIndex -lt 0 -or $secondIndex -lt 0 -or $firstIndex -ge $secondIndex) {
        throw $Failure
    }
}

foreach ($path in @($runnerPath, $specPath, $financialPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Falta archivo requerido por el contrato E2E: $path"
    }
}

$tokens = $null
$parseErrors = $null
$runnerAst = [Management.Automation.Language.Parser]::ParseFile(
    $runnerPath,
    [ref]$tokens,
    [ref]$parseErrors)
if ($parseErrors.Count -ne 0) {
    throw 'run-control-plane.ps1 no supera el parseo AST.'
}

$runner = [IO.File]::ReadAllText($runnerPath)
$spec = [IO.File]::ReadAllText($specPath)
$financial = [IO.File]::ReadAllText($financialPath)

# Application discovery returns every matching PATH entry on Windows. Execute
# the runner's actual assignment with several installations, including spaces.
$nodeResolvers = @($runnerAst.FindAll({
    param($item)
    $item -is [Management.Automation.Language.AssignmentStatementAst] -and
        $item.Left.Extent.Text -ceq '$nodeCommand'
}, $true))
if ($nodeResolvers.Count -ne 1) { throw 'Falta una resolucion unica del ejecutable Node.' }
$resolvedNodeFixture = & {
    function Get-Command {
        [CmdletBinding()]
        param([string] $Name, [string] $CommandType)
        if ($Name -cne 'node' -or $CommandType -cne 'Application') { throw 'Consulta Node inesperada.' }
        foreach ($path in @('C:\runtime con espacios\node.exe','C:\otra version\node.exe','C:\tercera\node.exe')) {
            [pscustomobject]@{Source=$path}
        }
    }
    . ([scriptblock]::Create($nodeResolvers[0].Extent.Text))
    return $nodeCommand
}
if (@($resolvedNodeFixture).Count -ne 1 -or
    $resolvedNodeFixture.Source -cne 'C:\runtime con espacios\node.exe') {
    throw 'El runner no fija el primer ejecutable Node del PATH cuando hay varias instalaciones.'
}
Write-Host 'Node PATH fixture: primera instalacion exacta con espacios y tres candidatos'

$startupFunctions = @($runnerAst.FindAll({
    param($item)
    $item -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $item.Name -ceq 'Get-ComposeStartupArguments'
}, $true))
if ($startupFunctions.Count -ne 1) { throw 'Falta contrato de arranque de imagenes ya preparadas.' }
. ([scriptblock]::Create($startupFunctions[0].Extent.Text))
foreach ($prepared in @($true,$false)) {
    $startup = @(Get-ComposeStartupArguments -ImagesAlreadyBuilt $prepared)
    $expectedMode = if ($prepared) { '--no-build' } else { '--build' }
    $forbiddenMode = if ($prepared) { '--build' } else { '--no-build' }
    if ($startup.Count -ne 6 -or $startup[0] -cne 'up' -or
        $startup -cnotcontains $expectedMode -or $startup -ccontains $forbiddenMode) {
        throw 'El arranque reconstruye un candidato ya preparado o altera el modo ordinario.'
    }
}
Assert-Contains -Source $runner -Marker 'Get-ComposeStartupArguments -ImagesAlreadyBuilt ([bool]$FinancialFlow)' `
    -Failure 'El runtime no usa el selector de construccion probado.'
Assert-Ordered -Source $runner -First 'El runtime $($entry[0]) difiere del ID construido/exportado.' `
    -Second '& node $playwrightCli test --config $playwrightConfig' `
    -Failure 'La identidad runtime/export debe verificarse antes del navegador.'
Write-Host 'Compose startup fixture: candidato sin reconstruccion y modo ordinario conservado'

# Run the runner's actual native command against an argv-only fixture. This
# covers spaces and option forwarding in both PowerShell runtimes without Docker.
$nodeCommands = @($runnerAst.FindAll({
    param($item)
    $item -is [Management.Automation.Language.CommandAst] -and
        $item.GetCommandName() -ceq 'node' -and
        $item.Extent.Text.IndexOf('$playwrightCli', [StringComparison]::Ordinal) -ge 0
}, $true))
if ($nodeCommands.Count -ne 1) { throw 'El runner debe tener una sola invocacion directa del CLI Node.' }
$argvRoot = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('gestudio-e2e-argv-' + [Guid]::NewGuid().ToString('N'))))
try {
    [IO.Directory]::CreateDirectory($argvRoot) | Out-Null
    $playwrightCli = Join-Path $argvRoot 'capture cli.js'
    $playwrightConfig = Join-Path $argvRoot 'config con espacios.ts'
    [IO.File]::WriteAllText($playwrightCli,
        'process.stdout.write(JSON.stringify(process.argv.slice(2)));', [Text.UTF8Encoding]::new($false))
    $argvOutput = & ([scriptblock]::Create($nodeCommands[0].Extent.Text))
    if ($LASTEXITCODE -ne 0) { throw 'El fixture nativo de argumentos fallo.' }
    [object[]] $forwarded = ConvertFrom-Json -InputObject ($argvOutput -join "`n")
    if ($forwarded.Count -ne 3 -or $forwarded[0] -cne 'test' -or
        $forwarded[1] -cne '--config' -or $forwarded[2] -cne $playwrightConfig) {
        throw 'Node no recibio test/config/path como tres argumentos exactos.'
    }
    Write-Host ('CLI argv fixture: ' + ($forwarded | ConvertTo-Json -Compress))
    $nativeDefinition=$runnerAst.Find({param($item) $item -is [Management.Automation.Language.FunctionDefinitionAst] -and $item.Name -ceq 'Invoke-Native'},$false)
    . ([scriptblock]::Create($nativeDefinition.Extent.Text))
    function ConvertTo-SafeText { param([AllowNull()][AllowEmptyString()][string] $Text) return $Text }
    $stderrProbe=Join-Path $argvRoot 'native stderr probe.js'
    [IO.File]::WriteAllText($stderrProbe,'process.stdout.write("synthetic stdout\n");process.stderr.write("synthetic stderr\n");process.exitCode=Number(process.argv[2]);',[Text.UTF8Encoding]::new($false))
    $successfulNative=Invoke-Native -FilePath node -Arguments @($stderrProbe,'0') -Capture
    if($successfulNative -notlike '*synthetic stdout*' -or $successfulNative -notlike '*synthetic stderr*' -or $ErrorActionPreference -cne 'Stop'){throw 'Native stderr exit0 was lost or error policy leaked.'}
    $nativeRejected=$false
    try { Invoke-Native -FilePath node -Arguments @($stderrProbe,'7') -Capture } catch { $nativeRejected=$_.Exception.Message -like '*exit code 7*' }
    if(-not $nativeRejected -or $ErrorActionPreference -cne 'Stop'){throw 'Native failure did not preserve its exit code and terminating contract.'}
    if((Invoke-Native -FilePath node -Arguments @($stderrProbe,'7') -AllowFailure) -ne 7 -or $ErrorActionPreference -cne 'Stop'){throw 'Allowed native failure lost its explicit exit code.'}
    foreach($allowMissing in @($false,$true)) {
        [void](Invoke-Native -FilePath node -Arguments @($stderrProbe,'0') -Capture)
        $missingRejected=$false
        try { Invoke-Native -FilePath (Join-Path $argvRoot 'missing executable.exe') -Arguments @('synthetic') -AllowFailure:$allowMissing } catch { $missingRejected=$true }
        if(-not $missingRejected -or $ErrorActionPreference -cne 'Stop'){throw 'Missing executable inherited stale exit0, including AllowFailure.'}
    }
    $nativePreference=Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue
    if($null -ne $nativePreference){
        $previousNativePreference=$nativePreference.Value
        try {
            $PSNativeCommandUseErrorActionPreference=$true
            if((Invoke-Native -FilePath node -Arguments @($stderrProbe,'7') -AllowFailure) -ne 7 -or
                $PSNativeCommandUseErrorActionPreference -ne $true){throw 'Native exit preference overrode explicit AllowFailure or leaked.'}
        } finally { $PSNativeCommandUseErrorActionPreference=$previousNativePreference }
    }
    Write-Host 'Native stderr fixture: exit0 capturado; exit7 rechazado o devuelto solo con AllowFailure; politica restaurada'
} finally {
    $resolvedArgvRoot = [IO.Path]::GetFullPath($argvRoot)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedArgvRoot.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        (Split-Path $resolvedArgvRoot -Leaf) -notmatch '^gestudio-e2e-argv-[a-f0-9]{32}$') {
        throw 'Se rechazo cleanup de fixture argv fuera del temporal propio.'
    }
    if (Test-Path -LiteralPath $resolvedArgvRoot) { Remove-Item -LiteralPath $resolvedArgvRoot -Recurse -Force }
}

$discoveryPath = Join-Path $repoRoot 'frontend\scripts\list-e2e.mjs'
Push-Location ([IO.Path]::GetTempPath())
try {
    $discoveryOutput = @(& node $discoveryPath 2>&1 | ForEach-Object { [string]$_ })
    if ($LASTEXITCODE -ne 0 -or ($discoveryOutput -join "`n") -notmatch 'Total: 1 test in 1 file') {
        throw 'La misma CLI/config no descubre el escenario desde otro directorio.'
    }
    $discoveryOutput | ForEach-Object { Write-Host $_ }
} finally { Pop-Location }

# Execute the fail-fast guard: this combination must not probe Docker or mutate a demo.
$rejected = $false
try {
    & $runnerPath -FinancialFlow -PersistentDemo
} catch {
    $rejected = $_.Exception.Message -ceq 'FinancialFlow requiere un proyecto efimero; PersistentDemo esta excluido.'
}
if (-not $rejected) { throw 'El flujo financiero no rechazo el demo persistente antes de ejecutar operaciones.' }
foreach ($option in @('RecoveryDrill','ExportCandidateImages')) {
    $rejected = $false
    $gateOptions = @{}
    $gateOptions[$option] = $true
    try { & $runnerPath @gateOptions } catch {
        $rejected = $_.Exception.Message -ceq 'RecoveryDrill y ExportCandidateImages requieren FinancialFlow efimero.'
    }
    if (-not $rejected) { throw 'Recovery/export sin FinancialFlow no rechazo antes de Docker.' }
}
Assert-Ordered -Source $runner -First 'if ($FinancialFlow -and $PersistentDemo)' `
    -Second '$dockerContext = Assert-LocalDockerTarget' `
    -Failure 'El rechazo de FinancialFlow persistente debe preceder al contacto con Docker.'
$rejected = $false
try { & $runnerPath -FinancialFlow -RecoveryDrill } catch {
    $rejected = $_.Exception.Message -ceq 'RecoveryDrill requiere RecoveryHistoricalCommit SHA40 explicito.'
}
if (-not $rejected) { throw 'RecoveryDrill sin baseline explicito no rechazo antes de Docker.' }
foreach ($requirement in @(
    @('APP_RECEIPTS_WORKER_ENABLED: `${APP_RECEIPTS_WORKER_ENABLED:?required}', 'El override no transmite el worker a Compose.'),
    @('$config.services.backend.environment.APP_RECEIPTS_WORKER_ENABLED -cne $envValues.APP_RECEIPTS_WORKER_ENABLED', 'Falta verificar el worker efectivo.'),
    @('$config.services.backend.environment.APP_SCHEDULING_ENABLED -cne ''false''', 'El flujo podria activar cron de negocio.'),
    @('$config.services.backend.environment.APP_EMAIL_REAL_NETWORK_ALLOWED -cne ''false''', 'El flujo podria permitir red de correo.'),
    @('''build'', ''--target'', ''receipt-path-validation''', 'Falta ejecutar el gate Linux de rutas.'),
    @('RECEIPT_PATH_VALIDATION_RUN=$suffix', 'El gate Linux no exige un run unico.'),
    @('''--output=type=cacheonly''', 'El stage opcional no debe exportar imagenes sin cleanup.'),
    @('$receiptPathLinuxStatus = ''EXECUTED_FAIL''', 'Un gate ejecutado que falla no debe aparecer como no ejecutado.'),
    @('& node $playwrightCli test --config $playwrightConfig', 'Playwright debe recibir sus opciones sin el shim npm.ps1.'),
    @('1|1|1|2|1|120.50|120.50|1|1|0|0', 'Falta reconciliacion financiera exacta y sin envios.')
)) {
    Assert-Contains -Source $runner -Marker $requirement[0] -Failure $requirement[1]
}
foreach ($marker in @('El recorrido financiero requiere un proyecto efimero aislado',
        'download.suggestedFilename()', 'Buffer.concat(chunks).equals(bytes)',
        'expect(denied.status()).toBe(404)', 'creditoGenerado: "0.00"')) {
    Assert-Contains -Source $financial -Marker $marker -Failure "Falta contrato financiero: $marker"
}
Assert-Ordered -Source $financial -First 'download.suggestedFilename()' `
    -Second 'headers: betaHeaders' -Failure 'Beta debe probar el PDF ya disponible para Alpha.'
$workflow = [IO.File]::ReadAllText((Join-Path $repoRoot '.github\workflows\e2e.yml'))
Assert-Contains -Source $workflow -Marker 'run: ./scripts/e2e/run-control-plane.ps1 -FinancialFlow' `
    -Failure 'El workflow E2E no exige el recorrido financiero efimero.'
Assert-Contains -Source $workflow -Marker '-FinancialFlow -RecoveryDrill' `
    -Failure 'El workflow E2E no exige recuperacion financiera real.'
Assert-Contains -Source $workflow -Marker 'fetch-depth: 0' `
    -Failure 'RecoveryDrill necesita el historial del baseline explicito en CI.'
Assert-Contains -Source $workflow -Marker '-RecoveryHistoricalCommit $env:RECOVERY_BASELINE_COMMIT' `
    -Failure 'RecoveryDrill debe probar el baseline de PR/push/manual explicito.'

foreach ($requirement in @(
    @("GetEnvironmentVariable('DOCKER_HOST', 'Process')", 'Falta rechazo explicito de DOCKER_HOST.'),
    @("'context', 'show'", 'Falta resolver el contexto Docker activo.'),
    @("'context', 'inspect', '--format', '{{json .Endpoints.docker.Host}}'", 'Falta inspeccionar el endpoint Docker.'),
    @('npipe:////./pipe/dockerDesktopLinuxEngine', 'Falta permitir exclusivamente named pipe local en Windows.'),
    @('unix:///var/run/docker.sock', 'Falta permitir exclusivamente el socket Docker local en Unix.'),
    @("'--context', `$context, 'info', '--format', '{{.OSType}}'", 'Falta inspeccionar el OSType del daemon fijado.'),
    @("`$osType.Trim() -cne 'linux'", 'Falta exigir un daemon Linux.'),
    @("SetEnvironmentVariable('DOCKER_CONTEXT', `$dockerContext, 'Process')", 'Falta fijar el contexto validado durante el run.'),
    @("Get-DockerProjectSnapshot -ProjectName 'gestudio-remote-demo'", 'Falta snapshot del demo protegido.'),
    @('Get-DockerProjectSnapshot -ProjectName $project', 'Falta snapshot del proyecto E2E aleatorio.'),
    @('{{.Id}}|{{.Image}}|{{.State.Status}}', 'Falta identidad y estado exactos de contenedores.'),
    @('{{.Name}}|{{.CreatedAt}}|{{.Driver}}|{{.Mountpoint}}|{{.Scope}}', 'Falta identidad exacta de volumenes.'),
    @('{{json .Containers}}', 'Falta estado exacto de conexiones de red.'),
    @('$projectBefore.Containers.Count -ne 0', 'Falta preflight de contenedores preexistentes.'),
    @('$projectBefore.Volumes.Count -ne 0', 'Falta preflight de volumenes preexistentes.'),
    @('$projectBefore.Networks.Count -ne 0', 'Falta preflight de redes preexistentes.'),
    @('$playwrightOutput = Join-Path $runRoot ''playwright-output''', 'El output Playwright no pertenece al temporal privado del run.'),
    @('GESTUDIO_E2E_OUTPUT_DIR = $playwrightOutput', 'El runner no entrega a Playwright el output privado del run.'),
    @('[Security.AccessControl.AccessControlSections]::Access', 'La ACL temporal no limita la lectura a la DACL.'),
    @('[IO.FileSystemAclExtensions]::GetAccessControl', 'La ACL temporal no usa lectura de acceso sin privilegios de SACL.'),
    @('[IO.FileSystemAclExtensions]::SetAccessControl', 'La ACL temporal no persiste la DACL restringida.'),
    @('Test-DockerProjectSnapshotInvariant -Before $projectBefore -After $projectAfter', 'Falta invariancia post-cleanup del proyecto E2E.'),
    @('Test-DockerProjectSnapshotInvariant -Before $protectedDemoBefore -After $protectedDemoAfter', 'Falta invariancia post-cleanup del demo protegido.'),
    @('protectedDemoInvariant = $protectedDemoInvariant', 'Falta resultado sanitizado de invariancia del demo.'),
    @('composeProjectInvariant = $projectInvariant', 'Falta resultado sanitizado de invariancia del proyecto E2E.'),
    @("`$_ -cne 'DO'", 'La salida fresh no elimina exclusivamente el command tag DO conocido.'),
    @('$freshRows.Count -ne 1', 'La salida fresh no exige una unica fila de estado.'),
    @('Estado actual: $freshState', 'El fallo fresh no conserva evidencia sanitizada para diagnostico.'),
    @('$bootstrapCounter = $currentTotpCounter + 1', 'El bootstrap no compensa el arranque frio del one-shot TOTP.'),
    @('Wait-BootstrapCommitted -Username $platformUsername', 'Falta confirmar el commit transaccional del bootstrap.')
)) {
    Assert-Contains -Source $runner -Marker $requirement[0] -Failure $requirement[1]
}

if ($runner -notmatch '(?s)\$residual\s*=\s*@\(\s*@\(') {
    throw 'El inventario residual debe conservar semantica de array con cero o un recurso.'
}
if ($runner.IndexOf('.SetOwner(', [StringComparison]::Ordinal) -ge 0) {
    throw 'La ACL temporal no debe exigir privilegios de cambio de owner.'
}

Assert-Ordered -Source $runner `
    -First '$dockerContext = Assert-LocalDockerTarget' `
    -Second '$protectedDemoBefore = Get-DockerProjectSnapshot' `
    -Failure 'El snapshot protegido debe ocurrir despues del preflight Docker local.'
Assert-Ordered -Source $runner `
    -First '$protectedDemoBefore = Get-DockerProjectSnapshot' `
    -Second '[void](Invoke-Compose -Arguments (Get-ComposeStartupArguments' `
    -Failure 'El snapshot protegido debe ocurrir antes de Compose up.'
Assert-Ordered -Source $runner `
    -First '$projectBefore = Get-DockerProjectSnapshot' `
    -Second '[void](Invoke-Compose -Arguments (Get-ComposeStartupArguments' `
    -Failure 'El preflight del proyecto aleatorio debe ocurrir antes de Compose up.'
Assert-Ordered -Source $runner `
    -First '$protectedDemoBefore = Get-DockerProjectSnapshot' `
    -Second '[IO.Directory]::CreateDirectory($runRoot)' `
    -Failure 'El snapshot protegido debe ocurrir antes de crear recursos temporales del run.'

$cleanupIndex = $runner.LastIndexOf('            Remove-LabeledResources', [StringComparison]::Ordinal)
$projectAfterIndex = $runner.LastIndexOf(
    '$projectAfter = Get-DockerProjectSnapshot',
    [StringComparison]::Ordinal)
$protectedAfterIndex = $runner.LastIndexOf(
    '$protectedDemoAfter = Get-DockerProjectSnapshot',
    [StringComparison]::Ordinal)
if ($cleanupIndex -lt 0 -or $projectAfterIndex -le $cleanupIndex -or
    $protectedAfterIndex -le $projectAfterIndex) {
    throw 'Las invariancias Docker deben comprobarse despues del cleanup etiquetado.'
}
if ($runner.IndexOf("function Remove-PlaywrightOutput", [StringComparison]::Ordinal) -ge 0 -or
    $runner.IndexOf("frontendRoot 'test-results\\e2e'", [StringComparison]::Ordinal) -ge 0) {
    throw 'El runner conserva cleanup de un output Playwright compartido fuera del temporal privado.'
}
if ($runner.IndexOf("if (`$Kind -in @('volume', 'network'))", [StringComparison]::Ordinal) -lt 0 -or
    $runner.IndexOf('{{index .Labels "com.docker.compose.project"}}', [StringComparison]::Ordinal) -lt 0 -or
    $runner.IndexOf('{{index .Config.Labels "com.docker.compose.project"}}', [StringComparison]::Ordinal) -lt 0) {
    throw 'El cleanup no selecciona el contrato de labels correcto por tipo de recurso.'
}
foreach ($forbidden in @("'system', 'prune'", "'volume', 'prune'", "'network', 'prune'")) {
    if ($runner.IndexOf($forbidden, [StringComparison]::Ordinal) -ge 0) {
        throw 'El runner contiene un prune Docker fuera del scope exacto.'
    }
}

foreach ($requirement in @(
    @('type SensitiveAuditValues = Set<string>', 'Falta el Set de secretos emitidos.'),
    @('const containsSensitiveAuditMaterial =', 'Falta el scanner recursivo de auditoria.'),
    @('sensitiveAuditKeyPattern.test(key)', 'Falta inspeccion recursiva de claves.'),
    @('value.includes(secret)', 'Falta inspeccion de secretos conocidos dentro de valores.'),
    @('sensitiveValues.has(String(value))', 'Falta inspeccion de valores primitivos no string.'),
    @('Array.isArray(value)', 'Falta recursion sobre arrays.'),
    @('Object.entries(value).some', 'Falta recursion sobre objetos.'),
    @('bearerValuePattern.test(value)', 'Falta detectar credenciales Bearer.'),
    @('jwtValuePattern.test(value)', 'Falta detectar JWT por forma.'),
    @('recoveryValuePattern.test(value)', 'Falta detectar recovery codes por forma.'),
    @('otpValuePattern.test(value)', 'Falta detectar OTP por forma.'),
    @('otpauthValuePattern.test(value)', 'Falta detectar URIs otpauth.'),
    @('rememberSensitiveValue(sensitiveValues, await totp.next())', 'Falta registrar codigos TOTP emitidos.'),
    @('await rememberSessionCookies(', 'Falta registrar cookies refresh emitidas.'),
    @('await rememberStepUpProof(await proofPromise, sensitiveValues)', 'Falta registrar proofs step-up emitidos.'),
    @('activationToken: rememberSensitiveValue(', 'Falta registrar tokens de activacion emitidos.'),
    @('/platform/activate#token=${encodeURIComponent(activationToken)}', 'El token de activacion no usa un fragmento local.'),
    @('url.search === "" && url.hash === ""', 'Falta comprobar el saneamiento completo de la URL de activacion.'),
    @('containsSensitiveAuditMaterial(event, sensitiveValues)', 'Falta escanear el evento completo.'),
    @('containsSensitiveAuditMaterial(detail, sensitiveValues)', 'Falta escanear metadata JSON parseada.'),
    @('body.content.length !== counts.success + counts.denied', 'Falta impedir eventos fuera del conjunto auditado.'),
    @('assertSensitiveAuditScannerContract(sensitiveValues)', 'Falta caracterizacion ejecutable del scanner.')
)) {
    Assert-Contains -Source $spec -Marker $requirement[0] -Failure $requirement[1]
}
foreach ($forbiddenInterpolation in @('${secret}', '${knownSecret}')) {
    if ($spec.IndexOf($forbiddenInterpolation, [StringComparison]::Ordinal) -ge 0) {
        throw 'Una falla del scanner podria interpolar un secreto.'
    }
}
if ($spec.IndexOf('/platform/activate?token=', [StringComparison]::Ordinal) -ge 0) {
    throw 'El spec E2E aun coloca el token de activacion en el query string.'
}

Write-Host 'Contrato estatico control-plane E2E: PASS'
