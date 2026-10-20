# Demo pública multitenant mediante Cloudflare Pages

## Alcance y estados de readiness

Este runbook publica la demo local multitenant persistente de Gestudio. Es una
demo comercial temporal: no es un despliegue productivo ni reemplaza las gates
completas del repositorio.

El launcher sólo puede declarar el siguiente resultado después de completar
todos los controles locales y públicos de este documento:

```text
PUBLIC_DEMO_READINESS=PASS
```

Ese resultado queda deliberadamente separado de:

```text
REPOSITORY_CODE_READINESS=NOT_ESTABLISHED_BY_THIS_RUNBOOK
PRODUCTION_ENVIRONMENT_READINESS=NOT_ESTABLISHED_BY_THIS_RUNBOOK
```

`REPOSITORY_CODE_READINESS` requiere sus validaciones completas independientes,
incluidos los gates backend y frontend aplicables. `PRODUCTION_ENVIRONMENT_READINESS`
requiere otra arquitectura operativa, seguridad, disponibilidad, backups,
observabilidad y recuperación. Que la demo pública esté disponible no acredita
ninguno de esos dos estados.

## Identidad de la publicación

| Concepto | Valor |
|---|---|
| Proyecto Cloudflare Pages | `gestudio-demo-jere-287b8c90` |
| URL pública única | `https://gestudio-demo-jere-287b8c90.pages.dev/` |
| Proyecto Docker Compose local | `gestudio-demo-local` |
| Tenant promocional | `Escuela Danza Marcos Paz` (Alpha) |
| Usuario promocional | `alpha.demo.presentacion` |
| Manifiesto privado de la contraseña | `%LOCALAPPDATA%\Gestudio\gestudio-demo-local\credentials.json` |

El valor de la contraseña no se documenta, imprime ni copia a Git. El operador
puede leerlo localmente desde el manifiesto privado, dentro de su sesión de
Windows. Es una credencial sintética exclusiva de esta demo y no debe
reutilizarse en ningún otro sistema.

El usuario promocional sólo posee el rol comercial preparado por el fixture de
demo. Puede recorrer las áreas funcionales principales, pero no puede acceder a
control plane, administración de plataforma, tenants, MFA, usuarios, roles ni
configuración de seguridad.

El tenant Beta (`Escuela Beta Demo`) se conserva para pruebas privadas y
demostraciones guiadas. El `PLATFORM_SUPERADMIN`, sus factores MFA y sus códigos
de recuperación son exclusivamente operativos y nunca se publican. La
publicación mantiene RLS, memberships, aislamiento HTTP y de base de datos,
auditoría, lifecycle y persistencia; no crea un modo single-tenant alternativo.

## Arquitectura preservada

```text
navegador
  -> https://gestudio-demo-jere-287b8c90.pages.dev
  -> Pages Function /api o /api/*
  -> Quick Tunnel https://<aleatorio>.trycloudflare.com
  -> proceso cloudflared local
  -> http://127.0.0.1:18080
  -> backend demo multitenant
  -> PostgreSQL local no publicado
```

Cloudflare Pages sirve la SPA y conserva API y cookie en el mismo origin. El
Quick Tunnel sólo apunta al backend loopback. No existe túnel hacia PostgreSQL,
Docker, archivos, logs, métricas ni otros puertos.

Antes, el publicador convergía el escenario legacy single-tenant de
`scripts/demo-remote.ps1`. El flujo vigente llama a
`scripts/demo-local-multitenant.ps1` y converge el proyecto persistente
`gestudio-demo-local`. `scripts/demo-remote.ps1` ya no es una dependencia
funcional del comando público y no debe ejecutarse como paso adicional.

No se crea un segundo mecanismo de publicación: se reutilizan el proyecto
Pages, la Pages Function, Wrangler y Quick Tunnel existentes.

## Contratos de seguridad

### Exposición local y CORS

- El backend permanece enlazado exclusivamente a `127.0.0.1:18080`.
- PostgreSQL no posee exposición pública y nunca es destino de `cloudflared`.
- El único origin CORS permitido es
  `https://gestudio-demo-jere-287b8c90.pages.dev`.
- No se admiten wildcard, previews de Pages ni `trycloudflare.com` como origins
  CORS.
- El visitante nunca recibe el hostname Quick Tunnel como URL de la demo.

### Pages Function

`frontend/functions/api/[[path]].js`, junto con
`frontend/public/_routes.json`, mantiene este contrato:

- sólo acepta y reenvía `/api` y `/api/*`;
- conserva método, body, query, `Authorization`, cookie y `Origin`;
- elimina dinámicamente todos los headers `X-Forwarded-*` y también los
  headers de forwarding o identidad de red falsificables (`Forwarded`, `Host`,
  `CF-*`, `X-Real-IP`, `True-Client-IP` y `Via`);
