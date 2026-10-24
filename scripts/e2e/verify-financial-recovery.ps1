# Loaded by the ephemeral E2E runner. Operational helpers retain their normal
# confirmations; this wrapper supplies them only after checking its exact scope.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-FinancialRecoveryCompose {
    param([Parameter(Mandatory)][string] $ConfigJson)
    # Canonical `compose config` already escapes literal dollars for round trips.
    # Retain those escapes; only image/health remain deliberate substitutions.
    $config = $ConfigJson | ConvertFrom-Json
    $config.services.backend.image = '${BACKEND_IMAGE:?required}'
    $config.services.backend.environment.BACKEND_HEALTHCHECK_MODE = '${BACKEND_HEALTHCHECK_MODE:-actuator-readiness-v1}'
    $config.services.backend.PSObject.Properties.Remove('build')
    $config.services.frontend.PSObject.Properties.Remove('build')
    return ($config | ConvertTo-Json -Depth 30)
}

function Assert-FinancialRecoveryScope {
    param([string] $Project, [string] $RunRoot, [string] $ComposeFile, [string] $EnvFile)
    if ($Project -cnotmatch '^gestudio-e2e-[a-f0-9]{12}$') {
        throw 'Recovery requires an exact ephemeral E2E project.'
    }
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
    $resolved = [IO.Path]::GetFullPath($RunRoot).TrimEnd('\', '/')
    if (-not $resolved.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar,
            [StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -cne $Project) {
        throw 'Recovery temporary root is outside its exact ephemeral scope.'
    }
    foreach ($path in @($resolved, $ComposeFile, $EnvFile)) {
        $absolute = [IO.Path]::GetFullPath($path)
        if ($absolute -cne $resolved -and -not $absolute.StartsWith(
                $resolved + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Recovery input is outside its private temporary root.'
        }
        $item = Get-Item -LiteralPath $absolute -ErrorAction Stop
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Recovery rejects reparse points.'
        }
        $parent = Split-Path $absolute -Parent
        while ($parent -and $parent.StartsWith($resolved + [IO.Path]::DirectorySeparatorChar,
                [StringComparison]::OrdinalIgnoreCase)) {
            if (((Get-Item -LiteralPath $parent).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Recovery rejects parent reparse points.'
            }
            $parent = Split-Path $parent -Parent
        }
    }
}

function Get-RecoveryTextSha256 {
    param([Parameter(Mandatory)][string] $Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Invoke-FinancialRecovery {
    param(
        [Parameter(Mandatory)][string] $RepoRoot,
        [Parameter(Mandatory)][string] $RunRoot,
        [Parameter(Mandatory)][string] $ComposeFile,
        [Parameter(Mandatory)][string] $EnvFile,
        [Parameter(Mandatory)][string] $Project,
        [Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{40}$')][string] $HistoricalCommit,
        [Parameter(Mandatory)][string] $CurrentImageId,
        [Parameter(Mandatory)][string] $AlphaCode,
        [Parameter(Mandatory)][string] $BetaCode,
        [Parameter(Mandatory)][scriptblock] $Native,
        [Parameter(Mandatory)][scriptblock] $WritePrivate,
        [Parameter(Mandatory)][scriptblock] $Sanitize,
        [Parameter(Mandatory)][AllowEmptyCollection()] $Log
    )
    Assert-FinancialRecoveryScope -Project $Project -RunRoot $RunRoot -ComposeFile $ComposeFile -EnvFile $EnvFile
    if ($CurrentImageId -cnotmatch '^sha256:[a-f0-9]{64}$' -or
        $AlphaCode -cnotmatch '^danza-marcos-paz-[a-f0-9]{12}$' -or
        $BetaCode -cnotmatch '^beta-e2e-[a-f0-9]{12}$') { throw 'Recovery image or fixture identifiers are invalid.' }
    if ($env:DOCKER_HOST -or -not $env:DOCKER_CONTEXT) { throw 'Recovery requires the pinned local Docker context.' }
    $endpointRaw = & $Native -FilePath docker -Arguments @('context', 'inspect', '--format', '{{json .Endpoints.docker.Host}}', $env:DOCKER_CONTEXT) -Capture
    $endpoint = [string]($endpointRaw | ConvertFrom-Json)
    if ($endpoint -cnotin @('npipe:////./pipe/docker_engine',
            'npipe:////./pipe/dockerDesktopLinuxEngine', 'unix:///var/run/docker.sock')) {
        throw 'Recovery refuses a non-local Docker endpoint.'
    }
    $resolvedHistoricalCommit = (& $Native -FilePath git -Arguments @('-C', $RepoRoot, 'rev-parse', '--verify', ($HistoricalCommit + '^{commit}')) -Capture).Trim()
    $currentHead = (& $Native -FilePath git -Arguments @('-C', $RepoRoot, 'rev-parse', '--verify', 'HEAD') -Capture).Trim()
    if ($resolvedHistoricalCommit -cne $HistoricalCommit -or $resolvedHistoricalCommit -ceq $currentHead) {
        throw 'Historical rollback requires an exact ancestor different from HEAD.'
    }
    [void](& $Native -FilePath git -Arguments @('-C', $RepoRoot, 'merge-base', '--is-ancestor', $resolvedHistoricalCommit, 'HEAD'))
    $prefix = @('compose', '-f', $ComposeFile, '--env-file', $EnvFile, '-p', $Project)
    function Recovery-Compose {
        param([string[]] $Arguments)
        return & $Native -FilePath docker -Arguments ($prefix + $Arguments) -Capture
    }
    function Recovery-Containers {
        param([string] $ExpectedBackendId)
        $db = (Recovery-Compose @('ps', '-q', 'db')).Trim()
        $backend = (Recovery-Compose @('ps', '-q', 'backend')).Trim()
        foreach ($entry in @(@($db, 'db'), @($backend, 'backend'))) {
            if ($entry[0] -cnotmatch '^[a-f0-9]{12,64}$') { throw 'Recovery service container is absent.' }
            $ownership = & $Native -FilePath docker -Arguments @('inspect', '--format', '{{index .Config.Labels "com.docker.compose.project"}}|{{index .Config.Labels "com.docker.compose.service"}}', $entry[0]) -Capture
            if ($ownership -cne "$Project|$($entry[1])") { throw 'Recovery container ownership mismatch.' }
        }
        $actualId = & $Native -FilePath docker -Arguments @('inspect', '--format', '{{.Image}}', $backend) -Capture
        if ($actualId -cne $ExpectedBackendId) { throw 'Recovery backend image identity mismatch.' }
        return @($db, $backend)
    }
    function Recovery-Sql {
        param([string] $Sql, [string] $Database = '')
        $base64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Sql))
        $sqlArguments = @('exec', '-T', 'db', 'sh', '-ec',
            'printf "%s" "$1" | base64 -d | PGPASSWORD="$POSTGRES_PASSWORD" psql --set=ON_ERROR_STOP=1 --no-psqlrc --tuples-only --no-align --username="$POSTGRES_USER" --dbname="${2:-$POSTGRES_DB}" --file=-', 'sh', $base64)
        if ($Database) { $sqlArguments += $Database }
        return (Recovery-Compose $sqlArguments).Trim()
    }
    function Recovery-Wait {
        param([string] $ExpectedBackendId)
        [void](Recovery-Compose @('up', '-d', '--no-build', '--wait', '--wait-timeout', '240', 'backend'))
        [void](Recovery-Containers -ExpectedBackendId $ExpectedBackendId)
    }
    function Recovery-Ops {
        param([string] $Script, [hashtable] $Parameters)
        $output = @(& $Script @Parameters *>&1 | ForEach-Object {
            $Log.Add((& $Sanitize ([string]$_)))
            if ($_ -is [Management.Automation.ErrorRecord]) { throw $_ }
            if ($_ -isnot [Management.Automation.InformationRecord] -and
                $_ -isnot [Management.Automation.WarningRecord] -and
                $_ -isnot [Management.Automation.VerboseRecord] -and
                $_ -isnot [Management.Automation.DebugRecord]) { [string]$_ }
        })
        return $output
    }
    $containers = Recovery-Containers -ExpectedBackendId $CurrentImageId
    $sourceDatabase = Recovery-Sql 'SELECT current_database()'
    if ($sourceDatabase -cne ('gestudio_e2e_' + $Project.Substring('gestudio-e2e-'.Length))) {
        throw 'Recovery database is not the exact synthetic E2E database.'
    }
    $config = Get-Content -LiteralPath $ComposeFile -Raw | ConvertFrom-Json
    foreach ($property in @{ APP_BOOTSTRAP_SUPERADMIN_ENABLED='false'; APP_SCHEDULING_ENABLED='false'; APP_EMAIL_ENABLED='false'; APP_EMAIL_PROVIDER='NOOP'; APP_EMAIL_REAL_NETWORK_ALLOWED='false'; APP_EMAIL_KILL_SWITCH='true' }.GetEnumerator()) {
        if ($config.services.backend.environment.($property.Key) -cne $property.Value) { throw 'Recovery safety configuration mismatch.' }
    }
    $financialSql = @'
SELECT jsonb_build_object(
 'students',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM alumnos x),
 'enrollments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM inscripciones x),
 'monthly',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM mensualidades x),
 'registration',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM matriculas x),
 'charges',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM cargos x),
 'snapshots',(SELECT jsonb_agg(to_jsonb(x) ORDER BY cargo_id) FROM cargo_liquidaciones x),
 'payments',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM pagos x),
 'applications',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM aplicaciones_pago x),
 'cash',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM movimientos_caja x),
 'receipts',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM recibos x),
 'outbox',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM recibos_pendientes x),
 'flyway',(SELECT jsonb_agg(to_jsonb(x) ORDER BY installed_rank) FROM flyway_schema_history x),
 'tenants',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM tenants x),
 'users',(SELECT jsonb_agg((to_jsonb(x)-'contrasena') || jsonb_build_object('passwordDigest',md5(contrasena)) ORDER BY id) FROM usuarios x),
 'memberships',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM tenant_memberships x),
 'membershipRoles',(SELECT jsonb_agg(to_jsonb(x) ORDER BY membership_id,role_id) FROM tenant_membership_roles x),
 'roles',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM roles x),
 'permissions',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM permisos x),
 'rolePermissions',(SELECT jsonb_agg(to_jsonb(x) ORDER BY rol_id,permiso_id) FROM rol_permisos x),
 'platformAdmins',(SELECT jsonb_agg(to_jsonb(x) ORDER BY usuario_id) FROM platform_admins x),
 'mfa',(SELECT jsonb_agg((to_jsonb(x)-'secret_ciphertext'-'last_counter'-'last_used_at') || jsonb_build_object('cipherDigest',md5(encode(secret_ciphertext,'hex'))) ORDER BY id) FROM platform_mfa_credentials x),
 'recoveryCodes',(SELECT jsonb_agg((to_jsonb(x)-'code_hash') || jsonb_build_object('codeDigest',md5(code_hash)) ORDER BY id) FROM platform_recovery_codes x),
 'platformAudit',(SELECT jsonb_agg(to_jsonb(x) ORDER BY id) FROM platform_audit_events x)
)::text;
'@
    $financialBefore = Recovery-Sql $financialSql
    $fixture = Recovery-Sql @"
