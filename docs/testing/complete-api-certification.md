# Certificación integral de endpoints

## Objetivo

Validar de forma repetible la API completa de Gestudio sin contaminar la demo
compartida con datos técnicos ni exponer credenciales.

El comando canónico es:

```powershell
pwsh -NoProfile `
  -File .\scripts\certify-api-complete.ps1
```

La contraseña de `demo-superadmin` se solicita mediante entrada segura. No se
acepta como argumento, no se escribe en archivos y no se incorpora a los
informes.

## Qué significa «todos los endpoints»

La certificación separa tres evidencias que no deben confundirse:

1. **Inventario y política HTTP:** `SecurityHttpIntegrationTest` descubre todos
   los `@RestController` y todos sus mappings reales. La prueba falla si cambia
   la cantidad, aparece una ruta sin política RBAC o un usuario autorizado no
   alcanza el controlador.
2. **Ciclo funcional real:** `scripts/smoke-local.ps1` levanta PostgreSQL,
   backend y frontend en un proyecto Docker efímero. Ejecuta altas académicas,
   tarifa histórica, inscripción, liquidaciones, cargos, pagos parciales y
   totales, recibos, caja, egresos, idempotencia, stock, reversión, RBAC,
   reinicio e integridad SQL. Al finalizar destruye contenedores, red y
   volúmenes de esa ejecución.
3. **Demo pública:** autentica contra Cloudflare Pages, rota la cookie refresh,
   consulta los módulos y relaciones disponibles sobre el seed realista,
   descarga reportes/PDF, valida CORS, cierra sesión y confirma la revocación.
   Esta fase no crea alumnos, pagos, egresos ni otros datos de negocio.

Así, todas las rutas quedan cubiertas por el inventario dinámico y la matriz
HTTP, mientras los flujos de negocio mutables se prueban con PostgreSQL real en
un entorno descartable.

## Datos

- No se usan personas reales.
- La fase aislada utiliza datos sintéticos y claves de idempotencia únicas.
- La fase pública utiliza únicamente los datos demostrativos existentes.
- Los informes no almacenan request bodies, contraseñas, JWT, cookies ni
  secretos de Cloudflare.

## Informes

Por defecto se generan fuera del checkout:

```text
%USERPROFILE%\Documents\Gestudio-Certifications\
```

Cada ejecución produce:

```text
api-certification-<fecha>-<id>.json
api-certification-<fecha>-<id>.md
```

Los informes incluyen:

- commit certificado;
- estado y duración de cada fase;
- escenario, método, ruta, HTTP, duración y request ID de cada prueba pública;
- fallo sanitizado, cuando corresponda.

## Requisitos

- Windows y PowerShell 7.
- Git, JDK 21, Maven Wrapper, Node.js y Docker Desktop.
- `main` limpia y sincronizada con `origin/main`.
- Demo pública encendida y accesible.
- Credencial vigente de `demo-superadmin`.

## Variantes

Sólo inventario, seguridad y demo pública:

```powershell
pwsh -NoProfile `
  -File .\scripts\certify-api-complete.ps1 `
  -SkipIsolatedLifecycle
```

Sólo inventario, seguridad y ciclo aislado:

```powershell
pwsh -NoProfile `
  -File .\scripts\certify-api-complete.ps1 `
  -SkipPublic
```

Salida HTTP detallada:

```powershell
pwsh -NoProfile `
  -File .\scripts\certify-api-complete.ps1 `
  -VerboseHttp
```

## Criterio de aprobación

La certificación es `PASS` únicamente cuando:

- el inventario dinámico y la matriz RBAC pasan;
- el ciclo aislado finaliza sin fallos de negocio, idempotencia o integridad;
- todas las solicitudes públicas previstas devuelven estados permitidos;
- ninguna solicitud pública devuelve `5xx`;
- login, refresh, logout y CORS cumplen su contrato;
- el árbol Git permanece limpio;
- se generan ambos informes sin secretos.

## Seguridad posterior

Toda contraseña pegada en un chat, ticket o captura debe considerarse expuesta.
Después de la certificación se debe rotar la contraseña demo y revocar las
sesiones activas mediante el mecanismo soportado del repositorio.
