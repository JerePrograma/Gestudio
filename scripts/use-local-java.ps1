param(
    [string] $JdkPath = $env:JAVA_HOME
)

# Este helper se carga con dot-sourcing para modificar JAVA_HOME y Path en la
# terminal llamadora. Por eso, deliberadamente no cambia StrictMode ni
# ErrorActionPreference del usuario. Los demás scripts ejecutables sí los fijan.
if ([string]::IsNullOrWhiteSpace($JdkPath)) {
    throw "Indicá un JDK 21 con -JdkPath o definí JAVA_HOME antes de cargar este helper."
}

$jdkPath = [IO.Path]::GetFullPath($JdkPath)
$javaExe = Join-Path $jdkPath "bin\java.exe"
$javacExe = Join-Path $jdkPath "bin\javac.exe"

if (-not (Test-Path -LiteralPath $javaExe)) {
    throw "No se encontró Java en: $javaExe"
}

if (-not (Test-Path -LiteralPath $javacExe)) {
    throw "No se encontró javac en: $javacExe"
}

$javacVersion = (& $javacExe -version 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or $javacVersion -notmatch '^javac 21(?:\.|$)') {
    throw "El JDK indicado no es Java 21. Detectado: $javacVersion"
}

$env:JAVA_HOME = $jdkPath
$jdkBin = Join-Path $jdkPath "bin"

$pathEntries = $env:Path -split ";" |
    Where-Object {
        $_ -and
        $_ -ne $jdkBin -and
        $_ -notmatch '\\Java\\.*\\bin\\?$' -and
        $_ -notmatch '\\\.jdks\\.*\\bin\\?$'
    }

$env:Path = (@($jdkBin) + $pathEntries) -join ";"

Write-Host "JAVA_HOME configurado para esta terminal:"
Write-Host "  $env:JAVA_HOME"

& $javaExe -version
