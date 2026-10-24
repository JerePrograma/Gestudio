[CmdletBinding()]
param()
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repoRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$runId=[Guid]::NewGuid().ToString('N').Substring(0,12)
$root=[IO.Path]::GetFullPath((Join-Path $repoRoot "artifacts/e2e/candidate-$runId"))
if(Test-Path -LiteralPath $root){throw 'Contract candidate already exists.'}
[IO.Directory]::CreateDirectory($root)|Out-Null
$script:dockerCalls=0
function docker { $script:dockerCalls++; throw 'Docker must not be called by rejected candidate preflight.' }
function Expect-Rejection {
    param([scriptblock]$Action)
    $rejected=$false
    try{& $Action}catch{$rejected=$true}
    if(-not $rejected -or $script:dockerCalls -ne 0){throw 'Candidate was not rejected before Docker.'}
}
$resultPath=Join-Path $root 'synthetic-result.json'
$archives=@()
try {
    foreach($role in @('backend','frontend')){
        $path=Join-Path $root ($role+'.tar')
        [IO.File]::WriteAllText($path,'not a deployable archive; preflight fixture only')
        $archives+=@{service=$role;path=$path;imageId=('sha256:'+('a'*64));sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $path).Length}
    }
    $fixture=@{status='FAIL';runId=$runId;financialFlowRequested=$true;candidateArchives=$archives;backendImageId=('sha256:'+('a'*64));frontendImageId=('sha256:'+('a'*64));backendRuntimeImageId=('sha256:'+('a'*64));frontendRuntimeImageId=('sha256:'+('a'*64))}
    [IO.File]::WriteAllText($resultPath,($fixture|ConvertTo-Json -Depth 8))
    Expect-Rejection { & (Join-Path $PSScriptRoot 'scan-e2e-candidate.ps1') -ResultPath $resultPath }
    $fixture.status='PASS'
    $fixture.candidateArchives[0].sha256='0'*64
    [IO.File]::WriteAllText($resultPath,($fixture|ConvertTo-Json -Depth 8))
    Expect-Rejection { & (Join-Path $PSScriptRoot 'scan-e2e-candidate.ps1') -ResultPath $resultPath }
    $fixture.candidateArchives[0].sha256=(Get-FileHash -LiteralPath $archives[0].path -Algorithm SHA256).Hash.ToLowerInvariant()
    $fixture.candidateArchives[0].path=$PSCommandPath
    [IO.File]::WriteAllText($resultPath,($fixture|ConvertTo-Json -Depth 8))
    Expect-Rejection { & (Join-Path $PSScriptRoot 'scan-e2e-candidate.ps1') -ResultPath $resultPath }
    $fixture.candidateArchives[0].path=Join-Path $root 'backend.tar'
    $fixture.backendRuntimeImageId='sha256:'+('b'*64)
    [IO.File]::WriteAllText($resultPath,($fixture|ConvertTo-Json -Depth 8))
    Expect-Rejection { & (Join-Path $PSScriptRoot 'scan-e2e-candidate.ps1') -ResultPath $resultPath }
    $fixture.backendRuntimeImageId='sha256:'+('a'*64)
    [IO.File]::WriteAllText($resultPath,($fixture|ConvertTo-Json -Depth 8))
    Expect-Rejection { & (Join-Path $PSScriptRoot 'scan-e2e-candidate.ps1') -ResultPath $resultPath -ExistingDatabaseVolume 'bad /volume' }
    # A removed --rm container normally yields no stdout. Exercise the actual
    # scanner native wrapper with a real empty native process, without Docker.
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'scan-e2e-candidate.ps1'),[ref]$tokens,[ref]$errors)
    if($errors.Count){throw 'Scanner source does not parse.'}
    $nativeFunction=$ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Scan-Native'},$false)
    . ([scriptblock]::Create($nativeFunction.Extent.Text))
    $proofRoot=$root
    $executions=[Collections.Generic.List[object]]::new()
    function docker { & node -e 'process.exit(0)' }
    $empty=Scan-Native -Arguments @('synthetic-empty-output') -Name 'empty-output-contract'
    if($empty.code -ne 0 -or $null -eq $empty.output -or $empty.output -cne '' -or
        $executions.Count -ne 1){throw 'Empty successful native output did not remain an empty string.'}
    Write-Host 'PASS: failed gate, altered archive hash/path/runtime identity and invalid cache refused before Docker'
}
finally {
    $allowed=[IO.Path]::GetFullPath((Join-Path $repoRoot 'artifacts/e2e')).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $root.StartsWith($allowed,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $root -Leaf) -cne "candidate-$runId"){throw 'Contract cleanup scope mismatch.'}
    Remove-Item -LiteralPath $root -Recurse -Force
}
