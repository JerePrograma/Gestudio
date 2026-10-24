[CmdletBinding()]
param(
    [string] $ResultPath = '',
    [string] $ExistingDatabaseVolume = '',
    [ValidatePattern('^[a-z0-9-]{1,32}$')][string] $Attempt = '1'
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
if (-not $ResultPath) { $ResultPath = Join-Path $repoRoot 'artifacts/e2e/result.json' }
$candidate = Get-Content -LiteralPath $ResultPath -Raw | ConvertFrom-Json
if ($candidate.status -cne 'PASS' -or $candidate.runId -cnotmatch '^[a-f0-9]{12}$' -or
    $candidate.financialFlowRequested -ne $true -or $candidate.candidateArchives.Count -ne 2) {
    throw 'Security scan requires a complete PASS with two exact exported financial E2E images.'
}
$runId = [string]$candidate.runId
$archiveRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot "artifacts/e2e/candidate-$runId"))
$services = @($candidate.candidateArchives.service | Sort-Object)
if (($services -join '|') -cne 'backend|frontend') { throw 'Candidate image roles are not exact.' }
foreach ($archive in $candidate.candidateArchives) {
    $expectedPath = Join-Path $archiveRoot ($archive.service + '.tar')
    if ([IO.Path]::GetFullPath($archive.path) -cne $expectedPath -or
        $archive.imageId -cnotmatch '^sha256:[a-f0-9]{64}$' -or
        $archive.sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        (Get-FileHash -LiteralPath $expectedPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $archive.sha256 -or
        (Get-Item -LiteralPath $expectedPath).Length -ne $archive.bytes) {
        throw 'Candidate archive path, image identity, size or SHA256 does not match the executed gate.'
    }
    if (((Get-Item -LiteralPath $expectedPath).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        ((Get-Item -LiteralPath $archiveRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'Candidate archives must be physical files in the exact run directory.'
    }
    $expectedId = if ($archive.service -ceq 'backend') { $candidate.backendImageId } else { $candidate.frontendImageId }
    $runtimeId = if ($archive.service -ceq 'backend') { $candidate.backendRuntimeImageId } else { $candidate.frontendRuntimeImageId }
    if ($archive.imageId -cne $expectedId -or $archive.imageId -cne $runtimeId) { throw 'Candidate archive image ID differs from its tested running service.' }
}
if ($ExistingDatabaseVolume -and $ExistingDatabaseVolume -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_.-]{0,100}$') {
    throw 'Invalid read-only vulnerability database volume.'
}
if ($env:DOCKER_HOST) { throw 'Security scan refuses inherited DOCKER_HOST.' }
$contextBackup = [Environment]::GetEnvironmentVariable('DOCKER_CONTEXT','Process')
$context = (& docker context show).Trim()
if ($LASTEXITCODE -ne 0 -or -not $context -or $context -match '(?i)(prod|stage|remote|demo)') { throw 'Security scan refuses a protected Docker context.' }
$endpointJson = & docker context inspect --format '{{json .Endpoints.docker.Host}}' $context
if ($LASTEXITCODE -ne 0) { throw 'Cannot inspect Docker context.' }
$endpoint = [string]($endpointJson | ConvertFrom-Json)
if ($endpoint -cnotin @('npipe:////./pipe/docker_engine','npipe:////./pipe/dockerDesktopLinuxEngine','unix:///var/run/docker.sock')) {
    throw 'Security scan requires an exact local Docker endpoint.'
}
$proofRoot = Join-Path $repoRoot "artifacts/e2e/security-$runId-attempt-$Attempt"
if (Test-Path -LiteralPath $proofRoot) { throw 'Security evidence directory already exists; preserve the prior attempt.' }
[IO.Directory]::CreateDirectory($proofRoot) | Out-Null
$syft = 'anchore/syft@sha256:4cc92b64ca74ffca4c94d4c8fcc01f217731375300be14d0b6eeb2e82eaa110a'
$grype = 'anchore/grype@sha256:fd4ab4d1042b522c896e73bdf09ab8bf384fa417df99d6dd0d6e1008c7e7c821'
$cacheVolume = if ($ExistingDatabaseVolume) { $ExistingDatabaseVolume } else { "gestudio-grype-$runId" }
$ownedCache = $false
$containerNames = [Collections.Generic.List[string]]::new()
$executions = [Collections.Generic.List[object]]::new()
$primaryFailure = $null
$cleanupFailure = $null
$scanReports = [Collections.Generic.List[object]]::new()
$pythonVersion = (@(& python --version 2>&1) -join ' ').Trim()
if ($LASTEXITCODE -ne 0 -or $pythonVersion -notmatch '^Python 3\.(1[2-9]|[2-9][0-9])\.') { throw 'The stdlib content verifier requires an explicit Python 3.12+ runtime.' }
$resultHashBefore = (Get-FileHash -LiteralPath $ResultPath -Algorithm SHA256).Hash.ToLowerInvariant()
$configPath = Join-Path $proofRoot 'controlled-grype.yaml'
[IO.File]::WriteAllText($configPath,@'
check-for-app-update: false
ignore: []
match-upstream-kernel-headers: true
db:
  cache-dir: /cache/db
  auto-update: false
  validate-by-hash-on-start: true
  validate-age: true
  max-allowed-built-age: 24h0m0s
'@,[Text.UTF8Encoding]::new($false))
function Scan-Native {
    param([string[]] $Arguments, [string] $Name, [switch] $AllowFailure)
    $started=[DateTimeOffset]::UtcNow
    $previousError=$ErrorActionPreference
    try { $ErrorActionPreference='Continue'; $output=@(& docker @Arguments 2>&1 | ForEach-Object { [string]$_ }); $code=$LASTEXITCODE }
    finally { $ErrorActionPreference=$previousError }
    [IO.File]::WriteAllLines((Join-Path $proofRoot ($Name+'.log')),$output,[Text.UTF8Encoding]::new($false))
    $executions.Add([ordered]@{ name=$Name; command=@('docker')+$Arguments; startedAt=$started.ToString('O'); finishedAt=[DateTimeOffset]::UtcNow.ToString('O'); exitCode=$code })
    if ($code -ne 0 -and -not $AllowFailure) { throw "Security command failed: $Name (exit $code); see its preserved log." }
    return [pscustomobject]@{ code=$code; output=($output -join "`n").Trim() }
}
function Scan-Run {
    param([string] $Name, [string] $Tool, [string[]] $Arguments, [string] $Network='none', [switch] $Cache, [switch] $AllowFailure)
    $container="gestudio-scan-$runId-$Name"
    $existing=Scan-Native @('ps','-aq','--filter',"name=^/$container`$") "preflight-$Name"
    if ($existing.output) { throw 'Scanner container name already exists.' }
    $containerNames.Add($container)
    $dockerArgs=@('run','--rm','--pull=never','--name',$container,'--label',"org.gestudio.scan.run=$runId",'--network',$Network,
        '--mount',"type=bind,src=$archiveRoot,dst=/images,readonly",'--mount',"type=bind,src=$proofRoot,dst=/out")
    if ($Cache) {
        $readOnly=if($ExistingDatabaseVolume){',readonly'}else{''}
        $dockerArgs+=@('--mount',"type=volume,src=$cacheVolume,dst=/cache$readOnly")
    }
    $dockerArgs+=@($Tool)+$Arguments
    return Scan-Native -Arguments $dockerArgs -Name $Name -AllowFailure:$AllowFailure
}
try {
    $env:DOCKER_CONTEXT = $context
    $os=Scan-Native @('info','--format','{{.OSType}}') 'docker-platform'
    if ($os.output -cne 'linux') { throw 'Security scans require the selected local Linux daemon.' }
    [void](Scan-Native @('info','--format','{{json .DriverStatus}}') 'docker-image-store')
    [void](Scan-Native @('version','--format','{{.Server.Version}}') 'docker-engine-version')
    foreach ($tool in @(@('syft',$syft),@('grype',$grype))) {
        $inspect=Scan-Native @('image','inspect','--format','{{.Id}}',$tool[1]) ($tool[0]+'-image-before') -AllowFailure
        if ($inspect.code -ne 0) {
            if ($ExistingDatabaseVolume) { throw 'Local scanner must reuse the prepared pinned tool image; no implicit download.' }
            [void](Scan-Native @('pull',$tool[1]) ($tool[0]+'-pull-pinned'))
        }
        [void](Scan-Native @('image','inspect','--format','{{json .RepoDigests}}|{{.Id}}',$tool[1]) ($tool[0]+'-image-identity'))
    }
    if ($ExistingDatabaseVolume) {
        [void](Scan-Native @('volume','inspect',$cacheVolume) 'database-readonly-volume')
    } else {
        $existing=Scan-Native @('volume','ls','-q','--filter',"name=^$cacheVolume`$") 'database-volume-before'
        if ($existing.output) { throw 'Scanner database volume already exists.' }
        $ownedCache=$true
        [void](Scan-Native @('volume','create','--label',"org.gestudio.scan.run=$runId",$cacheVolume) 'database-volume-create')
        [void](Scan-Run -Name 'database-update' -Tool $grype -Arguments @('--config','/out/controlled-grype.yaml','db','update') -Network 'bridge' -Cache)
    }
    $dbStatus=Scan-Run -Name 'database-status' -Tool $grype -Arguments @('--config','/out/controlled-grype.yaml','db','status','-o','json') -Cache
    [IO.File]::WriteAllText((Join-Path $proofRoot 'database-status.json'),$dbStatus.output,[Text.UTF8Encoding]::new($false))
    $db = $dbStatus.output | ConvertFrom-Json
    if ($db.valid -ne $true) { throw 'Grype database is not valid.' }
    foreach ($archive in $candidate.candidateArchives) {
        $role=[string]$archive.service
        [void](Scan-Run -Name "$role-sbom" -Tool $syft -Arguments @('scan',"docker-archive:/images/$role.tar",'--scope','squashed',
            '-o',"syft-json=/out/$role-sbom.syft.json",'-o',"cyclonedx-json=/out/$role-sbom.cdx.json"))
        $sbomPath=Join-Path $proofRoot "$role-sbom.syft.json"
        $sbom=Get-Content -LiteralPath $sbomPath -Raw | ConvertFrom-Json
        if (@($sbom.artifacts).Count -eq 0) { throw 'Syft returned an empty package inventory.' }
        $cdxPath=Join-Path $proofRoot "$role-sbom.cdx.json"
        if (-not (Test-Path -LiteralPath $cdxPath) -or (Get-Item -LiteralPath $cdxPath).Length -le 0) { throw 'CycloneDX output is missing or empty.' }
        $cdx=Get-Content -LiteralPath $cdxPath -Raw | ConvertFrom-Json
        if ($cdx.bomFormat -cne 'CycloneDX' -or @($cdx.components).Count -eq 0) { throw 'CycloneDX package inventory is empty or invalid.' }
        $sbomHashBefore=(Get-FileHash -LiteralPath $sbomPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $scan=Scan-Run -Name "$role-grype" -Tool $grype -Arguments @('--config','/out/controlled-grype.yaml',"sbom:/out/$role-sbom.syft.json",'-o','json','--file',"/out/$role-grype.json",'--fail-on','high') -Cache -AllowFailure
        $reportPath=Join-Path $proofRoot "$role-grype.json"
        if (-not (Test-Path -LiteralPath $reportPath)) { throw 'Grype did not produce a report.' }
        $report=Get-Content -LiteralPath $reportPath -Raw | ConvertFrom-Json
        if ($report.descriptor.db.status.valid -ne $true) { throw 'The executed scan did not use a valid vulnerability database.' }
        $identityArguments=@('-B',(Join-Path $PSScriptRoot 'verify_image_identity.py'),'--archive',$archive.path,'--image-id',$archive.imageId,
            '--archive-input',"/images/$role.tar",'--sbom',$sbomPath,'--grype',$reportPath,'--output',(Join-Path $proofRoot "$role-identity.json"))
        $identityStarted=[DateTimeOffset]::UtcNow
        $identityErrorPreference=$ErrorActionPreference
        try {
            $ErrorActionPreference='Continue'
            $identityOutput=@(& python @identityArguments 2>&1 | ForEach-Object {[string]$_})
            $identityExitCode=$LASTEXITCODE
        } finally { $ErrorActionPreference=$identityErrorPreference }
        [IO.File]::WriteAllLines((Join-Path $proofRoot "$role-identity.log"),$identityOutput,[Text.UTF8Encoding]::new($false))
        $executions.Add([ordered]@{name="$role-identity";command=@('python')+$identityArguments;startedAt=$identityStarted.ToString('O');finishedAt=[DateTimeOffset]::UtcNow.ToString('O');exitCode=$identityExitCode})
        if ($identityExitCode -ne 0) { throw 'Archive→OCI index→config/layers→Syft/Grype identity validation failed.' }
        if ((Get-FileHash -LiteralPath $sbomPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $sbomHashBefore) { throw 'SBOM changed during identity validation.' }
        $identityPath=Join-Path $proofRoot "$role-identity.json"
        $identity=Get-Content -LiteralPath $identityPath -Raw | ConvertFrom-Json
        if ($identity.identity.archive.sha256 -cne ('sha256:'+$archive.sha256) -or
            $identity.identity.archive.bytes -ne $archive.bytes -or
            (Get-FileHash -LiteralPath $archive.path -Algorithm SHA256).Hash.ToLowerInvariant() -cne $archive.sha256) {
            throw 'Image archive changed during scanning/content verification.'
        }
        $severity=@{}
        foreach ($group in @($report.matches | Group-Object {$_.vulnerability.severity})) { $severity[$group.Name]=$group.Count }
        $high=@($report.matches | Where-Object {$_.vulnerability.severity -in @('High','Critical')}).Count
        if (($scan.code -eq 0 -and $high -ne 0) -or ($scan.code -ne 0 -and $scan.code -ne 2)) { throw 'Scanner exit code/findings contract is inconsistent or operationally failed.' }
        $scanReports.Add([ordered]@{
            service=$role; imageId=$archive.imageId; archiveSha256=$archive.sha256;
            sbomSha256=(Get-FileHash -LiteralPath $sbomPath -Algorithm SHA256).Hash.ToLowerInvariant();
            cycloneDxSha256=(Get-FileHash -LiteralPath $cdxPath -Algorithm SHA256).Hash.ToLowerInvariant();
            cycloneDxVersion=$cdx.specVersion;cycloneDxComponents=@($cdx.components).Count;
            reportSha256=(Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash.ToLowerInvariant();
            identityProofSha256=(Get-FileHash -LiteralPath $identityPath -Algorithm SHA256).Hash.ToLowerInvariant();
            status=if($scan.code -eq 0){'PASS'}else{'FAIL_FINDINGS'}; exitCode=$scan.code;
            severity=$severity; database=$report.descriptor.db; packages=@($sbom.artifacts).Count
        })
    }
    if ((Get-FileHash -LiteralPath $ResultPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $resultHashBefore) { throw 'Candidate result changed during scanning.' }
}
catch { $primaryFailure=$_.Exception.Message }
finally {
    foreach ($name in $containerNames) {
        try {
            $residual=Scan-Native @('ps','-aq','--filter',"name=^/$name`$") ("cleanup-probe-$name")
            if ($residual.output) {
                $owner=Scan-Native @('inspect','--format','{{index .Config.Labels "org.gestudio.scan.run"}}',$residual.output) ("cleanup-owner-$name")
                if ($owner.output -cne $runId) { throw 'Refusing cleanup of a foreign scanner container.' }
                [void](Scan-Native @('container','rm','-f',$residual.output) ("cleanup-$name"))
            }
        } catch { $cleanupFailure=$_.Exception.Message }
    }
    if ($ownedCache) {
        try {
            $owner=Scan-Native @('volume','inspect','--format','{{index .Labels "org.gestudio.scan.run"}}',$cacheVolume) 'database-cleanup-owner'
            if ($owner.output -cne $runId) { throw 'Refusing cleanup of a foreign scanner database.' }
            [void](Scan-Native @('volume','rm',$cacheVolume) 'database-cleanup')
        } catch { $cleanupFailure=$_.Exception.Message }
    }
    $status=if(-not $primaryFailure -and -not $cleanupFailure -and $scanReports.Count -eq 2 -and @($scanReports|Where-Object {$_.status -cne 'PASS'}).Count -eq 0){'PASS'}else{'FAIL'}
    $proof=[ordered]@{schemaVersion=1;status=$status;runId=$runId;attempt=$Attempt;sourceGitSha=$candidate.gitSha;worktreeClean=$candidate.worktreeClean;
        backendSourceFingerprint=$candidate.backendSourceFingerprint;frontendSourceFingerprint=$candidate.frontendSourceFingerprint;composeFingerprint=$candidate.composeFingerprint;
        executedE2eResultSha256=$resultHashBefore;syftImage=$syft;grypeImage=$grype;pythonRuntime=$pythonVersion;databaseMaxAge='24h';ignores=@();onlyFixed=$false;
        scans=$scanReports.ToArray();commands=$executions.ToArray();failure=$primaryFailure;cleanupFailure=$cleanupFailure;
        limitation='Local/CI image scan; compiled frontend JS is supplemented by current lockfile production audit. No remote CI claim for an uncommitted tree.'}
    [IO.File]::WriteAllText((Join-Path $proofRoot 'scan-result.json'),($proof|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
    [Environment]::SetEnvironmentVariable('DOCKER_CONTEXT',$contextBackup,'Process')
}
Write-Host "Candidate security scan: $status; proof directory: $proofRoot"
if ($status -cne 'PASS') { throw 'Candidate security scan did not pass; inspect preserved reports and exact execution proofs.' }