- sobreescribe cualquier valor entrante y añade el
  `X-Gestudio-Proxy-Token` controlado por Pages;
- usa seguimiento manual de redirects y reescribe `Location` y
  `Content-Location` absolutos del Quick Tunnel al origin Pages, conservando
  path, query y fragment;
- aplica `Cache-Control: no-store` a toda respuesta y a todo error;
- devuelve errores genéricos sin revelar el origin interno.

El backend exige el proxy token en toda ruta `/api`. Una solicitud directa al
Quick Tunnel sin ese token debe responder `404`. El token es independiente de
JWT, passwords y credenciales de base de datos, se conserva fuera de Git y no se
imprime.

`/actuator` y `/actuator/**` no están incluidos en las rutas de la Function. La
validación pública debe comprobar que Pages no devuelve contenido de actuator ni
los reenvía al backend. Los endpoints locales de readiness sólo los consume el
launcher desde loopback.

### Sesión promocional

Login, refresh y logout se ejecutan exclusivamente mediante el origin
`pages.dev`. La cookie de refresh debe ser host-only y contener todas estas
propiedades:

```text
Secure; HttpOnly; SameSite=Strict; Path=/api/login
```

No debe contener `Domain`. Los JWT, cookies y payloads de autenticación nunca se
incluyen en la salida del launcher ni en sus logs operativos.

## Configuración de Pages

El launcher actualiza en el proyecto existente:

| Variable | Tratamiento |
|---|---|
| `GESTUDIO_BACKEND_ORIGIN` | origin HTTPS del Quick Tunnel vigente; no se muestra como URL pública |
| `GESTUDIO_PROXY_TOKEN` | secreto independiente generado o reutilizado fuera de Git |

El frontend se construye para producción con:

```text
VITE_API_BASE_URL=https://gestudio-demo-jere-287b8c90.pages.dev/api
```

Luego se publica `frontend/dist` mediante Wrangler en
`gestudio-demo-jere-287b8c90`. No se crea otro proyecto Pages. Como la política
CORS admite un único origin, los deployments preview no forman parte de esta
demo.

## Procedimiento del operador

### START/PUBLISH

Desde Windows PowerShell:

```powershell
Set-Location C:\laburo\Gestudio
.\DESPLEGAR-DEMO-REMOTA.cmd
```

El comando debe, en este orden:

1. verificar repositorio, rama `main`, relación con `origin/main`, herramientas
   y configuración local sin descartar el worktree;
2. verificar Docker Desktop y que el daemon sea local;
3. iniciar o converger `scripts/demo-local-multitenant.ps1 -Action Start` sin
   ejecutar `Reset`;
4. exigir que el `Status` local termine en `PASS`;
5. verificar el binding loopback del backend y la ausencia de publicación de
   PostgreSQL;
6. reutilizar o generar el proxy token independiente y la credencial
   promocional privada sin mostrarlos;
7. iniciar un único Quick Tunnel hacia `http://127.0.0.1:18080` y obtener
   internamente su hostname aleatorio;
8. actualizar `GESTUDIO_BACKEND_ORIGIN` y `GESTUDIO_PROXY_TOKEN` en Pages;
9. construir el frontend con el `VITE_API_BASE_URL` exacto y publicar `dist` en
   el proyecto existente;
10. esperar DNS y disponibilidad pública;
11. ejecutar el gate público completo descrito más abajo;
12. declarar `PUBLIC_DEMO_READINESS=PASS` únicamente si todo pasó.

La salida final no debe contener secretos ni el hostname Quick Tunnel. Debe
mostrar como URL de usuario final solamente:

```text
DEMO PUBLICA DISPONIBLE
https://gestudio-demo-jere-287b8c90.pages.dev/
```

Puede agregar después instrucciones operativas no sensibles sobre los procesos
que deben permanecer activos.

### STATUS

```powershell
.\DESPLEGAR-DEMO-REMOTA.cmd -Action Status
```

Esta acción consulta el estado sin ejecutar `Reset`, rotar credenciales ni
duplicar fixtures. Debe fallar si la demo local no termina `PASS`, si el proceso
`cloudflared` registrado no está activo o si ya no se cumplen los controles
públicos. No debe imprimir secretos, cookies, tokens ni el origin Quick Tunnel.

### STOP

```powershell
.\DESPLEGAR-DEMO-REMOTA.cmd -Action Stop
```

Esta acción detiene primero el Quick Tunnel registrado y luego los servicios de
la demo. Conserva los volúmenes, la configuración privada, las credenciales, el
fixture y la auditoría. La SPA ya publicada puede continuar respondiendo desde
Pages, pero la demo no se considera disponible sin API y no puede conservar
`PUBLIC_DEMO_READINESS=PASS`.

