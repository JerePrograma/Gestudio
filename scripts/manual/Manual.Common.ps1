Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ManualDemoCredentialVariables = [ordered]@{
    'demo-superadmin'   = 'GESTUDIO_DEMO_SUPERADMIN_PASSWORD'
    'demo-direccion'    = 'GESTUDIO_DEMO_DIRECCION_PASSWORD'
    'demo-administrador'= 'GESTUDIO_DEMO_ADMINISTRADOR_PASSWORD'
    'demo-secretaria'   = 'GESTUDIO_DEMO_SECRETARIA_PASSWORD'
    'demo-caja'         = 'GESTUDIO_DEMO_CAJA_PASSWORD'
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
        [ValidateSet('Start', 'Status')]
        [string]$Action,

        [switch]$AllowFailure
    )

    Assert-ManualDemoCredentials

    $powershell = Get-CurrentPowerShellExecutable
    $processInfo = [Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $powershell
    $escapedPath = $Path.Replace('"', '\"')
    $processInfo.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$escapedPath`" -Action $Action"
    $processInfo.UseShellExecute = $false
    $processInfo.RedirectStandardInput = $true
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.CreateNoWindow = $true

    if ($processInfo.PSObject.Properties.Name -contains 'StandardInputEncoding') {
        $processInfo.StandardInputEncoding = New-Object Text.UTF8Encoding($false)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $processInfo
    [void]$process.Start()

    try {
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()

        foreach ($variableName in $script:ManualDemoCredentialVariables.Values) {
            $secret = [Environment]::GetEnvironmentVariable($variableName, 'Process')
            $process.StandardInput.WriteLine($secret)
        }

        $process.StandardInput.Close()
        $process.WaitForExit()

        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
        $exitCode = $process.ExitCode
    }
    finally {
        $secret = $null
        $process.Dispose()
    }

    $combined = ($stdout + [Environment]::NewLine + $stderr).Trim()

    if (-not [string]::IsNullOrWhiteSpace($combined)) {
        Write-Host $combined
    }

    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "scripts/demo-local.ps1 -Action $Action falló con código $exitCode."
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = $combined
    }
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

    foreach ($entry in $script:ManualDemoCredentialVariables.GetEnumerator()) {
        $current = [Environment]::GetEnvironmentVariable($entry.Value, 'Process')
        if (-not [string]::IsNullOrWhiteSpace($current)) {
            continue
        }

        $secure = Read-Host "Contraseña para $($entry.Key)" -AsSecureString

        try {
            $plain = ConvertFrom-ManualSecureString -SecureValue $secure
            $byteCount = [Text.Encoding]::UTF8.GetByteCount($plain)

            if ([string]::IsNullOrWhiteSpace($plain)) {
                throw "La contraseña para $($entry.Key) no puede estar vacía."
            }

            if ($byteCount -gt 72) {
                throw "La contraseña para $($entry.Key) supera los 72 bytes admitidos por BCrypt."
            }

            [Environment]::SetEnvironmentVariable($entry.Value, $plain, 'Process')
        }
        finally {
            $plain = $null
            $secure.Dispose()
        }
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
