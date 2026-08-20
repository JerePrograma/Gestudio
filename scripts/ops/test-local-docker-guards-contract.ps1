[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$targets = @(
    [pscustomobject]@{
        Path = 'scripts/deploy/deploy.ps1'
        FirstDockerMarker = "`$null = Invoke-CheckedNative -FilePath 'docker' -Arguments @('version')"
    },
    [pscustomobject]@{
        Path = 'scripts/deploy/test-idempotency.ps1'
        FirstDockerMarker = "`$null = Invoke-Native docker @('version')"
    },
    [pscustomobject]@{
        Path = 'scripts/ops/verify-backup-restore.ps1'
        FirstDockerMarker = "Invoke-Native -FilePath 'docker' -Arguments @('info', '--format', '{{.ServerVersion}}')"
    },
    [pscustomobject]@{
        Path = 'scripts/ops/verify-observability.ps1'
        FirstDockerMarker = "Invoke-Native -FilePath 'docker' -Arguments @('info', '--format', '{{.ServerVersion}}')"
    },
    [pscustomobject]@{
        Path = 'scripts/smoke-local.ps1'
        FirstDockerMarker = 'Invoke-Docker -Arguments @("info", "--format", "{{.ServerVersion}}")'
    },
    [pscustomobject]@{
        Path = 'scripts/demo-local.ps1'
        FirstDockerMarker = 'switch ($Action)'
    }
)

$script:passes = 0
$script:fakeCalls = 0
$script:fakeContext = 'default'
$script:fakeEndpoint = 'npipe:////./pipe/docker_engine'
$script:fakeOsType = 'linux'
$script:guardAcceptsProjectName = $false
$script:project = 'gestudio-contract-local'

function Assert-Contract {
    param([Parameter(Mandatory)][bool] $Condition, [Parameter(Mandatory)][string] $Message)

    if (-not $Condition) { throw $Message }
    $script:passes++
}

function Test-IsInsideFunction {
    param([Parameter(Mandatory)] $Node)

    $parent = $Node.Parent
    while ($null -ne $parent) {
        if ($parent -is [Management.Automation.Language.FunctionDefinitionAst]) { return $true }
        $parent = $parent.Parent
    }
    return $false
}

function Invoke-FakeDocker {
    param([Parameter(Mandatory)][string[]] $Arguments)

    $script:fakeCalls++
    if ($Arguments.Count -ge 2 -and $Arguments[0] -ceq 'context' -and $Arguments[1] -ceq 'show') {
        return $script:fakeContext
    }
    if ($Arguments.Count -ge 2 -and $Arguments[0] -ceq 'context' -and $Arguments[1] -ceq 'inspect') {
        return '"' + $script:fakeEndpoint + '"'
    }
    if ($Arguments.Count -ge 3 -and $Arguments[0] -ceq '--context' -and $Arguments[2] -ceq 'info') {
        return $script:fakeOsType
    }
    throw "Fake Docker recibio argumentos inesperados: $($Arguments -join ' ')"
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [switch] $IgnoreFailure
    )

    return Invoke-FakeDocker -Arguments $Arguments
}

function Invoke-CheckedNative {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [Parameter(Mandatory)][int] $FailureExitCode,
        [switch] $Capture
    )

    return Invoke-FakeDocker -Arguments $Arguments
}

function Invoke-Docker {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [switch] $IgnoreDeadline
    )

    return Invoke-FakeDocker -Arguments $Arguments
}

function New-DeployFailure {
    param([Parameter(Mandatory)][string] $Message, [Parameter(Mandatory)][int] $ExitCode)

    $exception = [InvalidOperationException]::new($Message)
    $exception.Data['ExitCode'] = $ExitCode
    return $exception
}

function docker {
    throw 'El contrato no debe invocar un Docker real.'
}

function Invoke-SelectedGuard {
    param([Parameter(Mandatory)][string] $ProjectName)

    $script:project = $ProjectName
    if ($script:guardAcceptsProjectName) {
        return Assert-LocalDockerTarget -ProjectName $ProjectName
    }
    return Assert-LocalDockerTarget
}

function Assert-GuardFails {
    param(
        [Parameter(Mandatory)][string] $ProjectName,
        [Parameter(Mandatory)][string] $MessagePattern,
        [Parameter(Mandatory)][string] $Case
    )

    $message = $null
    try { $null = Invoke-SelectedGuard -ProjectName $ProjectName }
    catch { $message = $_.Exception.Message }
    Assert-Contract -Condition (-not [string]::IsNullOrWhiteSpace($message)) -Message "$Case no fue rechazado."
    Assert-Contract -Condition ($message -match $MessagePattern) -Message "$Case devolvio un error inesperado: $message"
}

