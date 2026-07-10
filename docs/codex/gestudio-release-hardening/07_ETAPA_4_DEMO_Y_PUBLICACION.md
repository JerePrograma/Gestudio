# Etapa 4 — Refinamiento, demo comercial y publicación

> Estado: `PENDING`  
> Gate previo requerido: `GATE-3` cerrado y autorización explícita  
> Gate de salida: `GATE-4`  
> Baseline documental: `main` en `b833f6741cf614c508666e8a121701e8db2fcf9a`

[Índice](./00_INDEX.md) · [Baseline](./01_BASELINE_Y_HALLAZGOS.md) · [Etapa 3](./06_ETAPA_3_COMPONENTES_Y_CONTRATOS.md) · [Plan de pruebas](./08_PLAN_DE_PRUEBAS.md) · [Bitácora](./09_BITACORA_IMPLEMENTACION.md) · [Decisiones](./10_DECISIONES_Y_BLOQUEOS.md) · [Checklist release](./11_CHECKLIST_RELEASE.md)

## Objetivo

Hacer que Gestudio explique qué requiere atención, demostrar separación real por rol y completar una demo comercial reproducible de 10–15 minutos antes de evaluar staging o producción.

## Fuera de alcance

- Reabrir gates funcionales anteriores para sumar funciones no necesarias para la demo.
- Crear dashboard configurable, marketplace de widgets o sistema analítico nuevo.
- Mezclar seed demo con catálogo RBAC/migraciones productivas.
- Publicar, migrar una base real o usar credenciales reales sin autorización específica.
- Agregar una plataforma E2E/observabilidad/deploy sin comprobar que las herramientas actuales no cubren el gate.

## Dependencias y condiciones de entrada

- [ ] `GATE-1`, `GATE-1B`, `GATE-2` y `GATE-3` cerrados con evidencia.
- [ ] Autorización explícita para Etapa 4 registrada en la bitácora.
- [ ] [11_CHECKLIST_RELEASE.md](./11_CHECKLIST_RELEASE.md) actualizado antes de cualquier staging/producción.
- [ ] Ambientes, responsables, dominio/TLS, datos permitidos, ventana y rollback definidos antes de mutaciones externas.
- [ ] Sólo una tarea E4 está `IN_PROGRESS`.

## Estado actual verificado

- `VALIDADO`: existen `Dashboard.tsx`, `Reportes.tsx`, API/componente de observaciones, `scripts/gestudio_demo_seed_full.sql`, `scripts/smoke-local.ps1`, Dockerfiles y `docker-compose.yml`.
- `VALIDADO`: el dashboard actual reutiliza navegación filtrada; todavía no prueba señales operativas por rol.
- `VALIDADO`: el seed demo es un script separado, pero actualmente suple permisos que deben pertenecer al catálogo productivo; no puede ser requisito de bootstrap.
- `VALIDADO`: el frontend tiene 33/36 tests verdes en el baseline actual, por lo que el gate de release está rojo.
- `NO_VERIFICADO`: no se ejecutaron demo por rol, navegador PC/celular, base limpia, upgrade, Docker limpio, staging, backup/restore ni rollback.
- `RIESGOSO`: el compose actual usa nombres/puertos que dificultan aislamiento; Docker no debe iniciarse automáticamente.
- `PENDING`: ninguna tarea E4 fue iniciada; `GATE-4` está abierto y no existe autorización de publicación.

## Orden obligatorio de tareas

### E4-001 — Dashboard operativo

- **Estado:** `PENDING`.
- **Dependencias:** `GATE-3`; consultas y permisos ya estabilizados.
- **Archivos esperados:** `frontend/src/paginas/Dashboard.tsx`, APIs/DTOs existentes de asistencia, pagos/deuda, caja y notificaciones.
- **Cambio esperado:** 3–5 señales por permiso: clases de hoy, deuda/pagos que requieren atención, caja de hoy, cumpleaños y accesos rápidos.
- **Estrategia:** componer endpoints existentes; crear una consulta nueva sólo si evita múltiples lecturas incoherentes. Sin widgets configurables.
- **Riesgo/rollback:** consultas pesadas o exposición entre roles. Medir y filtrar backend; retirar una señal sin afectar los módulos fuente.
- **Aceptación:** cada rol ve sólo información accionable autorizada y estados empty/error útiles.
- **Validación/evidencia:** tests de permiso/DTO, componente y revisión por rol. `NO_VERIFICADO`.

### E4-002 — Hub único de Reportes

