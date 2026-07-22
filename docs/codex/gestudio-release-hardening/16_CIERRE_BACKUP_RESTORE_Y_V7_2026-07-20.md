# Cierre técnico — integración V7, backup y restore

> Fecha: 20 de julio de 2026  
> Zona horaria: `America/Argentina/Buenos_Aires`  
> Decisión global: **NO-GO para demo comercial, staging y producción**

## 1. Alcance

Este cierre consolida dos bloques posteriores a GATE-1B:

1. integración source-owned de referencias mínimas de estudiantes para Jere Platform;
2. backup y restore reproducible de PostgreSQL y recibos.

No incluye despliegue, base real, transporte automático, staging ni producción.

## 2. Integración V7

Integrada en `main` mediante PR `#15` y merge commit:

```text
e1afec960ddeb72d61932a1eb1f4a83a65899540
```

Capacidad incorporada:

- referencia `GESTUDIO_STUDENT`;
- payload limitado a ID, nombre de visualización y activo;
- mapping explícito deployment/academia → tenant UUID;
- feature deshabilitada por defecto;
- snapshots y páginas append-only;
- cursor opaco y checkpoint UUID;
- SHA-256 y HMAC-SHA256 sobre bytes exactos;
- secreto independiente de 32 bytes o más;
- POST/GET administrativos;
- permisos simultáneos `PERM_CONFIG_ADMIN` y `PERM_REPORTES_EXPORTAR`;
- auditoría sin payload ni secretos;
- Flyway `V7__jere_platform_student_source_exports.sql`.

Exclusiones deliberadas:

- documento;
- email;
- teléfono;
- nacimiento;
- responsables;
- notas;
- datos de salud;
- cuotas o deuda;
- asistencia;
- disciplina;
- metadata libre;
- transporte automático;
- UI;
- scheduler;
- broker;
- Scalaris.

### Bloqueo externo

La operación end-to-end multipágina continúa bloqueada por:

```text
JerePrograma/jere-platform#59
```

Por lo tanto, el emisor está integrado y probado, pero no debe declararse operativa la reconciliación externa completa.

## 3. Evidencia de aplicación después de V7

Sobre el HEAD validado del PR `#15`:

- backend: 162/162 PASS;
- frontend: 142/142 PASS;
- lint: PASS;
- build frontend: PASS;
- `Scope All`: PASS;
- backend image: PASS;
- frontend image: PASS;
- smoke canónico V1-V7: PASS;
- seed doble V1-V7: PASS;
- residuos Docker: ninguno;
- `GATE-1B validation`: success;
- `CI Gestudio`: success.

V1-V6 permanecieron inmutables. Después de aplicar V7, cualquier corrección de esquema debe usar una migración nueva forward-only.

## 4. Backup y restore

Archivos incorporados:

- `scripts/ops/backup-postgres.ps1`;
- `scripts/ops/restore-postgres.ps1`;
- `scripts/ops/verify-backup-restore.ps1`;
- `.github/workflows/backup-restore-verification.yml`;
- `docs/operations/backup-restore.md`;
- `docs/operations/local-runbook.md`.

### Backup

- `pg_dump` en formato custom;
- compresión 9;
- sin owner ni privileges;
- recibos opcionales en `tar.gz`;
- backend detenido para consistencia de aplicación cuando se incluyen recibos;
- paquete incompleto eliminado ante fallo;
- manifiesto JSON con:
  - UTC;
  - proyecto;
  - base y usuario;
  - HEAD Git;
  - cantidad y última versión Flyway;
  - tamaño y SHA-256 del dump;
  - tamaño y SHA-256 de recibos;
  - indicador de consistencia.

### Restore

- confirmación destructiva obligatoria;
- identificador PostgreSQL validado;
- bases reservadas rechazadas;
- restore sobre origen rechazado por defecto;
- overwrite de recibos requiere confirmación propia;
- hashes y tamaños validados antes de destruir destino;
- archivo de recibos inspeccionado antes de extraer;
- `dropdb --force`, `createdb` y `pg_restore --exit-on-error`;
- cantidad y versión Flyway verificadas después del restore;
- backend detenido cuando corresponde y reiniciado al finalizar.

Actualización de seguridad del 21 de julio de 2026:

