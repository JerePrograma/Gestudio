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

Los gates de métricas se ejecutan mediante el orquestador permanente:

```powershell
.\scripts\codex\quality-fortress.ps1 -Scope BackendCoverage
.\scripts\codex\quality-fortress.ps1 -Scope BackendDiffCoverage -DiffBase origin/main
.\scripts\codex\quality-fortress.ps1 -Scope BackendMutationGlobal
.\scripts\codex\quality-fortress.ps1 -Scope BackendMutationCritical
.\scripts\codex\quality-fortress.ps1 -Scope BackendStatic -DiffBase origin/main
```

`BackendCoverage` exige 90% líneas/85% ramas globales, 95%/90% en familias
críticas y 95% de ramas en autorización. El diff exige 90%. PIT exige 80% de
mutación y 85% de fuerza global, y 90%/90% en capacidades críticas. Los
verificadores rechazan artefactos ausentes, viejos, vacíos, inconsistentes o
generados fuera del marcador de ejecución. Coverage, Gherkin y PIT incluyen
tests PostgreSQL: Docker/Testcontainers son obligatorios.

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

Los gates de cobertura y análisis frontend son:

```powershell
.\scripts\codex\quality-fortress.ps1 -Scope FrontendCoverage
.\scripts\codex\quality-fortress.ps1 -Scope FrontendDiffCoverage -DiffBase origin/main
.\scripts\codex\quality-fortress.ps1 -Scope FrontendStatic -DiffBase origin/main
```

El release exige 85% líneas, 80% ramas y 85% sentencias globales, además de 90%
de líneas para servicios/guards críticos. El diff calcula hunks ejecutables
reales y exige 90% en líneas, sentencias y ramas; los cambios sólo de tipos se
clasifican explícitamente. Un inventario independiente impide que una fuente
ejecutable sin mapa se cuente como cubierta. La duplicación se mide sobre
producto, excluye tests de forma explícita y falla al superar 2%.

## Supply chain

```powershell
.\scripts\codex\quality-fortress.ps1 -Scope SupplyChain
```

Este scope ejecuta ambos `npm audit`, OWASP Dependency-Check backend, SBOM
CycloneDX backend/frontend y la policy de Actions con referencias inmutables.
CodeQL y TruffleHog se ejecutan en el workflow de seguridad del SHA publicado;
un análisis local parcial no los sustituye.

## E2E del control plane

El runner canónico es:

```powershell
pwsh -NoProfile -File .\scripts\e2e\run-control-plane.ps1
```

El runner crea un proyecto Compose efímero con credenciales sintéticas, prueba
B12 fresh, bootstrap one-shot, MFA/step-up, tenants Alpha/Beta, RLS adversarial,
suspensión/reactivación, auditoría exacta y axe en Chromium, y limpia sólo los
recursos propios. No debe apuntarse a `gestudio-remote-demo` ni a una DB
persistente. `npm run e2e:typecheck` y `npm run e2e:list` validan el arnés, pero
no constituyen evidencia browser.

El gate E2E de CI exige además el recorrido financiero completo:

Para el ensayo de recuperación, fijar previamente `$historicalCommit` al SHA40
de un ancestro aprobado distinto de HEAD. CI usa el baseline de PR/push o el
input manual explícito; no infiere `HEAD^` del último commit de revisión.

```powershell
pwsh -NoProfile -File .\scripts\e2e\run-control-plane.ps1 -FinancialFlow -RecoveryDrill -RecoveryHistoricalCommit $historicalCommit
```

Esta variante rechaza `-PersistentDemo`, reconstruye backend y frontend sin
capas reutilizadas y habilita sólo el worker de recibos a un segundo, con cron
de negocio apagados y correo NOOP/sin red. El usuario Alpha se inscribe desde
UI, recibe cuota 100.50 y matrícula 20.00, paga 120.50 desde UI, consulta caja
y descarga el PDF real generado por el outbox. Se comparan los bytes API y
descarga, se verifica Beta 404 después de que el archivo existe y se reconcilian
registros, importes, outbox completado y ausencia de envíos mediante SQL.
`PdfServiceTest` extrae texto del PDF real con OpenPDF para verificar alumno,
fecha, pago, cargos e importes; no sustituye la prueba browser.

