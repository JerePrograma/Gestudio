[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$bootstrapScript = Join-Path $PSScriptRoot 'bootstrap-platform-admin.ps1'
$passes = 0

function Assert-Contract {
    param(
        [Parameter(Mandatory)][bool] $Condition,
        [Parameter(Mandatory)][string] $Message
    )
    if (-not $Condition) { throw $Message }
    $script:passes++
}

$bytes = [IO.File]::ReadAllBytes($bootstrapScript)
Assert-Contract -Condition ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
    $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) `
    -Message 'El script bootstrap debe conservar UTF-8 BOM para Windows PowerShell.'
$source = [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
Assert-Contract -Condition (-not $source.Contains("`r")) `
    -Message 'El script bootstrap debe usar LF, sin CRLF mezclado.'
Assert-Contract -Condition $source.EndsWith("`n") `
    -Message 'El script bootstrap debe terminar con newline.'

$tokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile(
    $bootstrapScript, [ref]$tokens, [ref]$parseErrors)
$parseDetails = (@($parseErrors | ForEach-Object { $_.Message }) -join '; ')
Assert-Contract -Condition ($parseErrors.Count -eq 0) `
    -Message ('El script bootstrap no parsea: ' + $parseDetails)

$command = Get-Command -Name $bootstrapScript
Assert-Contract -Condition (@($command.ParameterSets.Name) -contains 'Bootstrap' -and
    @($command.ParameterSets.Name) -contains 'Recovery' -and
    @($command.ParameterSets).Count -eq 2) `
    -Message 'Deben existir sólo los parameter sets Bootstrap y Recovery.'
$recoverySet = $command.ParameterSets | Where-Object Name -CEQ 'Recovery'
$recoveryNames = @($recoverySet.Parameters.Name)
Assert-Contract -Condition ($recoveryNames -contains 'RecoverJobId' -and
    $recoveryNames -contains 'ConfirmRecovery' -and
    $recoveryNames -contains 'RecoveryCodesPath' -and
    $recoveryNames -notcontains 'Username' -and
    $recoveryNames -notcontains 'Password' -and
    $recoveryNames -notcontains 'TotpSecret' -and
    $recoveryNames -notcontains 'TotpCode') `
    -Message 'Recovery debe operar sin reingresar identidad, password ni secretos MFA.'
Assert-Contract -Condition $source.Contains("[ValidatePattern('^[a-f0-9]{64}$')]") `
    -Message 'Recovery debe exigir el ID Docker completo y canónico.'

$help = Get-Help -Name $bootstrapScript -Full
Assert-Contract -Condition (-not [string]::IsNullOrWhiteSpace($help.Synopsis) -and
    @($help.parameters.parameter.name) -contains 'RecoverJobId' -and
    @($help.parameters.parameter.name) -contains 'ConfirmRecovery') `
    -Message 'La ayuda debe documentar el modo de recuperación explícito.'

$functions = @{}
foreach ($definition in $ast.FindAll({
    param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]
}, $true)) {
    $functions[$definition.Name] = $definition.Extent.Text
}
foreach ($requiredFunction in @(
    'Assert-RecoveryJob', 'Set-OwnerOnlyAcl', 'Copy-RecoveryCodesSecurely',
    'Get-BootstrapState', 'Get-RecoveryCommand', 'Test-ShouldPreserveRecoveryJob')) {
    Assert-Contract -Condition $functions.ContainsKey($requiredFunction) `
        -Message "Falta la función contractual $requiredFunction."
}

$jobContract = $functions['Assert-RecoveryJob']
foreach ($requiredLabel in @(
    'com.docker.compose.project', 'com.docker.compose.service',
    'com.docker.compose.oneoff')) {
    Assert-Contract -Condition $jobContract.Contains($requiredLabel) `
        -Message "La recuperación no valida el label $requiredLabel."
}
Assert-Contract -Condition ($jobContract.Contains('$parts[0] -cne $ContainerId') -and
    $jobContract.Contains('[Regex]::Escape($ProjectName)') -and
    $jobContract.Contains('-platform-bootstrap-[a-f0-9]{8}')) `
    -Message 'La recuperación debe exigir ID completo y nombre exacto del job bootstrap.'

$copyContract = $functions['Copy-RecoveryCodesSecurely']
Assert-Contract -Condition ($copyContract.Contains('Test-Path -LiteralPath $recoveryCodesFullPath') -and
    $copyContract.Contains('[IO.File]::Move($stagedFile, $recoveryCodesFullPath)')) `
    -Message 'La entrega debe rechazar overwrite y publicar mediante move atómico.'
Assert-Contract -Condition ($copyContract.Contains('Set-OwnerOnlyAcl -Path $stagingDirectory -Directory') -and
    $copyContract.Contains('Set-OwnerOnlyAcl -Path $recoveryCodesFullPath') -and
    $copyContract.Contains('$codeCount -ne 10')) `
    -Message 'La entrega debe usar staging privado, ACL final y exactamente diez códigos.'

$recoveryCommand = $functions['Get-RecoveryCommand']
Assert-Contract -Condition ($recoveryCommand.Contains('-RecoverJobId') -and
    $recoveryCommand.Contains('-ConfirmRecovery') -and
    $recoveryCommand -notmatch '(?i)Username|Password|TotpSecret|TotpCode') `
    -Message 'El comando de recuperación no debe contener credenciales ni secretos MFA.'

Assert-Contract -Condition ($source.Contains('$bootstrapCommitted = $true') -and
    $source.Contains('$preserveJobForRecovery = Test-ShouldPreserveRecoveryJob') -and
    $source.Contains('-not $preserveJobForRecovery -and $removeJob')) `
    -Message 'Un fallo post-commit debe conservar el job hasta una entrega local segura.'
. ([scriptblock]::Create($functions['Test-ShouldPreserveRecoveryJob']))
Assert-Contract -Condition (Test-ShouldPreserveRecoveryJob $true $false $true $false) `
    -Message 'Un fallo post-commit del modo Bootstrap debe conservar el job.'
Assert-Contract -Condition (Test-ShouldPreserveRecoveryJob $true $false $false $true) `
    -Message 'Un nuevo fallo del modo Recovery debe conservar el job.'
Assert-Contract -Condition (-not (Test-ShouldPreserveRecoveryJob $true $false $false $false)) `
    -Message 'Un fallo pre-commit del modo Bootstrap no debe retener el job.'
Assert-Contract -Condition (-not (Test-ShouldPreserveRecoveryJob $true $true $true $false)) `
    -Message 'Una entrega segura debe permitir eliminar el job.'
Assert-Contract -Condition ($source.Contains('$ProjectName -ceq ''gestudio-remote-demo''') -and
    $source.Contains('RecoveryCodesPath debe quedar fuera del checkout de Gestudio.') -and
    $source.Contains('RecoveryCodesPath ya existe; se rechaza sobrescribirlo')) `
    -Message 'Deben conservarse la protección de la demo, checkout y overwrite.'

Write-Host "[PASS] bootstrap-platform-admin static contract ($passes assertions)" -ForegroundColor Green
