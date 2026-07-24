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
    echo.
    pause
    exit /b 1
)

if not exist "%REPO_ROOT%\.env.remote-demo" (
    echo [ERROR] No existe .env.remote-demo.
    echo Cree y complete ese archivo local sin versionarlo.
    echo.
    pause
    exit /b 1
)

echo ============================================================
echo  GESTUDIO - DESPLIEGUE DE DEMO REMOTA PUBLICA
echo ============================================================
echo Repositorio: %REPO_ROOT%
echo.
echo No cierre esta ventana, Docker Desktop ni cloudflared.
echo.

pwsh.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%REPO_ROOT%\scripts\deploy-remote-demo-public.ps1" -RepoPath "%REPO_ROOT%"
set "EXIT_CODE=%ERRORLEVEL%"

echo.
if not "%EXIT_CODE%"=="0" (
    echo [ERROR] El despliegue remoto fallo con codigo %EXIT_CODE%.
    echo Revise la salida anterior. No se modificaron secretos en este archivo.
    echo.
    pause
    exit /b %EXIT_CODE%
)

echo [OK] Demo remota desplegada y validada.
echo Mantenga encendidos este equipo, Docker Desktop, Internet y cloudflared.
echo Frontend: https://gestudio-demo-jere-287b8c90.pages.dev
echo.
start "" "https://gestudio-demo-jere-287b8c90.pages.dev"
pause
exit /b 0
