# Recorridos humanos por rol — GATE-2

> Estado: pendiente de ejecución humana.  
> Datos permitidos: exclusivamente sintéticos.  
> Resultado esperado: evidencia funcional, visual y de autorización por cada rol.

La demo automatizada demuestra contratos técnicos, pero no detecta textos confusos, IDs internos visibles, navegación defectuosa, foco perdido, layouts rotos o acciones difíciles de comprender. Este documento define cómo cerrar esa brecha.

## 1. Precondiciones

1. rama `main` actualizada y estado Git limpio;
2. demo persistente levantada;
3. seed aplicado sin errores;
4. cinco usuarios disponibles;
5. navegador con consola y panel de red accesibles;
6. resolución de escritorio y móvil documentadas;
7. carpeta local de evidencia fuera de Git.

Comandos:

```powershell
git switch main
git pull --ff-only origin main

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\demo-local.ps1 `
  -Action Reset
```

## 2. Evidencia obligatoria

Para cada recorrido registrar:

- fecha y zona horaria;
- SHA de `main`;
- navegador y versión;
- resolución;
- usuario/rol;
- paso ejecutado;
- resultado esperado;
- resultado observado;
- `X-Request-ID` cuando haya error;
- captura sin secretos ni datos reales;
- severidad del defecto;
- decisión PASS/FAIL.

No capturar:

- contraseñas;
- cookies;
- tokens;
- `.env`;
- cabeceras `Authorization`;
- datos personales reales.

## 3. Severidad

| Severidad | Definición | Efecto |
|---|---|---|
| P0 | pérdida/corrupción, acceso indebido o imposibilidad total | bloquea todo |
| P1 | flujo principal incorrecto o confuso sin alternativa segura | bloquea demo comercial |
| P2 | defecto importante con alternativa clara | requiere backlog y decisión |
| P3 | cosmético o mejora menor | no bloquea por sí solo |

## 4. Controles comunes para todos los roles

- login y logout;
- refresh de sesión;
- menú acorde a permisos;
- ruta no autorizada devuelve `403` o redirige con mensaje claro;
- sesión ausente devuelve `401` sin pantalla rota;
- estados loading, vacío y error;
- búsqueda por nombre, apellido, ambos órdenes y documento;
- cero IDs técnicos como única referencia visible;
- moneda ARS consistente;
- foco visible;
- navegación por teclado;
- labels asociados;
- contraste legible;
- viewport de escritorio y móvil;
- respuesta con `X-Request-ID` cuando se inspecciona la red.

## 5. SUPERADMIN

### Objetivo

Demostrar configuración, seguridad y operación completa.

### Pasos

1. iniciar sesión como `demo-superadmin`;
2. revisar perfil y permisos efectivos;
3. crear un salón sintético;
4. crear profesor sintético;
5. crear disciplina sintética;
6. crear horario;
7. crear tarifa con vigencia;
8. crear método de pago y concepto;
9. crear usuario de prueba;
10. asignar y retirar un rol permitido;
11. confirmar que `PROFESOR` no sea asignable;
12. crear alumno e inscripción;
13. verificar mensualidad, matrícula y snapshot;
14. registrar pago, recibo y caja;
15. registrar y revertir movimiento de stock;
16. consultar reportes;
17. cerrar sesión.

### Criterio de cierre

- todas las funciones inventariadas accesibles;
- ninguna superficie oculta por error;
- ninguna función fuera de inventario expuesta;
- operaciones financieras coherentes;
- cero error P0/P1.

## 6. DIRECCION

### Objetivo

Demostrar gestión y reportes sin administración de seguridad.

### Pasos

1. iniciar sesión como `demo-direccion`;
2. consultar alumnos, disciplinas, asistencia y reportes;
3. operar funciones de gestión autorizadas;
4. intentar abrir administración de roles por menú y URL directa;
5. confirmar denegación explícita;
6. revisar que no existan botones que luego fallen por permiso;
7. cerrar sesión.

### Criterio de cierre

- gestión y reportes disponibles;
- roles/permisos no visibles ni operables;
- URL directa protegida;
- cero error P0/P1.

## 7. ADMINISTRADOR

### Objetivo

Demostrar operación amplia sin gobierno de roles.

### Pasos

1. iniciar sesión como `demo-administrador`;
2. gestionar configuración operativa permitida;
3. crear/editar alumno e inscripción;
4. operar asistencia;
5. revisar obligaciones y reportes permitidos;
6. intentar administración de roles;
7. confirmar denegación;
8. cerrar sesión.

### Criterio de cierre

- operación amplia completa;
- seguridad no administrable;
- mensajes y acciones coherentes con permisos;
- cero error P0/P1.

## 8. SECRETARIA

### Objetivo

Demostrar alta de alumnos, inscripción y asistencia sin acceso a caja, egresos o seguridad.

### Pasos

1. iniciar sesión como `demo-secretaria`;
2. buscar alumno por distintas referencias humanas;
3. crear alumno sintético;
4. editar datos permitidos;
5. crear inscripción sobre disciplina con tarifa;
6. confirmar obligaciones iniciales sin editar importes legacy;
7. registrar asistencia;
8. probar estado vacío y error recuperable;
9. intentar egresos, seguridad y funciones financieras restringidas;
10. confirmar denegaciones;
11. cerrar sesión.

### Criterio de cierre

- circuito alumno → inscripción → asistencia completo;
- ninguna acción financiera o de seguridad indebida;
- cero ID técnico imprescindible para operar;
- cero error P0/P1.

## 9. CAJA

### Objetivo

Demostrar obligaciones, cobros, recibos, caja y stock permitido sin gestión académica restringida.

### Pasos

1. iniciar sesión como `demo-caja`;
2. buscar alumno por referencia humana;
3. consultar cargos y saldos;
4. registrar pago;
5. repetir con misma idempotency key y confirmar no duplicación;
6. consultar/generar recibo;
7. comprobar movimiento de caja;
8. registrar venta de stock permitida;
9. revertirla y comprobar compensación;
10. intentar gestión académica o seguridad restringida;
11. confirmar denegaciones;
12. cerrar sesión.

### Criterio de cierre

- cobro y recibo correctos;
- caja consistente;
- stock nunca negativo;
- reintento no duplica;
- restricciones académicas y de seguridad efectivas;
- cero error P0/P1.

## 10. Matriz de UX

| Área | Escritorio | Móvil | Teclado | Loading | Vacío | Error | IDs humanos |
|---|---|---|---|---|---|---|---|
| Login | pendiente | pendiente | pendiente | pendiente | N/A | pendiente | N/A |
| Alumnos | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Inscripciones | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Tarifas | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Asistencia | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Cargos/pagos | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Caja/egresos | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Recibos | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Stock | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Reportes | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |
| Usuarios/roles | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente | pendiente |

## 11. Plantilla de hallazgo

```text
ID: UX-YYYYMMDD-NNN
SHA:
Rol:
Pantalla:
Paso:
Esperado:
Observado:
Severidad:
Request-ID:
Evidencia:
Reproducibilidad:
Impacto:
Propuesta:
Estado:
```

## 12. Decisión de gate

GATE-2 sólo puede declararse `PASS` cuando:

- los cinco roles completan su recorrido;
- todas las denegaciones esperadas fueron verificadas;
- no hay P0 ni P1 abiertos;
- los P2 tienen decisión explícita;
- escritorio y móvil están cubiertos;
- foco, teclado, labels y contraste fueron revisados;
- loading, vacío y error tienen siguiente acción clara;
- la evidencia identifica el SHA exacto;
- backend, frontend, smoke y seed permanecen verdes después de las correcciones.

Hasta entonces la demo comercial continúa en `NO-GO`.
