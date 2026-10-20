@echo off
setlocal EnableExtensions
title Gestudio - Despliegue remoto publico

for %%I in ("%~dp0.") do set "REPO_ROOT=%%~fI"
cd /d "%REPO_ROOT%"

where pwsh.exe >nul 2>&1
if errorlevel 1 (
    echo [ERROR] PowerShell 7 ^(pwsh.exe^) no esta disponible en PATH.
    echo Instale PowerShell 7 y vuelva a ejecutar este archivo.
    echo.
    pause
    exit /b 1
)

if not exist "%REPO_ROOT%\scripts\deploy-remote-demo-public.ps1" (
    echo [ERROR] No existe scripts\deploy-remote-demo-public.ps1.
    echo Repositorio: %REPO_ROOT%
    exit /b 1
)

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%REPO_ROOT%\scripts\deploy-remote-demo-public.ps1" -RepoPath "%REPO_ROOT%" %*
set "EXIT_CODE=%ERRORLEVEL%"

if not "%EXIT_CODE%"=="0" (
    echo [ERROR] El despliegue remoto fallo con codigo %EXIT_CODE%.
    exit /b %EXIT_CODE%
)

exit /b 0