- **Estado:** `PENDING`.
- **Dependencias:** permisos de reportes/exportación y formatos de Etapa 3.
- **Archivos esperados:** `frontend/src/paginas/Reportes.tsx`, `frontend/src/funcionalidades/reportes/`, `ReporteControlador.java`, `ReporteServicio.java`.
- **Cambio esperado:** entrada única, catálogo humano de reportes y exportación visible sólo con permiso.
- **Estrategia:** integrar reportes existentes; no construir un motor genérico ni duplicar consultas.
- **Riesgo/rollback:** exportar datos no autorizados o inconsistentes. Autorizar backend y probar contenido; ocultar exportación no validada.
- **Aceptación:** acceso directo/API no escala privilegios y archivos no exponen IDs técnicos.
- **Validación/evidencia:** 401/403/permitido, contenido/filename y flujo UI. `NO_VERIFICADO`.

### E4-003 — Decidir Observaciones

- **Estado:** `PENDING`.
- **Dependencias:** decisión de producto/ownership registrada.
- **Archivos esperados:** `ObservacionProfesorControlador.java`, API/DTO/mapeador de observaciones y cualquier componente/ruta frontend existente.
- **Cambio esperado:** integrar con ruta, permiso y ownership completos o retirar/ocultar el flujo de la release.
- **Estrategia:** preferir retirar de alcance si no existe contrato comercial confirmado; no dejar una función a medio conectar.
- **Riesgo/rollback:** exponer notas privadas. Mantenerla deshabilitada hasta probar acceso propio/global según matriz.
- **Aceptación:** no existe endpoint o acción ambiguamente accesible.
- **Validación/evidencia:** decisión, tests de ownership si se habilita y búsqueda de callers/rutas. `NO_VERIFICADO`.

### E4-004 — Empty states con siguiente acción

- **Estado:** `PENDING`.
- **Dependencias:** flujos finales y permisos.
- **Archivos esperados:** páginas operativas y `EmptyState` existente.
- **Cambio esperado:** explicar por qué no hay datos y ofrecer una única acción válida cuando corresponda.
- **Estrategia:** reutilizar `EmptyState`; textos específicos por flujo, sin nueva abstracción.
- **Riesgo/rollback:** sugerir una acción prohibida. Derivar la acción del mismo permiso/estado; quitarla si no puede garantizarse.
- **Aceptación:** estados vacíos críticos de la demo tienen mensaje y siguiente paso autorizados.
- **Validación/evidencia:** tests de empty state por permiso y recorrido manual. `NO_VERIFICADO`.

### E4-005 — Responsive y accesibilidad

- **Estado:** `PENDING`.
- **Dependencias:** pantallas finales.
- **Archivos esperados:** layout, navegación, tablas/formularios críticos y estilos existentes.
- **Cambio esperado:** flujo usable en PC y celular, teclado, foco visible, labels, diálogos y errores anunciables.
- **Estrategia:** corregir pantallas del recorrido demo; no rediseñar módulos fuera de él.
- **Riesgo/rollback:** romper desktop al ajustar mobile. Verificar ambos tamaños por cambio y revertir sólo la regla afectada.
- **Aceptación:** checklist manual y pruebas automatizadas disponibles pasan en los recorridos críticos.
- **Validación/evidencia:** build, pruebas de componentes, teclado/foco y capturas/checklist PC-celular. `NO_VERIFICADO`.

### E4-006 — Dataset demo separado

- **Estado:** `PENDING`.
- **Dependencias:** RBAC productivo determinístico y decisiones de datos demo.
- **Archivos esperados:** `scripts/gestudio_demo_seed_full.sql`, documentación y scripts de carga/limpieza descartable si fueran necesarios.
- **Cambio esperado:** datos ficticios reproducibles para roles y recorrido, sin secretos ni permisos operativos obligatorios.
- **Estrategia:** conservar seed fuera de Flyway; ejecutarlo sólo sobre base descartable identificada y después de migrar/bootstrap.
- **Riesgo/rollback:** contaminar una base real o esconder un bootstrap roto. Guardas explícitas y base efímera; rollback descartando la base.
- **Aceptación:** base limpia funciona sin seed y, con seed, la demo no requiere SQL manual adicional.
- **Validación/evidencia:** migración/bootstrap sin seed y carga/demo con seed en otra base descartable. `NO_VERIFICADO`.

### E4-007 — E2E por rol

- **Estado:** `PENDING`.
- **Dependencias:** `E4-001` a `E4-006`, matriz final y dataset demo.
- **Archivos esperados:** [08_PLAN_DE_PRUEBAS.md](./08_PLAN_DE_PRUEBAS.md), scripts/tests existentes; nueva herramienta sólo con decisión justificada.
- **Cambio esperado:** recorridos Dirección, Secretaría, Caja y Profesor si está habilitado, incluyendo intentos denegados.
- **Estrategia:** comenzar con smoke HTTP y guion reproducible; automatizar navegador con herramienta ya disponible antes de agregar dependencia.
- **Riesgo/rollback:** E2E frágil o credenciales expuestas. Datos efímeros, secretos externos y selectores accesibles; retirar sólo automatización inestable, no el criterio de demo.
- **Aceptación:** cada rol completa su recorrido y no puede completar uno prohibido.
- **Validación/evidencia:** comandos, tiempos, resultados y capturas mínimas registradas. `NO_VERIFICADO`.