SELECT jsonb_build_object('project','$Project',
 'alphaId',(SELECT id::text FROM tenants WHERE code='$AlphaCode'),
 'betaId',(SELECT id::text FROM tenants WHERE code='$BetaCode'),
 'paymentId',p.id,'studentId',p.alumno_id,'paymentDate',p.fecha::text,
 'storageKey',r.storage_key,
 'applications',(SELECT jsonb_agg(jsonb_build_object('cargoId',a.cargo_id,'amount',a.importe_aplicado::text) ORDER BY a.id) FROM aplicaciones_pago a WHERE a.pago_id=p.id))
FROM pagos p JOIN recibos r ON r.pago_id=p.id;
"@ | ConvertFrom-Json
    if ($fixture -is [array] -or $fixture.storageKey -cnotmatch ('^' + [regex]::Escape($fixture.alphaId) + '/recibos/recibo_' + $fixture.paymentId + '\.pdf$')) {
        throw 'Recovery requires one real namespaced PDF linked to its payment.'
    }
    $pdfPath = '/app/data/receipts/' + $fixture.storageKey
    $pdfHashRaw = & $Native -FilePath docker -Arguments @('exec', $containers[1], 'sha256sum', $pdfPath) -Capture
    $pdfHash = ($pdfHashRaw -split '\s+')[0]
    if ($pdfHash -cnotmatch '^[a-f0-9]{64}$') { throw 'Recovery PDF hash is invalid.' }
    $fixture | Add-Member -NotePropertyName pdfSha256 -NotePropertyValue $pdfHash
    $fixturePath = Join-Path $RunRoot 'financial-recovery-fixture.json'
    & $WritePrivate -Path $fixturePath -Content ($fixture | ConvertTo-Json -Depth 8)
    function Recovery-Accept {
        param([string] $Phase, [string] $ExpectedBackendId)
        [void](Recovery-Containers -ExpectedBackendId $ExpectedBackendId)
        if ((Recovery-Sql $financialSql) -cne $financialBefore) { throw "Recovery financial/Flyway snapshot mismatch in $Phase." }
        $counter = Recovery-Sql 'SELECT coalesce(max(last_counter),0) FROM platform_mfa_credentials WHERE revoked_at IS NULL'
        $oldFixture = [Environment]::GetEnvironmentVariable('GESTUDIO_RECOVERY_FIXTURE', 'Process')
        $oldCounter = [Environment]::GetEnvironmentVariable('GESTUDIO_RECOVERY_MIN_COUNTER', 'Process')
        try {
            $env:GESTUDIO_RECOVERY_FIXTURE = $fixturePath
            $env:GESTUDIO_RECOVERY_MIN_COUNTER = $counter
            $output = & $Native -FilePath node -Arguments @((Join-Path $RepoRoot 'frontend/scripts/verify-financial-recovery.mjs')) -Capture
            $Log.Add("${Phase}: $output")
        }
        finally {
            [Environment]::SetEnvironmentVariable('GESTUDIO_RECOVERY_FIXTURE', $oldFixture, 'Process')
            [Environment]::SetEnvironmentVariable('GESTUDIO_RECOVERY_MIN_COUNTER', $oldCounter, 'Process')
        }
        $noDelivery = Recovery-Sql 'SELECT count(*) FROM recibos WHERE enviado_at IS NOT NULL'
        if ($noDelivery -cne '0') { throw 'Recovery produced an unexpected email delivery.' }
    }
    $backupRoot = Join-Path $RunRoot 'financial-backups'
    [IO.Directory]::CreateDirectory($backupRoot) | Out-Null
    $opsRoot = Join-Path $RepoRoot 'scripts/ops'
    Recovery-Accept -Phase 'BASELINE_BEFORE_BACKUP' -ExpectedBackendId $CurrentImageId
    # Exact encrypted MFA rows stay in memory only. Before any new authentication
    # after restore/switch, every field (including anti-replay counter/time) must
    # match. Only SHA256 proofs leave this private process.
    $mfaSql = 'SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY id),''[]''::jsonb)::text FROM platform_mfa_credentials x'
    $mfaBeforeBackup = Recovery-Sql $mfaSql
    function Recovery-MfaExact {
        param([string] $Expected, [string] $Phase, [string] $Database = '')
        if ((Recovery-Sql $mfaSql $Database) -cne $Expected) { throw "Exact MFA anti-replay state was not preserved before authentication in $Phase." }
        $Log.Add("PASS: ${Phase} exact MFA rows before authentication; sha256=$(Get-RecoveryTextSha256 $Expected)")
    }
    $backup = @(Recovery-Ops -Script (Join-Path $opsRoot 'backup-postgres.ps1') -Parameters @{
        ComposeFile=$ComposeFile; EnvFile=$EnvFile; ProjectName=$Project; OutputDirectory=$backupRoot; StopBackend=$true })
    $backupDirectory = [string]$backup[-1]
    if (-not [IO.Path]::GetFullPath($backupDirectory).StartsWith($backupRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Recovery backup package escaped its private root.'
    }
    $manifest = Get-Content -LiteralPath (Join-Path $backupDirectory 'manifest.json') -Raw | ConvertFrom-Json
    if ($manifest.formatVersion -ne 3 -or $manifest.applicationConsistent -ne $true -or -not $manifest.receiptsArchive) {
        throw 'Recovery requires a consistent v3 database plus receipts backup.'
    }
    Recovery-Wait $CurrentImageId
    $restoreArgs = @{ BackupDirectory=$backupDirectory; ComposeFile=$ComposeFile; EnvFile=$EnvFile; ProjectName=$Project; ConfirmDestructiveRestore=$true }
    $alternateDatabase = 'gestudio_recovery_' + $Project.Substring('gestudio-e2e-'.Length)
    $restoreArgs.TargetDatabase = $alternateDatabase
    [void](Recovery-Ops -Script (Join-Path $opsRoot 'restore-postgres.ps1') -Parameters $restoreArgs)
    if ((Recovery-Sql $financialSql $alternateDatabase) -cne $financialBefore) { throw 'Alternative database restore does not match the complete financial snapshot.' }
    Recovery-MfaExact -Expected $mfaBeforeBackup -Phase 'ALTERNATIVE_RESTORE' -Database $alternateDatabase
    $Log.Add('PASS: alternative database restore preserves complete financial rows and exact Flyway history')
    # Mutate only this run's synthetic student and its exact namespaced PDF.
    $containers = Recovery-Containers -ExpectedBackendId $CurrentImageId
    $mutated = Recovery-Sql "UPDATE alumnos SET nombre='Recovery altered' WHERE id=$($fixture.studentId) AND tenant_id='$($fixture.alphaId)' RETURNING id"
    if ($mutated -notmatch "^$($fixture.studentId)(\r?\nUPDATE 1)?$") { throw 'Recovery synthetic mutation did not affect its exact student.' }
    [void](& $Native -FilePath docker -Arguments @('exec', $containers[1], 'sh', '-ec', 'printf "%s" "synthetic recovery corruption" > "$1"', 'sh', $pdfPath) -Capture)
    $restoreArgs.TargetDatabase=$sourceDatabase
    $restoreArgs.AllowSourceDatabaseRestore=$true
    $restoreArgs.RestoreReceipts=$true
    $restoreArgs.ConfirmReceiptsOverwrite=$true
    $restoreArgs.StopBackend=$true
    [void](Recovery-Ops -Script (Join-Path $opsRoot 'restore-postgres.ps1') -Parameters $restoreArgs)
    Recovery-Wait $CurrentImageId
    Recovery-MfaExact -Expected $mfaBeforeBackup -Phase 'ACTIVE_RESTORE'
    Recovery-Accept -Phase 'ACTIVE_RESTORE' -ExpectedBackendId $CurrentImageId

    # Build the historical application with the current, immutable migration
    # resources and Docker packaging, as in the canonical rollback runbook.
    $historicalZip = Join-Path $RunRoot 'recovery-historical.zip'
    $historicalSource = Join-Path $RunRoot 'recovery-historical'
    [void](& $Native -FilePath git -Arguments @('-C', $RepoRoot, 'archive', '--format=zip', "--output=$historicalZip", $resolvedHistoricalCommit, '--', 'backend'))
    Expand-Archive -LiteralPath $historicalZip -DestinationPath $historicalSource
    $historicalBackend = Join-Path $historicalSource 'backend'
    $migrationRoot = Join-Path $historicalBackend 'src/main/resources/db/migration'
    $resolvedMigration = [IO.Path]::GetFullPath($migrationRoot)
    if (-not $resolvedMigration.StartsWith($historicalSource + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Historical migration destination escaped its scope.' }
    Remove-Item -LiteralPath $resolvedMigration -Recurse -Force
    [IO.Directory]::CreateDirectory($resolvedMigration) | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'backend/Dockerfile') -Destination (Join-Path $historicalBackend 'Dockerfile')
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'backend/src/main/resources/db/migration') -File) {
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $resolvedMigration $file.Name)
        if ((Get-FileHash -LiteralPath $file.FullName).Hash -cne (Get-FileHash -LiteralPath (Join-Path $resolvedMigration $file.Name)).Hash) { throw 'Historical migration overlay hash mismatch.' }
    }
    $historicalTag = 'gestudio-backend:recovery-' + $Project.Substring('gestudio-e2e-'.Length)
    if (& $Native -FilePath docker -Arguments @('image', 'ls', '-q', $historicalTag) -Capture) { throw 'Recovery historical tag already exists.' }
    $historicalId = $null
    try {
        $Log.Add((& $Native -FilePath docker -Arguments @('build', '--build-arg', "VCS_REF=$resolvedHistoricalCommit-compatible-recovery", '-t', $historicalTag, $historicalBackend) -Capture))
        $historicalId = (& $Native -FilePath docker -Arguments @('image', 'inspect', '--format', '{{.Id}}', $historicalTag) -Capture).Trim()
        $mfaBeforeHistorical = Recovery-Sql $mfaSql
        $rollbackArgs = @{ ComposeFile=$ComposeFile; EnvFile=$EnvFile; ProjectName=$Project; ExpectedCurrentImage=$CurrentImageId; TargetBackendImage=$historicalId; BackupOutputDirectory=$backupRoot; ConfirmRollback=$true }
        [void](Recovery-Ops -Script (Join-Path $opsRoot 'rollback-backend.ps1') -Parameters $rollbackArgs)
        Recovery-MfaExact -Expected $mfaBeforeHistorical -Phase 'HISTORICAL_ROLLBACK'
        Recovery-Accept -Phase 'HISTORICAL_ROLLBACK' -ExpectedBackendId $historicalId
        $mfaBeforeReturn = Recovery-Sql $mfaSql
        $rollbackArgs.ExpectedCurrentImage=$historicalId
        $rollbackArgs.TargetBackendImage=$CurrentImageId
        $rollbackArgs.SkipBackup=$true
        [void](Recovery-Ops -Script (Join-Path $opsRoot 'rollback-backend.ps1') -Parameters $rollbackArgs)
        Recovery-MfaExact -Expected $mfaBeforeReturn -Phase 'CURRENT_RETURN'
        Recovery-Accept -Phase 'CURRENT_RETURN' -ExpectedBackendId $CurrentImageId
    }
    finally {
        $tagId = (& $Native -FilePath docker -Arguments @('image', 'ls', '-q', '--no-trunc', $historicalTag) -Capture).Trim()
        if ($tagId) {
            if ($historicalId -and $tagId -cne $historicalId) { throw 'Historical image tag changed; cleanup refuses a foreign image.' }
            # Remove only the exact owned tag. A running container retains its image
            # until the outer runner cleans its labelled ephemeral resources.
            [void](& $Native -FilePath docker -Arguments @('image', 'rm', '-f', $historicalTag) -Capture)
        }
    }
    return [ordered]@{
        status='PASS'; backupFormat=3; applicationConsistent=$true; alternativeDatabase='PASS';
        activeRestore='PASS'; historicalRollback='PASS'; currentReturn='PASS';
        exactMfaStateBeforeNewAuthentication='PASS: alternative/active restore and both artifact switches';
        currentBackendImageId=$CurrentImageId; historicalBackendImageId=$historicalId; historicalCommit=$resolvedHistoricalCommit;
        financialSnapshotSha256=(Get-RecoveryTextSha256 $financialBefore); pdfSha256=$pdfHash;
        syntheticRuntimeConfigurationSha256=(Get-FileHash -LiteralPath $ComposeFile -Algorithm SHA256).Hash.ToLowerInvariant();
        noExternalDelivery=$true; keys='synthetic private runtime configuration retained separately; values never exported';
        limitation='local synthetic continuity drill; no production RPO/RTO or backup custody acceptance'
    }
}
