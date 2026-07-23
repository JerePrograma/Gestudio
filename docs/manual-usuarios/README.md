# Generador del manual visual de usuarios

Genera capturas reales de la demo local, HTML autocontenido, PDF y metadata mediante `scripts/manual/Build-Manual.ps1`.

Requiere PowerShell, Git, Docker Compose v2, Node/npm, Java 21 y las variables de proceso `GESTUDIO_DEMO_SUPERADMIN_PASSWORD`, `GESTUDIO_DEMO_DIRECCION_PASSWORD`, `GESTUDIO_DEMO_ADMINISTRADOR_PASSWORD`, `GESTUDIO_DEMO_SECRETARIA_PASSWORD` y `GESTUDIO_DEMO_CAJA_PASSWORD`.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\manual\Build-Manual.ps1
```

Use `-SkipApplicationStart` con una demo disponible y `-Headed` para observar Chromium. Los resultados quedan en `artifacts/manual/`. El manifest define orden, rol, ruta, captura y contenido. Sólo se versionan scripts, plantillas, manifest y contenido fuente. Capturas, HTML, PDF, metadata, traces y reportes están ignorados. Use únicamente datos ficticios y nunca persista claves. La limpieza segura consiste en eliminar `artifacts/manual`; no use `Reset` para generar el manual.