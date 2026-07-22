function Add-Secret {
    param([AllowNull()][string] $Value)

    if (-not [string]::IsNullOrEmpty($Value) -and -not $script:secretValues.Contains($Value)) {
        $script:secretValues.Add($Value)
    }
}

function Redact {
    param([AllowNull()][string] $Text)

    if ($null -eq $Text) { return "" }
    $safe = $Text
    foreach ($secret in $script:secretValues) {
        if (-not [string]::IsNullOrEmpty($secret)) {
            $safe = $safe.Replace($secret, "<redacted>")
        }
    }
    return $safe
}

function Pass {
    param([Parameter(Mandatory)][string] $Name, [string] $Detail = "")

    $suffix = if ([string]::IsNullOrWhiteSpace($Detail)) { "" } else { " - $Detail" }
    Write-Host "[PASS] $Name$suffix" -ForegroundColor Green
}

function Assert-True {
    param([bool] $Condition, [Parameter(Mandatory)][string] $Message)

    if (-not $Condition) { throw $Message }
}

function Assert-Equal {
    param($Actual, $Expected, [Parameter(Mandatory)][string] $Message)

    if ($Actual -ne $Expected) {
        throw "$Message (esperado=$Expected, actual=$Actual)"
    }
}

function Assert-Deadline {
    if ((Get-Date) -gt $script:deadline) {
        throw "Se agotó el timeout global de 45 minutos"
    }
}

function Set-ScopedEnvironmentVariable {
    param([Parameter(Mandatory)][string] $Name, [AllowNull()][string] $Value)

    if (-not $script:originalEnvironment.ContainsKey($Name)) {
        $script:originalEnvironment[$Name] = [Environment]::GetEnvironmentVariable($Name, "Process")
    }
    [Environment]::SetEnvironmentVariable($Name, $Value, "Process")
}

function Restore-Environment {
    foreach ($entry in $script:originalEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, "Process")
    }
}

function Invoke-Native {
    param(
        [Parameter(Mandatory)][string] $FilePath,
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [switch] $IgnoreDeadline
    )

    if (-not $IgnoreDeadline) { Assert-Deadline }
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        if ($Capture) {
            $output = @(& $FilePath @Arguments 2>&1)
        }
        else {
            $tail = [Collections.Generic.Queue[string]]::new()
            & $FilePath @Arguments 2>&1 | ForEach-Object {
                $line = Redact $_.ToString()
                Write-Host $line
                $tail.Enqueue($line)
                if ($tail.Count -gt 100) { [void]$tail.Dequeue() }
            }
        }
        $code = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }

    $text = if ($Capture) {
        ($output | ForEach-Object { $_.ToString() }) -join "`n"
    }
    else {
        @($tail) -join "`n"
    }
    if ($code -ne 0) {
        $errorTail = (($text -split "`r?`n") | Select-Object -Last 100) -join "`n"
        throw "$([IO.Path]::GetFileName($FilePath)) falló con código ${code}: $(Redact $errorTail)"
    }
    if ($Capture) { return $text.Trim() }
}

function Invoke-Docker {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [switch] $IgnoreDeadline
    )

    return Invoke-Native -FilePath "docker" -Arguments $Arguments -Capture:$Capture -IgnoreDeadline:$IgnoreDeadline
}

function Get-ComposeArguments {
    param([Parameter(Mandatory)][string[]] $Arguments)

    return @(
        "compose",
        "-f", $script:composeFile,
        "-f", $script:remoteComposeFile,
        "--env-file", $script:envPath,
        "-p", $script:project
    ) + $Arguments
}

function Invoke-Compose {
    param(
        [Parameter(Mandatory)][string[]] $Arguments,
        [switch] $Capture,
        [switch] $IgnoreDeadline
    )

    return Invoke-Docker -Arguments (Get-ComposeArguments -Arguments $Arguments) -Capture:$Capture -IgnoreDeadline:$IgnoreDeadline
}

function Invoke-ProjectDown {
    param([switch] $Volumes)

    $arguments = @(
        "compose",
        "-f", $script:composeFile,
        "-p", $script:project,
        "down"
    )
    if ($Volumes) { $arguments += "--volumes" }
    $arguments += "--remove-orphans"
    Invoke-Docker -Arguments $arguments -Capture -IgnoreDeadline | Out-Null
}

