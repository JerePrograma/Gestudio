function Sync-DatabasePassword {
    $databaseUser = Get-EnvironmentValue "POSTGRES_USER"
    $databasePassword = Get-EnvironmentValue "POSTGRES_PASSWORD"
    $encodedPassword = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($databasePassword))
    Add-Secret $encodedPassword

    $sql = @"
\set runtime_password_base64 $encodedPassword
SELECT format(
    'ALTER ROLE %I PASSWORD %L',
    '$databaseUser',
    convert_from(decode(:'runtime_password_base64', 'base64'), 'UTF8')
) \gexec
"@
    Invoke-PsqlInput -InputText $sql | Out-Null
}

function Invoke-PsqlInput {
    param(
        [Parameter(Mandatory)][string] $InputText,
        [switch] $TuplesOnly
    )

    Assert-Deadline
    $database = Get-EnvironmentValue "POSTGRES_DB"
    $user = Get-EnvironmentValue "POSTGRES_USER"
    $escapedCompose = $script:composeFile.Replace('"', '\"')
    $escapedRemoteCompose = $script:remoteComposeFile.Replace('"', '\"')
    $escapedEnv = $script:envPath.Replace('"', '\"')
    $formatArguments = if ($TuplesOnly) { ' -A -t -F "|"' } else { "" }

    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = "docker"
    $psi.Arguments = "compose -f `"$escapedCompose`" -f `"$escapedRemoteCompose`" --env-file `"$escapedEnv`" -p $($script:project) exec -T db psql -X -q -v ON_ERROR_STOP=1 -U `"$user`" -d `"$database`"$formatArguments"
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    if ($psi.PSObject.Properties.Name -contains "StandardInputEncoding") {
        $psi.StandardInputEncoding = New-Object Text.UTF8Encoding($false)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $psi
    [void]$process.Start()
    try {
        $process.StandardInput.Write($InputText)
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        $code = $process.ExitCode
    }
    finally { $process.Dispose() }

    $text = ($stdout + "`n" + $stderr).Trim()
    if ($code -ne 0) {
        throw "psql falló con código ${code}: $(Redact $text)"
    }
    return $text
}

function Invoke-Sql {
    param([Parameter(Mandatory)][string] $Query)

    return Invoke-PsqlInput -InputText ($Query + "`n") -TuplesOnly
}

function Get-BusinessDate {
    try { $zone = [TimeZoneInfo]::FindSystemTimeZoneById("America/Argentina/Buenos_Aires") }
    catch { $zone = [TimeZoneInfo]::FindSystemTimeZoneById("Argentina Standard Time") }
    return [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $zone).Date
}

function Get-LocalMigrationManifest {
    $entries = @(Get-ChildItem -LiteralPath $script:migrationRoot -Filter "V*__*.sql" -File | ForEach-Object {
        if ($_.Name -notmatch '^V(?<version>[0-9]+)__.+\.sql$') {
            throw "Nombre de migración Flyway inválido: $($_.Name)"
        }
        [pscustomobject]@{ Version = [int]$matches.version; Script = $_.Name }
    } | Sort-Object Version)
    if ($entries.Count -eq 0) { throw "No hay migraciones Flyway locales" }
    if (@($entries.Version | Select-Object -Unique).Count -ne $entries.Count) { throw "Hay versiones Flyway duplicadas" }
    for ($index = 0; $index -lt $entries.Count; $index++) {
        if ($entries[$index].Version -ne ($index + 1)) { throw "La cadena Flyway no es contigua desde V1" }
    }
    if (@($entries | Where-Object { $_.Script -match '(?i)demo.*seed|seed.*demo' }).Count -ne 0) {
        throw "Existe una migración Flyway demo"
    }
    return [pscustomobject]@{
        Count = $entries.Count
        LatestVersion = $entries[-1].Version
        Scripts = @($entries.Script)
    }
}

function Assert-FlywayHistory {
    $manifest = Get-LocalMigrationManifest
    $history = (Invoke-Sql @"
SELECT count(*) || '|' || COALESCE(max(version::int), 0) || '|' || count(*) FILTER (WHERE NOT success)
FROM flyway_schema_history;
"@).Split("|")
    Assert-Equal $history.Count 3 "Historial Flyway ilegible"
    Assert-Equal $history[0] ([string]$manifest.Count) "Cantidad Flyway inesperada"
    Assert-Equal $history[1] ([string]$manifest.LatestVersion) "Última versión Flyway inesperada"
    Assert-Equal $history[2] "0" "Hay migraciones Flyway fallidas"

    $historyScripts = @((Invoke-Sql "SELECT script FROM flyway_schema_history WHERE success ORDER BY installed_rank;") -split "`r?`n" |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    Assert-Equal $historyScripts.Count $manifest.Count "Cantidad de scripts Flyway inesperada"
    if (@(Compare-Object -ReferenceObject $manifest.Scripts -DifferenceObject $historyScripts).Count -ne 0) {
        throw "El historial Flyway no coincide con el manifiesto local"
    }

    Pass "Flyway" "$($manifest.Count) migraciones; última V$($manifest.LatestVersion)"
}

function Assert-DatabaseEmptyForDemo {
    Invoke-PsqlInput -InputText @'
DO $$
DECLARE
    table_name text;
    has_rows boolean;
BEGIN
    FOR table_name IN
        SELECT tablename
        FROM pg_tables
        WHERE schemaname = 'public'
          AND tablename NOT IN ('flyway_schema_history', 'roles', 'permisos', 'rol_permisos')
        ORDER BY tablename
    LOOP
        EXECUTE format('SELECT EXISTS (SELECT 1 FROM public.%I)', table_name) INTO has_rows;
        IF has_rows THEN
            RAISE EXCEPTION 'La base contiene datos preservables en public.%', table_name;
        END IF;
    END LOOP;
END
$$;
'@ | Out-Null
}

function Test-DemoSeedContract {
    if (-not (Test-Path -LiteralPath $script:seedContractPath -PathType Leaf)) {
        throw "Falta contrato SQL del seed remoto: $($script:seedContractPath)"
    }
    $query = [IO.File]::ReadAllText($script:seedContractPath)
    $result = Invoke-Sql $query
    return $result -eq "true"
}
