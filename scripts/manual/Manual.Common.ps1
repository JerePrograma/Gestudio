Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ManualDemoCredentialVariables = [ordered]@{
    'demo-superadmin'   = 'GESTUDIO_DEMO_SUPERADMIN_PASSWORD'
    'demo-direccion'    = 'GESTUDIO_DEMO_DIRECCION_PASSWORD'
    'demo-administrador'= 'GESTUDIO_DEMO_ADMINISTRADOR_PASSWORD'
    'demo-secretaria'   = 'GESTUDIO_DEMO_SECRETARIA_PASSWORD'
    'demo-caja'         = 'GESTUDIO_DEMO_CAJA_PASSWORD'
}

$script:ManualDemoAccountIds = [ordered]@{
    'demo-superadmin'    = 'alpha-superadmin'
    'demo-direccion'     = 'alpha-direccion'
    'demo-administrador' = 'alpha-administrador-funcional'
    'demo-secretaria'    = 'alpha-secretaria'
    'demo-caja'          = 'alpha-caja'
}

function Get-ManualDemoAccountData {
    [CmdletBinding()]
    param()

    $repoRoot = Get-ManualRepositoryRoot
    $path = Join-Path $repoRoot 'docs\manual-usuarios\data\demo-accounts.json'

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Falta la fuente autorizada de cuentas demo: $path"
    }

    $data = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($null -eq $data.accounts -or @($data.accounts).Count -ne 9) {
        throw 'La fuente de cuentas demo debe declarar exactamente nueve cuentas.'
    }

    return $data
}

function Get-ManualRepositoryRoot {
    [CmdletBinding()]
    param()

    return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
}

function Get-CurrentPowerShellExecutable {
    [CmdletBinding()]
    param()

    $process = Get-Process -Id $PID
    if ([string]::IsNullOrWhiteSpace($process.Path)) {
        throw 'No se pudo resolver el ejecutable actual de PowerShell.'
    }

    return $process.Path
}

function Invoke-ManualNativeCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string[]]$Arguments = @(),

        [switch]$CaptureOutput,

        [switch]$AllowFailure
    )

    $previousErrorActionPreference = $ErrorActionPreference
    $output = @()
    $exitCode = 0

    try {
        $ErrorActionPreference = 'Continue'

        if ($CaptureOutput) {
            $output = @(& $FilePath @Arguments 2>&1)
        }
        else {
            & $FilePath @Arguments
        }

        $exitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorActionPreference
    }

    $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine

    if (-not $AllowFailure -and $exitCode -ne 0) {
        $commandName = [IO.Path]::GetFileName($FilePath)
        $suffix = if ([string]::IsNullOrWhiteSpace($text)) { '' } else {
            " Salida: $($text.Trim())"
        }

        throw "$commandName falló con código $exitCode.$suffix"
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $text.Trim()
    }
}

function Invoke-ManualPowerShellFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string[]]$Arguments = @(),

        [switch]$CaptureOutput,

        [switch]$AllowFailure
    )

    $powershell = Get-CurrentPowerShellExecutable
    $nativeArguments = @(
        '-NoProfile'
        '-ExecutionPolicy'
        'Bypass'
        '-File'
        $Path
    ) + $Arguments

    return Invoke-ManualNativeCommand `
        -FilePath $powershell `
        -Arguments $nativeArguments `
        -CaptureOutput:$CaptureOutput `
        -AllowFailure:$AllowFailure
}


function Invoke-ManualDemoScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [ValidateSet('Start', 'Status', 'Stop')]
        [string]$Action,

        [switch]$AllowFailure
    )

    # The persistent multitenant fixture owns its private credentials and needs
    # PowerShell 7. Never pipe the public manual's credentials into that fixture.
    return Invoke-ManualNativeCommand -FilePath 'pwsh' -Arguments @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Path, '-Action', $Action
    ) -AllowFailure:$AllowFailure
}

function Get-ManualLocalCredentialManifestPath {
    [CmdletBinding()]
    param()

    $localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localData)) {
        throw 'No se pudo resolver el estado privado del fixture local.'
    }
    return Join-Path $localData 'Gestudio\gestudio-demo-local\credentials.json'
}

function Test-ManualLocalUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [uri]$Uri
    )

    return $Uri.Scheme -in @('http', 'https') -and
        $Uri.Host -in @('localhost', '127.0.0.1', '::1')
}

function ConvertFrom-ManualSecureString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [Security.SecureString]$SecureValue
    )

    $pointer = [IntPtr]::Zero

    try {
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    finally {
        if ($pointer -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
        }
    }
}