$originalDockerHost = [Environment]::GetEnvironmentVariable('DOCKER_HOST', 'Process')
try {
    foreach ($target in $targets) {
        $path = Join-Path $repoRoot $target.Path
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
        Assert-Contract -Condition ($parseErrors.Count -eq 0) -Message "$($target.Path) no parsea."

        $guards = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'Assert-LocalDockerTarget'
        }, $true))
        Assert-Contract -Condition ($guards.Count -eq 1) -Message "$($target.Path) debe definir un unico Assert-LocalDockerTarget."

        $guardCalls = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -ceq 'Assert-LocalDockerTarget'
        }, $true) | Where-Object { -not (Test-IsInsideFunction -Node $_) })
        Assert-Contract -Condition ($guardCalls.Count -eq 1) -Message "$($target.Path) debe invocar el guard una vez desde el flujo principal."

        $source = [IO.File]::ReadAllText($path)
        $operationOffset = $source.IndexOf($target.FirstDockerMarker, $guardCalls[0].Extent.EndOffset, [StringComparison]::Ordinal)
        Assert-Contract -Condition ($operationOffset -ge $guardCalls[0].Extent.EndOffset) `
            -Message "$($target.Path) no ejecuta el guard antes del primer preflight Docker."

        Invoke-Expression $guards[0].Extent.Text
        $guardParameters = if ($null -eq $guards[0].Body.ParamBlock) { @() } else { @($guards[0].Body.ParamBlock.Parameters) }
        $script:guardAcceptsProjectName = @($guardParameters | Where-Object {
            $_.Name.VariablePath.UserPath -ceq 'ProjectName'
        }).Count -eq 1

        [Environment]::SetEnvironmentVariable('DOCKER_HOST', 'tcp://127.0.0.1:2375', 'Process')
        $script:fakeCalls = 0
        Assert-GuardFails -ProjectName 'gestudio-contract-local' -MessagePattern 'DOCKER_HOST' -Case "$($target.Path): DOCKER_HOST"
        Assert-Contract -Condition ($script:fakeCalls -eq 0) -Message "$($target.Path) consulto Docker con DOCKER_HOST heredado."
        [Environment]::SetEnvironmentVariable('DOCKER_HOST', $null, 'Process')

        $script:fakeCalls = 0
        Assert-GuardFails -ProjectName 'gestudio-remote-demo' -MessagePattern 'gestudio-remote-demo' -Case "$($target.Path): proyecto protegido"
        Assert-Contract -Condition ($script:fakeCalls -eq 0) -Message "$($target.Path) consulto Docker para el proyecto protegido."

        foreach ($forbiddenContext in @('production-west', 'stage', 'remote-ci', 'demo-lab')) {
            $script:fakeContext = $forbiddenContext
            $script:fakeCalls = 0
            Assert-GuardFails -ProjectName 'gestudio-contract-local' -MessagePattern 'contexto Docker' `
                -Case "$($target.Path): contexto $forbiddenContext"
            Assert-Contract -Condition ($script:fakeCalls -eq 1) -Message "$($target.Path) inspecciono un contexto prohibido."
        }

        $script:fakeContext = 'default'
        $script:fakeEndpoint = 'tcp://docker.example.invalid:2376'
        $script:fakeOsType = 'linux'
        $script:fakeCalls = 0
        Assert-GuardFails -ProjectName 'gestudio-contract-local' -MessagePattern 'endpoint|local' -Case "$($target.Path): endpoint remoto"
        Assert-Contract -Condition ($script:fakeCalls -eq 2) -Message "$($target.Path) consulto el daemon con endpoint remoto."

        $script:fakeEndpoint = 'npipe:////./pipe/docker_engine'
        $script:fakeOsType = 'windows'
        $script:fakeCalls = 0
        Assert-GuardFails -ProjectName 'gestudio-contract-local' -MessagePattern 'Linux|OSType' -Case "$($target.Path): daemon Windows"
        Assert-Contract -Condition ($script:fakeCalls -eq 3) -Message "$($target.Path) no valido OSType en el orden esperado."

        foreach ($localEndpoint in @(
            'npipe:////./pipe/docker_engine',
            'npipe:////./pipe/dockerDesktopLinuxEngine',
            'unix:///var/run/docker.sock'
        )) {
            $script:fakeEndpoint = $localEndpoint
            $script:fakeOsType = 'linux'
            $script:fakeCalls = 0
            $actualContext = Invoke-SelectedGuard -ProjectName 'gestudio-contract-local'
            Assert-Contract -Condition ($null -eq $actualContext -or $actualContext -ceq 'default') `
                -Message "$($target.Path) rechazo endpoint local $localEndpoint."
            Assert-Contract -Condition ($script:fakeCalls -eq 3) -Message "$($target.Path) no completo el preflight local."
        }
    }
}
finally {
    [Environment]::SetEnvironmentVariable('DOCKER_HOST', $originalDockerHost, 'Process')
}

Write-Host "PASS: $($targets.Count) guards locales, $script:passes aserciones, Docker real no invocado."
