[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'verify-financial-recovery.ps1')
function Expect-Rejection {
    param([scriptblock] $Action)
    $rejected = $false
    try { & $Action } catch { $rejected = $true }
    if (-not $rejected) { throw 'Expected recovery scope rejection did not occur.' }
}
$project = 'gestudio-e2e-' + [Guid]::NewGuid().ToString('N').Substring(0,12)
$root = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) $project))
if (Test-Path -LiteralPath $root) { throw 'Contract temporary root exists.' }
[IO.Directory]::CreateDirectory($root) | Out-Null
$compose = Join-Path $root 'config.json'
$envFile = Join-Path $root 'synthetic.env'
$previousHost = [Environment]::GetEnvironmentVariable('DOCKER_HOST','Process')
$previousContext = [Environment]::GetEnvironmentVariable('DOCKER_CONTEXT','Process')
$previousBackend = [Environment]::GetEnvironmentVariable('BACKEND_IMAGE','Process')
try {
    # Execute the real SQL argument builder with the same mandatory native-array
    # binding as the runner. The primary database uses the shell's default and
    # must not forward an empty native argument; an alternative stays explicit.
    $sqlTokens=$null; $sqlErrors=$null
    $recoveryAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'verify-financial-recovery.ps1'),[ref]$sqlTokens,[ref]$sqlErrors)
    if($sqlErrors.Count -ne 0){throw 'Recovery AST is invalid.'}
    $sqlFunction=$recoveryAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Recovery-Sql'},$true)
    . ([scriptblock]::Create($sqlFunction.Extent.Text))
    $script:sqlArgumentCalls=[Collections.Generic.List[object]]::new()
    function Recovery-Compose {
        param([Parameter(Mandatory)][string[]] $Arguments)
        $script:sqlArgumentCalls.Add($Arguments)
        return ' 17 '
    }
    if((Recovery-Sql 'SELECT 17') -cne '17' -or
        (Recovery-Sql 'SELECT 17' 'gestudio_recovery_contract') -cne '17'){throw 'Recovery SQL output was altered.'}
    if($script:sqlArgumentCalls.Count -ne 2 -or
        $script:sqlArgumentCalls[0].Count -ne 8 -or $script:sqlArgumentCalls[1].Count -ne 9 -or
        $script:sqlArgumentCalls[1][-1] -cne 'gestudio_recovery_contract'){throw 'Recovery primary/alternative database argument contract failed.'}
    foreach($sqlCall in $script:sqlArgumentCalls){
        if([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($sqlCall[7])) -cne 'SELECT 17' -or
            $sqlCall[5] -cnotlike '*${2:-$POSTGRES_DB}*'){throw 'Recovery SQL encoding or primary database fallback changed.'}
    }
    $opsFunction=$recoveryAst.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Recovery-Ops'},$true)
    . ([scriptblock]::Create($opsFunction.Extent.Text))
    $Log=[Collections.Generic.List[string]]::new()
    $Sanitize={param($value) [string]$value}
    $operationFixture=Join-Path $root 'operation-stream-fixture.ps1'
    [IO.File]::WriteAllText($operationFixture,@'
[CmdletBinding()]
param([string] $Directory, [switch] $Fail)
try {
    if ($Fail) { throw 'synthetic operational failure' }
    Write-Output $Directory
} finally { Write-Host 'Container synthetic backend Started' }
'@,[Text.UTF8Encoding]::new($true))
    $expectedBackupPath=Join-Path $root 'backup con espacios'
    $backupOutput=@(Recovery-Ops -Script $operationFixture -Parameters @{Directory=$expectedBackupPath})
    if($backupOutput.Count -ne 1 -or $backupOutput[-1] -cne $expectedBackupPath -or
        $Log -cnotcontains 'Container synthetic backend Started'){throw 'Recovery success output is confused with diagnostic streams or a string character.'}
    Expect-Rejection { Recovery-Ops -Script $operationFixture -Parameters @{Directory=$expectedBackupPath;Fail=$true} }
    if(-not ([IO.File]::ReadAllText((Join-Path $PSScriptRoot 'verify-financial-recovery.ps1')).Contains('$backup = @(Recovery-Ops'))){throw 'Backup caller must preserve single-output array semantics.'}
    Set-Content -LiteralPath $compose -Value '{}' -Encoding ASCII
    Set-Content -LiteralPath $envFile -Value '# synthetic, no secrets' -Encoding ASCII
    Assert-FinancialRecoveryScope $project $root $compose $envFile
    foreach ($invalid in @('gestudio-remote-demo','gestudio-demo-local','crm-platform','gestudio-e2e-123')) {
        Expect-Rejection { Assert-FinancialRecoveryScope $invalid $root $compose $envFile }
    }
    Expect-Rejection { Assert-FinancialRecoveryScope $project ([IO.Path]::GetTempPath()) $compose $envFile }
    Expect-Rejection { Assert-FinancialRecoveryScope $project $root $PSCommandPath $envFile }
    $script:recoveryNativeCalls = 0
    $script:recoveryEndpointJson = '"tcp://external.invalid:2376"'
    $invokeParameters = @{
        RepoRoot=$root; RunRoot=$root; ComposeFile=$compose; EnvFile=$envFile; Project=$project;
        HistoricalCommit=('a'*40);
        CurrentImageId=('sha256:' + ('a' * 64)); AlphaCode='danza-marcos-paz-0123456789ab'; BetaCode='beta-e2e-0123456789ab';
        Native={ $script:recoveryNativeCalls++; return $script:recoveryEndpointJson };
        WritePrivate={ throw 'Private write must not occur before preflight' };
        Sanitize={ param($value) $value }; Log=[Collections.Generic.List[string]]::new()
    }
    $env:DOCKER_CONTEXT='desktop-linux'
    $env:DOCKER_HOST='tcp://external.invalid:2376'
    Expect-Rejection { Invoke-FinancialRecovery @invokeParameters }
    if ($script:recoveryNativeCalls -ne 0) { throw 'Inherited Docker host was not rejected before native commands.' }
    Remove-Item Env:DOCKER_HOST -ErrorAction SilentlyContinue
    Expect-Rejection { Invoke-FinancialRecovery @invokeParameters }
    if ($script:recoveryNativeCalls -ne 1) { throw 'Nonlocal endpoint was not rejected before Docker mutations.' }
    $script:recoveryEndpointJson='"npipe:////external.invalid/pipe/docker_engine"'
    Expect-Rejection { Invoke-FinancialRecovery @invokeParameters }
    if ($script:recoveryNativeCalls -ne 2) { throw 'Remote named pipe was not rejected before Docker mutations.' }
    $script:baselineNativeCalls=[Collections.Generic.List[string]]::new()
    $sameHead=$invokeParameters.Clone()
    $sameHead.Native={
        param($FilePath,$Arguments,[switch]$Capture)
        $script:baselineNativeCalls.Add($FilePath + ' ' + ($Arguments -join ' '))
        if($FilePath -ceq 'docker'){return '"npipe:////./pipe/dockerDesktopLinuxEngine"'}
        if($FilePath -ceq 'git'){return ('a'*40)}
        throw 'Unexpected native operation before baseline validation'
    }
    Expect-Rejection { Invoke-FinancialRecovery @sameHead }
    if($script:baselineNativeCalls.Count -ne 3){throw 'Historical HEAD must be rejected before Docker inventory/mutations.'}
    # Exercise the runner's actual preflight as well, with metadata-only stubs.
    $tokens=$null; $errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'run-control-plane.ps1'),[ref]$tokens,[ref]$errors)
    if ($errors.Count -ne 0) { throw 'Runner AST is invalid.' }
    $definition=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Assert-LocalDockerTarget'},$false)
    Invoke-Expression $definition.Extent.Text
    function Invoke-Native {
        param($FilePath,$Arguments,[switch]$Capture)
        if ($Arguments[0] -ceq 'context' -and $Arguments[1] -ceq 'show') { return 'desktop-linux' }
        if ($Arguments[0] -ceq 'context' -and $Arguments[1] -ceq 'inspect') { return $script:recoveryEndpointJson }
        if ($Arguments[-1] -ceq '{{.OSType}}') { return 'linux' }
        throw 'Unexpected native operation in local Docker preflight contract.'
    }
    foreach ($rejectedEndpoint in @('tcp://external.invalid:2376','npipe:////external.invalid/pipe/docker_engine')) {
        $script:recoveryEndpointJson=ConvertTo-Json $rejectedEndpoint -Compress
        Expect-Rejection { Assert-LocalDockerTarget }
    }
    foreach ($allowedEndpoint in @('npipe:////./pipe/docker_engine','npipe:////./pipe/dockerDesktopLinuxEngine','unix:///var/run/docker.sock')) {
        $script:recoveryEndpointJson=ConvertTo-Json $allowedEndpoint -Compress
        if ((Assert-LocalDockerTarget) -cne 'desktop-linux') { throw 'Allowed local Docker endpoint was rejected.' }
    }

    # Real Compose parsing only: no engine, containers or remote endpoint calls.
    # This proves resolved dollars remain literal while rollback can override ID.
    $fixture = @{
        name=$project;
        services=@{
            backend=@{image='original:local';build=@{context='.'};environment=@{SYNTHETIC_LITERAL='$$literal';BACKEND_HEALTHCHECK_MODE='actuator-readiness-v1'};healthcheck=@{test=@('CMD-SHELL','echo $$VALUE')}};
            frontend=@{image='frontend:local';build=@{context='.'}}
        }
    }
    [IO.File]::WriteAllText($compose,($fixture | ConvertTo-Json -Depth 12),[Text.UTF8Encoding]::new($false))
    $originalOutput=@(& docker compose -f $compose --env-file $envFile config --format json 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic original Compose does not parse.' }
    $canonicalOriginal=($originalOutput -join "`n")
    $original=$canonicalOriginal | ConvertFrom-Json
    $converted=ConvertTo-FinancialRecoveryCompose $canonicalOriginal
    [IO.File]::WriteAllText($compose,$converted,[Text.UTF8Encoding]::new($false))
    $env:BACKEND_IMAGE='backend:overridden'
    $output = @(& docker compose -f $compose --env-file $envFile config --format json 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'Recovery canonical Compose does not parse.' }
    $parsed=($output -join "`n") | ConvertFrom-Json
    if ($parsed.services.backend.image -cne 'backend:overridden' -or
        $parsed.services.backend.environment.SYNTHETIC_LITERAL -cne $original.services.backend.environment.SYNTHETIC_LITERAL -or
        $parsed.services.backend.healthcheck.test[1] -cne $original.services.backend.healthcheck.test[1] -or
        $parsed.services.backend.PSObject.Properties.Name -contains 'build') { throw 'Recovery Compose substitution contract failed.' }
    $hash=Get-RecoveryTextSha256 'abc'
    if ($hash -cne 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad') { throw 'Recovery text SHA256 vector mismatch.' }
    Write-Host 'PASS: recovery scope, inherited daemon denial, literal Compose config and exact image override (no engine mutations)'
}
finally {
    [Environment]::SetEnvironmentVariable('DOCKER_HOST',$previousHost,'Process')
    [Environment]::SetEnvironmentVariable('DOCKER_CONTEXT',$previousContext,'Process')
    [Environment]::SetEnvironmentVariable('BACKEND_IMAGE',$previousBackend,'Process')
    $checked=[IO.Path]::GetFullPath($root)
    $tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if (-not $checked.StartsWith($tempPrefix,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $checked -Leaf) -cne $project) { throw 'Contract cleanup scope mismatch.' }
    Remove-Item -LiteralPath $checked -Recurse -Force
}