function Set-MissingManualDemoCredentials {
    [CmdletBinding()]
    param()

    $data = Get-ManualDemoAccountData

    foreach ($entry in $script:ManualDemoCredentialVariables.GetEnumerator()) {
        $current = [Environment]::GetEnvironmentVariable($entry.Value, 'Process')
        if (-not [string]::IsNullOrWhiteSpace($current)) {
            continue
        }

        $accountId = [string]$script:ManualDemoAccountIds[$entry.Key]
        $account = @($data.accounts | Where-Object { [string]$_.id -ceq $accountId }) |
            Select-Object -First 1

        if ($null -eq $account -or [string]::IsNullOrWhiteSpace([string]$account.password)) {
            throw "La cuenta demo autorizada '$accountId' no define contraseña."
        }

        $plain = [string]$account.password
        $byteCount = [Text.Encoding]::UTF8.GetByteCount($plain)
        if ($byteCount -gt 72) {
            throw "La contraseña documentada para $($entry.Key) supera los 72 bytes admitidos por BCrypt."
        }

        [Environment]::SetEnvironmentVariable($entry.Value, $plain, 'Process')
        $plain = $null
    }
}

function Assert-ManualDemoCredentials {
    [CmdletBinding()]
    param()

    foreach ($entry in $script:ManualDemoCredentialVariables.GetEnumerator()) {
        $value = [Environment]::GetEnvironmentVariable($entry.Value, 'Process')

        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Falta la variable $($entry.Value)."
        }

        if ([Text.Encoding]::UTF8.GetByteCount($value) -gt 72) {
            throw "La variable $($entry.Value) supera los 72 bytes admitidos por BCrypt."
        }
    }
}

function Get-ManualRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$Path
    )

    $baseUri = [uri](([IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar))
    $pathUri = [uri]([IO.Path]::GetFullPath($Path))
    return [uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', [IO.Path]::DirectorySeparatorChar)
}

function Resolve-ManualPlaywrightRuntime {
    [CmdletBinding()]
    param()

    $repoRoot = Get-ManualRepositoryRoot
    $candidates = [Collections.Generic.List[string]]::new()
    $configuredNodePath = [Environment]::GetEnvironmentVariable('NODE_PATH', 'Process')

    if (-not [string]::IsNullOrWhiteSpace($configuredNodePath)) {
        foreach ($entry in $configuredNodePath -split [IO.Path]::PathSeparator) {
            if (-not [string]::IsNullOrWhiteSpace($entry)) {
                $candidates.Add([IO.Path]::GetFullPath($entry))
            }
        }
    }

    $candidates.Add((Join-Path $repoRoot 'frontend\node_modules'))

    foreach ($nodeModules in @($candidates | Select-Object -Unique)) {
        $packagePath = Join-Path $nodeModules 'playwright\package.json'
        $cliPath = Join-Path $nodeModules 'playwright\cli.js'
        if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf) -or
            -not (Test-Path -LiteralPath $cliPath -PathType Leaf)) {
            continue
        }

        $package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json
        return [pscustomobject]@{
            NodeModules = [IO.Path]::GetFullPath($nodeModules)
            CliPath = [IO.Path]::GetFullPath($cliPath)
            Version = [string]$package.version
        }
    }

    throw 'No se encontró Playwright. Ejecute npm ci dentro de frontend o use Build-Manual.ps1 para preparar el runtime aislado.'
}

function Set-ManualNodePathForRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$NodeModules,
        [AllowNull()][string]$PreviousNodePath
    )

    $value = [IO.Path]::GetFullPath($NodeModules)
    if (-not [string]::IsNullOrWhiteSpace($PreviousNodePath)) {
        $entries = @($PreviousNodePath -split [IO.Path]::PathSeparator)
        if ($entries -notcontains $value) {
            $value += [IO.Path]::PathSeparator + $PreviousNodePath
        }
        else {
            $value = $PreviousNodePath
        }
    }

    [Environment]::SetEnvironmentVariable('NODE_PATH', $value, 'Process')
}

function Test-ManualPathInside {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Parent,

        [Parameter(Mandatory)]
        [string]$Candidate
    )

    $parentFull = [IO.Path]::GetFullPath($Parent).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $candidateFull = [IO.Path]::GetFullPath($Candidate)

    return $candidateFull.StartsWith(
        $parentFull,
        [StringComparison]::OrdinalIgnoreCase
    )
}