### Rotación explícita de la credencial promocional

```powershell
.\DESPLEGAR-DEMO-REMOTA.cmd -RotatePublicCredential
```

Esta es la única operación normal que regenera la contraseña de
`alpha.demo.presentacion`. La rotación actualiza el manifiesto privado y la
identidad demo de forma controlada; no muestra el nuevo valor, no rota otros
secretos, no recrea la base y no altera tenants ni datos de negocio. Después de
rotar, el operador vuelve a obtener la contraseña únicamente desde
`%LOCALAPPDATA%\Gestudio\gestudio-demo-local\credentials.json`.

## Persistencia y convergencia

Repetir START/PUBLISH o reiniciar el equipo no debe:

- recrear la base de datos;
- duplicar tenants, memberships, usuarios ni datos del seed;
- rotar contraseñas o tokens sin una orden explícita;
- borrar o reescribir auditoría existente;
- ejecutar `Reset`;
- migrar el flujo a `gestudio-remote-demo`.

El launcher converge sobre el volumen y el estado privado existentes. El seed
demo es idempotente y sólo se reaplica cuando su contrato lo requiere. STOP
preserva el proyecto `gestudio-demo-local`; destruir volúmenes o usar Reset no
forma parte de este procedimiento público.

## Gate de aceptación pública

El gate debe registrar estados y códigos HTTP, pero nunca cuerpos o headers que
contengan secretos. Antes de declarar la demo disponible debe verificar:

1. `Status` local multitenant `PASS`.
2. Frontend `pages.dev` con HTTP `200` y SPA cargable.
3. API accesible mediante `/api` exclusivamente a través de `pages.dev`.
4. Login de `alpha.demo.presentacion` exitoso.
5. Perfil autenticado perteneciente a `Escuela Danza Marcos Paz`.
6. Un listado funcional contiene datos Alpha y no contiene datos Beta.
7. Refresh exitoso y cookie completa `Secure`, `HttpOnly`, `SameSite=Strict`,
   `Path=/api/login`, sin `Domain`.
8. Logout exitoso y sesión invalidada.
9. Solicitud directa al Quick Tunnel sin proxy token con respuesta `404`.
10. `/actuator` y `/actuator/**` en Pages no exponen ni proxifican actuator.
11. Backend aún enlazado sólo a `127.0.0.1:18080`.
12. PostgreSQL sin puerto público ni túnel.
13. Ningún secreto versionado y `git diff --check` exitoso.

Las comprobaciones positivas de frontend, login, perfil, listado, refresh y
logout usan siempre
`https://gestudio-demo-jere-287b8c90.pages.dev`. La única llamada directa al
Quick Tunnel es el control negativo sin token, y su hostname no se imprime.

## Procesos que deben permanecer activos

Mientras la demo esté disponible deben permanecer activos:

- el PC host, sin suspensión;
- la conexión a Internet;
- Docker Desktop;
- el stack `gestudio-demo-local`, incluidos backend y PostgreSQL;
- el proceso `cloudflared` iniciado y registrado por el launcher.

Si cualquiera se detiene, ejecutar STATUS y luego START/PUBLISH cuando la causa
esté resuelta.

## Limitaciones y riesgos de Quick Tunnel

- El subdominio `trycloudflare.com` es aleatorio y puede cambiar cuando se crea
  un túnel nuevo; el launcher debe actualizar Pages antes de validar.
- Quick Tunnel es para desarrollo y pruebas, no ofrece SLA ni garantía de
  uptime.
- Cloudflare documenta un límite de 200 solicitudes concurrentes en curso y
  respuesta `429` al superarlo.
- Quick Tunnel no soporta Server-Sent Events.
- La disponibilidad depende del host, su red, Docker, el backend y un único
  proceso local `cloudflared`; no hay alta disponibilidad.
- La persistencia local no equivale a almacenamiento productivo administrado ni
  reemplaza backups y pruebas de recuperación.
- Compartir la contraseña promocional amplía la superficie de abuso. Debe
  rotarse explícitamente al finalizar una campaña o ante cualquier duda.

Las limitaciones del servicio se mantienen en la
[documentación oficial de Quick Tunnels](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/).

## Registro de una ejecución

No completar este bloque por anticipado ni copiar resultados de otra sesión. El
operador registra fecha, commit y resumen no sensible sólo después de ejecutar
START/PUBLISH o STATUS:

```text
FECHA_UTC=<fecha de la ejecución>
COMMIT=<commit validado>
PUBLIC_DEMO_READINESS=<PASS o FAIL observado>
REPOSITORY_CODE_READINESS=<resultado de su gate independiente>
PRODUCTION_ENVIRONMENT_READINESS=<resultado de su gate independiente>
```