### E4-008 — Smoke de base limpia

- **Estado:** `PENDING`.
- **Dependencias:** `E4-006`; Docker/Testcontainers disponible conscientemente.
- **Archivos esperados:** `scripts/smoke-local.ps1`, configuración de test y Flyway.
- **Cambio esperado:** migrar base descartable, bootstrap, login, perfil y operaciones mínimas sin seed demo.
- **Estrategia:** reutilizar el smoke existente; no tocar `localhost:5432` ni iniciar Docker automáticamente.
- **Riesgo/rollback:** ejecutar contra datos reales. Validar URL/nombre de base y abortar si no es descartable; rollback destruyendo sólo el recurso efímero verificado.
- **Aceptación:** smoke termina en cero y demuestra uso inicial real.
- **Validación/evidencia:** comando exacto, versión de migraciones y conteos registrados. `NO_VERIFICADO`.

### E4-009 — Staging/producción, backup, observabilidad y rollback

- **Estado:** `PENDING`.
- **Dependencias:** smoke verde y ambiente/autoridad definidos.
- **Archivos esperados:** `docker-compose.yml`, Dockerfiles, perfiles `application-*.yml`, workflow, runbook/checklist y scripts de backup existentes.
- **Cambio esperado:** checklist ejecutable de secretos, TLS/CORS, salud, logs/métricas, migración, backup/restore y rollback de aplicación/datos.
- **Estrategia:** documentar y probar capacidades existentes; cambiar infraestructura sólo donde un gate concreto falle.
- **Riesgo/rollback:** indisponibilidad o pérdida de datos. Backup restaurado antes de release, artefacto anterior disponible y recovery SQL forward-only revisado.
- **Aceptación:** staging reproduce producción, restore fue probado y rollback tiene responsable/tiempo/comando.
- **Validación/evidencia:** Docker limpio, health/smoke, backup+restore y simulacro rollback. `NO_VERIFICADO`.

### E4-010 — Informe final de release

- **Estado:** `PENDING`.
- **Dependencias:** `E4-001` a `E4-009` y checklist completo.
- **Archivos esperados:** todos los documentos de esta carpeta, especialmente índice, bitácora, decisiones y checklist.
- **Cambio esperado:** versión/commit, alcance, migraciones, roles, comandos/resultados, demo, riesgos, rollback y decisión go/no-go.
- **Estrategia:** enlazar evidencia; no copiar logs ni declarar pruebas no ejecutadas.
- **Riesgo/rollback:** publicar con evidencia incompleta. Estado `NO-GO` por defecto hasta que todos los gates obligatorios estén validados.
- **Aceptación:** un tercero puede reproducir validación, demo y rollback desde el informe.
- **Validación/evidencia:** revisión cruzada de documentos y Git; `NO_VERIFICADO`.

## Estrategia transversal

1. Cerrar primero la demo interna; staging y producción requieren autoridad separada.
2. Usar datos ficticios y bases descartables hasta la aprobación de publicación.
3. Mantener seed demo, RBAC productivo y migraciones como responsabilidades separadas.
4. Reutilizar scripts/configuración existentes y cambiar sólo gates fallidos.
5. No marcar un checklist con inferencias: cada `VALIDADO` debe enlazar comando, fecha y resultado.

## Validación final

```powershell
git status --short --branch
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Frontend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope Backend
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\codex\validate.ps1 -Scope All
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\smoke-local.ps1
```

Además deben quedar registrados el Docker build pertinente, Flyway base limpia/upgrade, dataset demo, recorridos por rol, backup/restore y rollback. Ninguno está validado por este documento.

## GATE-4

- [ ] Demo de 10–15 minutos completada sin SQL manual.
- [ ] No hay IDs técnicos ni acciones no-op en el recorrido.
- [ ] No hay permisos sorpresa y los roles demuestran separación real.
- [ ] Tarifas, cargos, recibos y caja conservan exactitud.
- [ ] PC y celular pasan el checklist responsive/accesible.
- [ ] Base limpia y upgrade fueron probados.
- [ ] Validación Frontend, Backend y All está verde.
- [ ] Dataset demo está separado de RBAC productivo.
- [ ] Checklist release, backup/restore y rollback están completos.
- [ ] Riesgos residuales y decisión go/no-go son explícitos.

**Estado del gate:** `PENDING` / `NO-GO`. Cerrar Etapa 4 no autoriza por sí solo una mutación externa: staging o producción requieren la autorización indicada en [11_CHECKLIST_RELEASE.md](./11_CHECKLIST_RELEASE.md).
