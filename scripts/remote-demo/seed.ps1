function Invoke-DemoSeed {
    $manifest = Get-LocalMigrationManifest
    $businessDate = Get-BusinessDate
    $seed = [IO.File]::ReadAllText($script:seedPath)
    $input = @(
        "\set ON_ERROR_STOP on",
        "\set demo_anchor_date $($businessDate.ToString('yyyy-MM-dd'))",
        "\set demo_business_date $($businessDate.ToString('yyyy-MM-dd'))",
        "\set demo_expected_flyway_count $($manifest.Count)",
        "\set demo_expected_flyway_latest $($manifest.LatestVersion)",
        "\set demo_superadmin_password_hash $($script:demoHashes['demo-superadmin'])",
        "\set demo_direccion_password_hash $($script:demoHashes['demo-direccion'])",
        "\set demo_administrador_password_hash $($script:demoHashes['demo-administrador'])",
        "\set demo_secretaria_password_hash $($script:demoHashes['demo-secretaria'])",
        "\set demo_caja_password_hash $($script:demoHashes['demo-caja'])",
        $seed
    ) -join "`n"
    $output = Invoke-PsqlInput ($input + "`n")
    Assert-True ($output -match "GESTUDIO DEMO SEED: ejecución completada y validada") "El seed no emitió su confirmación canónica"
}

function Initialize-DemoSeedIfRequired {
    $userCountRaw = Invoke-Sql "SELECT count(*) FROM usuarios WHERE lower(nombre_usuario) LIKE 'demo-%';"
    $userCount = [int]$userCountRaw
    if ($userCount -eq 5 -and (Test-DemoSeedContract)) {
        Pass "Dataset demo" "existente y compatible"
        return
    }
    if ($userCount -ne 0) {
        throw "La base contiene un namespace demo parcial o incompatible; use Reset para recrearla"
    }

    Assert-DatabaseEmptyForDemo
    $script:tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("gestudio-demo-remote-$PID-" + ([Guid]::NewGuid().ToString("N").Substring(0, 8)))
    New-Item -ItemType Directory -Path $script:tempRoot -Force | Out-Null
    Write-Host "La base remota está vacía. Se solicitarán cinco contraseñas demo distintas." -ForegroundColor Yellow
    Read-DemoPasswords
    Initialize-BcryptHelper
    New-BcryptHashes
    Invoke-DemoSeed
    Assert-True (Test-DemoSeedContract) "El dataset demo remoto no satisface el contrato canónico"
    Pass "Dataset demo" "914 filas sintéticas y cinco roles inicializados"
}
