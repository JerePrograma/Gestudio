@echo off
setlocal

set "GESTUDIO_ROOT=%~dp0"
set "GESTUDIO_SCRIPT=%GESTUDIO_ROOT%scripts\deploy\deploy.ps1"

if not exist "%GESTUDIO_SCRIPT%" (
    echo ERROR: No existe "%GESTUDIO_SCRIPT%".
    endlocal & exit /b 2
)

where pwsh.exe >nul 2>&1
if errorlevel 1 goto windows_powershell

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%GESTUDIO_SCRIPT%" %*
goto finished

:windows_powershell
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo ERROR: No se encontro PowerShell 5.1 o PowerShell 7.
    endlocal & exit /b 2
)
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%GESTUDIO_SCRIPT%" %*

:finished

set "GESTUDIO_EXIT_CODE=%ERRORLEVEL%"
endlocal & exit /b %GESTUDIO_EXIT_CODE%
