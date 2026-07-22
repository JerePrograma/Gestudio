# Validación de Gestudio

Esta guía define los comandos soportados. Los resultados de una release se
registran en la bitácora de cierre correspondiente; iniciar un servidor o
compilar una parte del proyecto no sustituye estos gates.

## Requisitos

- JDK 21 indicado por `JAVA_HOME`;
- Docker Engine y Docker Compose disponibles para Testcontainers y los drills;
- Node.js 22 LTS y npm;
- PowerShell 7 para el flujo principal y Windows PowerShell 5.1 para la
  comprobación de compatibilidad cuando se trabaja en Windows.

El Maven global no es un requisito: se usa siempre el wrapper versionado.

## Backend

Desde la raíz, en PowerShell:

```powershell
Push-Location backend
try {
    .\mvnw.cmd --version
    .\mvnw.cmd -B -ntp clean test
    .\mvnw.cmd -B -ntp clean verify
}
finally {
    Pop-Location
}
```

En Linux o GitHub Actions, reemplazar `mvnw.cmd` por `bash ./mvnw`.

`clean verify` incluye pruebas unitarias, seguridad HTTP, PostgreSQL real con
Testcontainers, Flyway desde cero y desde estados de actualización soportados,
concurrencia, planes de consulta y contratos de arquitectura. Los reportes
JaCoCo se generan bajo `backend/target/site/jacoco/`; `target/` no se versiona.

Las pruebas de confinamiento de recibos crean enlaces simbólicos. En Windows
pueden omitirse únicamente cuando el sistema niega el privilegio de crearlos;
en Linux/GitHub Actions deben ejecutarse y pasar. El reporte final debe indicar
la cantidad exacta de skips observados en cada plataforma.

## Frontend

Partiendo de una instalación reproducible:

```powershell
Push-Location frontend
try {
    npm ci
    npm audit
    npm audit --omit=dev
    npm run lint
    npm test
    npm run build
}
finally {
    Pop-Location
}
```

El script `npm test` ejecuta primero los contratos Node de Nginx y después
Vitest. El build usa las variables Vite documentadas y su salida queda en
`frontend/dist/`, que tampoco se versiona.

## Validación integrada

```powershell
pwsh -NoProfile -File .\scripts\codex\validate.ps1 -Scope All
pwsh -NoProfile -File .\scripts\validate-demo-seed.ps1
pwsh -NoProfile -File .\scripts\smoke-local.ps1
pwsh -NoProfile -File .\scripts\ops\verify-observability.ps1
pwsh -NoProfile -File .\scripts\ops\verify-backup-restore.ps1
pwsh -NoProfile -File .\scripts\ops\verify-application-rollback.ps1
```

Cada drill crea un nombre de proyecto Compose aislado, comprueba sus propios
recursos y ejecuta limpieza en `finally`. No se deben usar nombres de proyecto
compartidos ni comandos de limpieza global de Docker.

## Criterio de reporte

Para cada comando se registra código de salida, duración, cantidad de pruebas,
fallos, errores y skips. Un resultado previo a la última modificación sirve
sólo como diagnóstico; la evidencia de release debe corresponder al mismo árbol
que se publica y a las GitHub Actions ejecutadas sobre su SHA.
