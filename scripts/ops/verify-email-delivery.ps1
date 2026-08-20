[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$evidenceRoot = Join-Path ([IO.Path]::GetTempPath()) ('GestudioEmailDelivery\' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$logPath = Join-Path $evidenceRoot 'verify-email-delivery.log'
$transcriptPath = Join-Path $evidenceRoot 'transcript.log'
$startedAt = Get-Date
$passes = 0
$previousEnvironment = @{}

function Pass {
    param([Parameter(Mandatory)][string] $Name)
    $script:passes++
    Write-Host "[PASS] $Name" -ForegroundColor Green
}

function Assert-True {
    param([bool] $Condition, [Parameter(Mandatory)][string] $Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Contains {
    param([Parameter(Mandatory)][string] $Text,
          [Parameter(Mandatory)][string] $Pattern,
          [Parameter(Mandatory)][string] $Message)
    Assert-True -Condition ($Text -match $Pattern) -Message $Message
}

function Invoke-Logged {
    param([Parameter(Mandatory)][string] $FilePath,
          [Parameter(Mandatory)][string[]] $Arguments)

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        & $FilePath @Arguments 2>&1 | Tee-Object -FilePath $logPath -Append
        $code = $LASTEXITCODE
    }
    finally { $ErrorActionPreference = $previousPreference }
    if ($code -ne 0) { throw "El comando '$FilePath' falló con código $code." }
}

function Set-SyntheticEnvironment {
    $values = [ordered]@{
        POSTGRES_DB = 'gestudio_email_verify'
        POSTGRES_USER = 'gestudio_email_verify'
        POSTGRES_PASSWORD = 'synthetic-compose-password'
        POSTGRES_APP_USER = 'gestudio_email_app'
        POSTGRES_APP_PASSWORD = 'synthetic-compose-app-password'
        POSTGRES_CONTROL_USER = 'gestudio_email_control'
        POSTGRES_CONTROL_PASSWORD = 'synthetic-compose-control-password'
        BACKEND_IMAGE = 'example.invalid/gestudio-backend:email-verify'
        FRONTEND_IMAGE = 'example.invalid/gestudio-frontend:email-verify'
        JWT_SECRET = 'synthetic-email-gate-jwt-secret-at-least-32-characters'
        JWT_ISSUER = 'gestudio-email-verify'
        JWT_ACCESS_TOKEN_TTL = 'PT15M'
        JWT_REFRESH_TOKEN_TTL = 'P7D'
        JWT_PLATFORM_AUDIENCE = 'gestudio-email-platform-web'
        APP_PLATFORM_ACCESS_TOKEN_TTL = 'PT5M'
        APP_PLATFORM_REFRESH_TOKEN_TTL = 'PT8H'
        APP_PLATFORM_STEP_UP_TTL = 'PT5M'
        APP_PLATFORM_MFA_ENCRYPTION_KEY = 'MDEyMzQ1Njc4OWFiY2RlZjAxMjM0NTY3ODlhYmNkZWY='
        APP_PLATFORM_MFA_KEY_VERSION = '1'
        APP_PLATFORM_REFRESH_COOKIE_NAME = 'gestudio_email_platform_refresh'
        APP_PLATFORM_REFRESH_COOKIE_SECURE = 'true'
        APP_PLATFORM_REFRESH_COOKIE_SAME_SITE = 'Strict'
        APP_PLATFORM_REFRESH_COOKIE_DOMAIN = ''
        APP_PLATFORM_REFRESH_COOKIE_PATH = '/api/platform/auth'
        APP_TIME_ZONE = 'America/Argentina/Buenos_Aires'
        APP_CORS_ALLOWED_ORIGINS = 'https://app.example.invalid'
        APP_OBSERVABILITY_METRICS_TOKEN = 'synthetic-email-gate-metrics-token-at-least-32-characters'
        APP_REMOTE_DEMO_PROXY_TOKEN = 'synthetic-email-gate-proxy-token-at-least-32-characters'
        APP_EMAIL_ENABLED = 'false'
        APP_EMAIL_PROVIDER = 'NOOP'
        APP_EMAIL_DRY_RUN = 'true'
        APP_EMAIL_REAL_NETWORK_ALLOWED = 'false'
        APP_EMAIL_KILL_SWITCH = 'true'
        APP_EMAIL_SENT_COPY_MODE = 'DISABLED'
    }
    foreach ($entry in $values.GetEnumerator()) {
        $script:previousEnvironment[$entry.Key] = [Environment]::GetEnvironmentVariable($entry.Key, 'Process')
        [Environment]::SetEnvironmentVariable($entry.Key, [string]$entry.Value, 'Process')
    }
}

New-Item -ItemType Directory -Path $evidenceRoot -Force | Out-Null
Start-Transcript -LiteralPath $transcriptPath -Append | Out-Null
try {
    Push-Location $repoRoot
    try {
        $application = Get-Content -Raw -LiteralPath 'backend/src/main/resources/application.yml'
        $properties = Get-Content -Raw -LiteralPath 'backend/src/main/java/gestudio/servicios/email/EmailDeliveryProperties.java'
        $profilesTest = Get-Content -Raw -LiteralPath 'backend/src/test/java/gestudio/infra/configuracion/RuntimeProfilesTest.java'
        $servicesTest = Get-Content -Raw -LiteralPath 'backend/src/test/java/gestudio/servicios/email/EmailServicesTest.java'
        $gmailTest = Get-Content -Raw -LiteralPath 'backend/src/test/java/gestudio/servicios/email/GmailSmtpEmailServiceTest.java'
        $receiptTest = Get-Content -Raw -LiteralPath 'backend/src/test/java/gestudio/servicios/pdfs/ReciboStorageServiceTest.java'
        $birthdayTest = Get-Content -Raw -LiteralPath 'backend/src/test/java/gestudio/servicios/notificaciones/NotificacionServiceTest.java'

        Assert-Contains $application 'APP_EMAIL_ENABLED:false' 'Falta el default APP_EMAIL_ENABLED=false.'
        Assert-Contains $application 'APP_EMAIL_PROVIDER:NOOP' 'Falta el default APP_EMAIL_PROVIDER=NOOP.'
        Assert-Contains $application 'APP_EMAIL_DRY_RUN:true' 'Falta el default APP_EMAIL_DRY_RUN=true.'
        Assert-Contains $application 'APP_EMAIL_REAL_NETWORK_ALLOWED:false' 'Falta el bloqueo de red predeterminado.'
        Assert-Contains $application 'APP_EMAIL_KILL_SWITCH:true' 'Falta el kill switch predeterminado.'
        Assert-Contains $application 'APP_EMAIL_SENT_COPY_MODE:DISABLED' 'Falta Sent copy deshabilitado por defecto.'
        Pass 'Configuración NOOP segura por defecto'

        foreach ($provider in @('NOOP', 'FAKE', 'GMAIL_SMTP')) {
            Assert-Contains $properties ("\b{0}\b" -f $provider) "Falta el proveedor $provider."
        }
        Assert-Contains $profilesTest 'prodSeleccionaFakeSoloPorPropiedadExplicita' 'Falta selección FAKE explícita en prod.'
        Assert-Contains $profilesTest 'prodConGmailBloqueadoNoInvocaMailSender' 'Falta prueba de Gmail bloqueado en prod.'
        Pass 'NOOP, FAKE y Gmail bloqueado seleccionan exactamente un adaptador'

        Assert-Contains $servicesTest 'fakeEsDeterministaParaExitoFalloTransitorioYPermanente' 'Falta cobertura de los tres resultados FAKE.'
        Assert-Contains $servicesTest 'logsYMetricasNoIncluyenDestinatarioAsuntoNiCuerpo' 'Falta prueba de logs sanitizados.'
        Assert-Contains $gmailTest 'construyeMimeUtf8ConSenderConfiguradoHtmlInlineYAdjunto' 'Falta prueba MIME controlada.'
        Assert-Contains $gmailTest 'bestEffortFallidoMantieneSmtpAceptadoYNoReenvia' 'Falta prueba de append sin reenvío.'
        Assert-Contains $receiptTest 'noopSimulacionYBloqueosCompletanSinMarcarEnvioNiReintentar' 'Falta semántica de recibo simulado/bloqueado.'
        Assert-Contains $birthdayTest 'enviaElCorreoAfterCommitSoloParaLaTransaccionQueInserta' 'Falta prueba de cumpleaños deduplicado.'
        Pass 'Éxito, fallos FAKE, cumpleaños, recibo, Sent copy, métricas y logs están cubiertos'

        $forbiddenHosts = @(
            (@('smtp', 'gmail.com') -join '.'),
            (@('imap', 'gmail.com') -join '.'),
            (@('gmail', 'googleapis.com') -join '.'),
            (@('oauth2', 'googleapis.com') -join '.'),
            (@('accounts', 'google.com') -join '.')
        )
        $trackedSource = @(& git ls-files -- '*.java' '*.yml' '*.yaml' '*.properties' '*.ps1' '*.env*')
        foreach ($file in $trackedSource) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
            $content = Get-Content -Raw -LiteralPath $file
            foreach ($hostName in $forbiddenHosts) {
                Assert-True -Condition (-not $content.Contains($hostName)) -Message "Host Gmail real versionado en $file."
            }
        }
        Pass 'No hay destino Gmail real en código, configuración ni pruebas'

        $secretMatches = @(& git grep -n -I -E '(client_secret|refresh_token|access_token|app[ _-]?password)[[:space:]]*[:=][[:space:]]*[^$<{[:space:]]' -- . 2>$null |
            Where-Object { $_ -notmatch '(?i)(example|synthetic|no-debe-persistirse|intentionally omitted)' })
        Assert-True -Condition ($secretMatches.Count -eq 0) -Message ('Posible secreto versionado: ' + ($secretMatches -join '; '))
        Pass 'No se detectaron credenciales de email versionadas'

        Push-Location 'backend'
        try {
            Invoke-Logged -FilePath '.\mvnw.cmd' -Arguments @(
                '-Dtest=*Email*,RuntimeProfilesTest,RemoteDemoProfileTest,ReciboStorageServiceTest,NotificacionServiceTest',
                'test')
        }
        finally { Pop-Location }
        Pass 'Pruebas focalizadas ejecutadas sin red Gmail'

        Set-SyntheticEnvironment
        Invoke-Logged -FilePath 'docker' -Arguments @('compose', 'config', '--quiet')
        Invoke-Logged -FilePath 'docker' -Arguments @('compose', '-f', 'docker-compose.yml', '-f', 'docker-compose.prod.yml', 'config', '--quiet')
        Invoke-Logged -FilePath 'docker' -Arguments @('compose', '-f', 'docker-compose.yml', '-f', 'docker-compose.remote-demo.yml', 'config', '--quiet')
        Pass 'Compose local, prod NOOP y remote-demo válidos sin secretos Gmail'

        $summary = [ordered]@{
            result = 'PASS'
            passes = $passes
            startedAt = $startedAt.ToString('o')
            finishedAt = (Get-Date).ToString('o')
            externalGmailTraffic = 'NOT_PERFORMED'
            evidence = $evidenceRoot
        }
        $summary | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $evidenceRoot 'summary.json') -Encoding UTF8
        Write-Host "EMAIL_DELIVERY_GATE=PASS passes=$passes evidence=$evidenceRoot" -ForegroundColor Green
    }
    finally { Pop-Location }
}
finally {
    foreach ($entry in $previousEnvironment.GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value, 'Process')
    }
    Stop-Transcript | Out-Null
}
