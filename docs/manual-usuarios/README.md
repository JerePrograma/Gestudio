# Manual de usuarios y demo comercial de Gestudio

Este directorio contiene las fuentes reproducibles del manual para clientes,
dueños de academias y personal no técnico. El resultado combina explicaciones
breves, cuentas sintéticas autorizadas y capturas de la aplicación real.

## Cómo abrir el manual final

Después de generarlo, abrir:

    artifacts/manual/manual.html

El HTML es autocontenido: incluye estilos e imágenes y puede consultarse sin
Internet. Los enlaces a la demo pública sí necesitan conexión.

También se genera:

    artifacts/manual/Manual_Gestudio_Usuarios_Nuevos.pdf

## Fuentes

| Ruta | Uso |
|---|---|
| manifest.json | Orden de los 40 capítulos y capturas asociadas. |
| content/*.html | Contenido editorial en español para clientes. |
| data/demo-accounts.json | Única fuente de las cuentas demo autorizadas y su matriz comprobada. |
| templates/manual.html | Estructura del documento. |
| templates/manual.css | Diseño de pantalla e impresión. |
| scripts/manual/flows/capture-manual.cjs | Recorrido de sólo consulta y capturas reales. |
| scripts/manual/Render-Manual.ps1 | Composición de HTML, PDF y metadata. |
| scripts/manual/Validate-Manual.ps1 | Controles de estructura, enlaces, imágenes y contenido sensible. |

No se usa un framework adicional, una fuente remota ni una CDN.

## Cuentas demo autorizadas

Por indicación expresa del propietario, las nueve contraseñas sintéticas y la
clave TOTP de demostración se publican en data/demo-accounts.json y en el
manual generado. No son credenciales productivas y no deben reutilizarse.

Ese archivo no puede contener:

- token del proxy público;
- códigos de recuperación;
- tokens de sesión;
- cookies;
- credenciales de PostgreSQL;
- direcciones internas;
- secretos de infraestructura.

El renderer crea desde esa única fuente la sección de credenciales, las tarjetas
por perfil y la matriz. Así se evita mantener contraseñas duplicadas en varios
fragmentos.

## Generación pública completa en un checkout limpio

Desde la raíz:

    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\manual\Build-Manual.ps1 -PublicDemo

El orquestador conserva su precondición de Git limpio. Comprueba la demo pública,
recorre el fixture multiorganización existente sin modificarlo, captura las
pantallas, genera HTML/PDF y valida el resultado. En este modo no necesita
Docker ni Java y no inicia servicios locales.

## Generación durante una edición documental

Cuando el worktree contiene cambios revisados y no corresponde hacer commit,
stash ni usar otro worktree, ejecutar las etapas por separado:

    $output = Join-Path (Get-Location) 'artifacts\manual'
    $public = 'https://gestudio-demo-jere-287b8c90.pages.dev/'
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\manual\Capture-Manual.ps1 -BaseUrl $public -OutputDirectory $output
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\manual\Render-Manual.ps1 -BaseUrl $public -BackendUrl ($public.TrimEnd('/') + '/api') -OutputDirectory $output
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\manual\Validate-Manual.ps1 -OutputDirectory $output

Este recorrido no modifica datos funcionales: inicia sesión, consulta pantallas,
aplica filtros y cierra las sesiones. No confirma pagos, egresos, bajas,
anulaciones, cambios de permisos ni acciones de plataforma.

## Generación con el fixture local multiorganización

Sin `-PublicDemo`, `Build-Manual.ps1` usa
`scripts/demo-local-multitenant.ps1` para iniciar, comprobar y detener únicamente
la demo persistente de este proyecto. Requiere PowerShell 7 (`pwsh`), Docker y
JDK 21, además de Node. Conserva los datos existentes y no ejecuta Reset.

Las capturas leen las credenciales privadas del fixture en memoria. No las
copian a las fuentes, al HTML, al PDF ni a la metadata. Las cuentas y claves
publicadas en el manual siguen siendo exclusivamente las de la demo pública.

Si el fixture local no tiene una cuenta de presentación, el recorrido general
usa Secretaría. El manual muestra una nota de origen y una leyenda acorde;
la metadata registra `LocalMultitenant`, `SECRETARIA` y ocho cuentas distintas
verificadas en nueve recorridos. Con una cuenta de presentación configurada,
usa `DEMO_COMERCIAL` y verifica nueve cuentas distintas.

Para ejecutar las etapas locales por separado sobre una demo ya iniciada:

    $output = Join-Path (Get-Location) 'artifacts\manual'
    $credentials = Join-Path $env:LOCALAPPDATA 'Gestudio\gestudio-demo-local\credentials.json'
    $capture = & .\scripts\manual\Capture-Manual.ps1 -BaseUrl 'http://localhost:18081' -OutputDirectory $output -CredentialManifestPath $credentials
    & .\scripts\manual\Render-Manual.ps1 -OutputDirectory $output -CaptureSource $capture.CaptureSource -GeneralCaptureProfile $capture.GeneralCaptureProfile -CapturedAccountCount $capture.CapturedAccountCount
    & .\scripts\manual\Validate-Manual.ps1 -OutputDirectory $output

El manifiesto privado se rechaza para cualquier URL que no sea local.

## Qué verifican las capturas

- ingreso habitual con campos vacíos;
- cuenta de presentación de Escuela Danza Marcos Paz;
- módulos académicos, financieros, catálogos y reportes;
- menús de Secretaría, Caja, Administración, Dirección y SUPERADMIN;
- denegación esperada por permisos;
- datos propios de Escuela Beta Demo;
- ingreso de plataforma con campos vacíos;
- organizaciones, detalle, administradores y auditoría de plataforma;
- inicio y cierre de sesión de las nueve cuentas documentadas.

Las capturas usan una ventana de 1440×1000, ocultan identificadores internos y
no incluyen contraseñas, códigos temporales ni información del navegador.

## Artefactos

    artifacts/manual/
    ├── manual.html
    ├── Manual_Gestudio_Usuarios_Nuevos.pdf
    ├── metadata.json
    └── screenshots/*.png

Los artefactos y capturas están ignorados por Git. Las fuentes del manual sí se
versionan.

## Actualizar un capítulo

1. Confirmar el comportamiento en la interfaz actual.
2. Contrastar rutas, permisos y reglas con código o pruebas.
3. Editar el fragmento correspondiente sin agregar lenguaje técnico.
4. Si cambia una pantalla, actualizar el recorrido y el nombre declarado en el
   manifest.
5. Regenerar HTML/PDF.
6. Ejecutar Validate-Manual.ps1.
7. Abrir el HTML y recorrer todos los enlaces.
8. Renderizar el PDF a imágenes y revisar cada página.

## Principios editoriales

- Explicar tareas y beneficios reales, no componentes técnicos.
- Usar “organización” o “academia”; reservar “tenant” para el glosario.
- Distinguir cargo, pago, aplicación, crédito, caja y egreso.
- No presentar funciones que sólo existen en servicios internos.
- Señalar límites visibles de la demo sin convertir el manual en un informe de
  pruebas.
- Proponer recorridos de consulta que no alteren datos compartidos.

La lista completa de comprobaciones está en
[LOCAL_VALIDATION.md](LOCAL_VALIDATION.md).