- los nombres declarados por el manifiesto quedan limitados a los basenames canónicos y confinados al paquete;
- los argumentos del archivo no se interpolan en `sh -ec`;
- los miembros tar se validan antes de extraer y sólo se admiten archivos regulares o directorios bajo `receipts/`;
- symlinks, hardlinks, dispositivos, FIFOs, rutas absolutas y segmentos de escape se rechazan;
- dump y recibos se copian a temporales privados y se revalida su SHA-256 inmediatamente antes de usarlos;
- la promoción de recibos conserva el contenido anterior dentro del volumen y lo restaura si falla el reemplazo;
- `-RestoreReceipts` se rechaza cuando `TargetDatabase` no es la base activa del proyecto, evitando mezclar una base alternativa con el volumen original;
- el acceso HTTP y el worker de recibos rechazan symlinks y rutas cuyo destino real escape del directorio configurado.

El drill local posterior a este hardening terminó el 21 de julio con 10 etapas,
0 fallos y cleanup completo en 8 min 20 s. Esa evidencia no reemplaza el
workflow del SHA final ni altera los límites productivos de este cierre.

## 5. Primer drill y corrección

La primera ejecución produjo:

- backup creado y manifiesto válido;
- cleanup correcto;
- resultado global FAIL.

Causa:

`psql` devolvió dos líneas para `INSERT ... RETURNING id`:

```text
1
INSERT 0 1
```

El drill utilizó ambas como ID al ejecutar el `DELETE`. Se corrigió el parser para tomar únicamente la primera línea y exigir `^[0-9]+$`.

No se ocultó ni se reclasificó el fallo inicial.

## 6. Drill verde

Workflow:

```text
Backup restore verification
```

Evidencia:

- runner: Ubuntu 24.04.4;
- SHA del merge ref probado: `6f50659f18207104b32a8db76fb14951437b61a2`;
- branch head correspondiente: `8ef5405cbc38dbbb6f0b627f27b6f84a4e16ab26`;
- Git: 2.54.0;
- Docker: 28.0.4;
- Docker Compose: 2.38.2;
- PowerShell: 7.6.3;
- duración: `00:02:17`;
- pasos aprobados: 9;
- fallos: 0;
- resultado global: PASS;
- artefacto digest: `sha256:987a80fc0de9d9632ceba220acd75faa3548a594ec440873ca9138054f13e521`.

### Casos aprobados

1. Docker disponible;
2. stack descartable healthy;
3. Flyway V1-V7 en origen;
4. fixture sintética creada;
5. backup y manifiesto verificados;
6. origen mutado después del backup;
7. guardas destructivas verificadas;
8. restore PostgreSQL y recibos verificado;
9. limpieza Docker.

También se comprobó:

- alumno restaurado en la base alternativa;
- alumno ausente en el origen mutado;
- tablas V7 presentes;
- recibo restaurado byte a byte;
- cero contenedores, volúmenes y redes residuales.

## 7. Qué queda cerrado

- capacidad source V7: integrada y probada;
- Flyway V1-V7 sobre base vacía: probado;
- backup técnico: probado;
- restore aislado: probado;
- integridad de hashes: probada;
- guardas destructivas: probadas;
- runbook local: publicado.

## 8. Qué continúa abierto

- receptor multipágina de Jere Platform;
- política de destino externo y cifrado;
- retención;
- RPO/RTO;
- responsables y frecuencia;
- rollback forward-compatible;
- observabilidad y alertas;
- recorridos humanos;
- GATE-2;
- staging;
- producción.

## 9. Riesgo residual explícito

PostgreSQL y recibos no forman una transacción distribuida. El backup detiene el backend para obtener un punto consistente, pero un restore puede completar la base y fallar después al reemplazar archivos. La mitigación vigente es:

1. validar hashes y tar antes de destruir destino;
2. restaurar primero en una base alternativa;
3. operar dentro de una ventana de mantenimiento;
4. conservar el paquete original;
5. verificar DB, Flyway y archivos antes de promover el resultado.

## 10. Veredicto

**Backup y restore quedan cerrados técnicamente en infraestructura descartable.**

Esto no equivale a política productiva de recuperación ni habilita staging o producción. El siguiente gate operativo es rollback forward-compatible, seguido por observabilidad y recorridos humanos.