El stage opcional `receipt-path-validation` reutiliza el build Linux y exige
ejecutar las dos pruebas de symlinks con un ID único: XML con dos casos
nombrados y cero skips/fallos/errores. El runtime final no depende de ese stage.
El resultado y log sanitizados quedan en `artifacts/e2e/result.json`,
`playwright.log`, `receipt-path-linux.log` e `image-builds.log` (IDs de imágenes
en el JSON); los recursos efímeros se limpian.
El contrato del runner se ejecuta con PowerShell 7 y también admite 5.1:
`scripts/e2e/test-run-control-plane-contract.ps1`.
El runner invoca el CLI local de Playwright directamente mediante Node: evita
que el shim `npm.ps1` consuma el separador `--` y transforme la configuración
en un filtro sin escenarios en Windows.

`-RecoveryDrill` agrega continuidad del producto al mismo proyecto efímero:
backup v3 consistente de PostgreSQL y el PDF real, restore a una base alternativa,
restore activo después de alterar sólo el alumno y PDF sintéticos, cambio al
backend histórico compatible con las migraciones actuales y retorno al actual.
Cada fase compara filas financieras, identidad/RBAC, auditoría y Flyway; exige
login Alpha/Beta, importes, caja, PDF idéntico, aislamiento y MFA de plataforma.
Los campos MFA completos, incluidos contador anti-replay y fecha de uso, se
comparan antes de nuevos logins; luego se usa un TOTP de un paso posterior.
Las claves sintéticas permanecen en la configuración privada separada del backup.
El log sanitizado adicional es `financial-recovery.log`. El workflow exige esta
variante; los contratos sin cargas se verifican con
`scripts/e2e/test-financial-recovery-contract.ps1` (PS7/5.1) y
`node --test frontend/scripts/verify-financial-recovery.test.mjs`.

Para preparar scans sobre los mismos IDs probados puede agregarse
`-ExportCandidateImages`: escribe archivos Docker en
`artifacts/e2e/candidate-<runId>/` y registra IDs, SHA256 y tamaños en el resultado.
No conserva contenedores, volúmenes ni tags del proyecto. Los archivos se aceptan
como candidato sólo si el gate completo termina en `PASS`; un cambio de SHA en
CI exige nuevas imágenes y scans propios, aunque las fuentes coincidan.
El arranque financiero usa `--no-build` después del clean build y comprueba,
antes del navegador, que los IDs de ambos contenedores coincidan exactamente
con las imágenes preparadas y exportadas; conserva las attestations OCI.

Después de ese `PASS`, `scripts/security/scan-e2e-candidate.ps1` genera SBOM Syft y
CycloneDX y ejecuta Grype sobre los archivos exactos. Vincula índice OCI o config
Docker clásico, config, capas ordenadas, SBOM, hashes de archivos y reporte;
rechaza inventarios vacíos o cambios durante la lectura. El gate falla ante
hallazgos High/Critical, sin ignores ni filtro de vulnerabilidades con arreglo.
La base de vulnerabilidades debe ser válida y tener menos de 24 horas.
CI usa Python 3.12.15 explícito y una caché propia que actualiza antes del scan.
Para una caché local ya preparada puede indicarse `-ExistingDatabaseVolume`:
se monta sólo lectura y no descarga herramientas ni actualiza datos ajenos.
Los comandos, códigos, identidad de herramientas, base y hashes quedan en
`artifacts/e2e/security-<runId>-attempt-<n>/scan-result.json` y archivos asociados.
`-Attempt <n>` permite conservar cada intento previo sin sobrescribir evidencia.

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
