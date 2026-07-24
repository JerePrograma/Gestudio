# Mantenimiento documental

> Estado: CONFIRMADO  
> Última revisión: 2026-07-24  
> Fuentes principales: protocolo definido para `docs/ai-reference`

## Cuándo actualizar

| Cambio | Documentos |
|---|---|
| Endpoint/DTO | 05, 06, 08, 16, 22, 25 |
| Ruta UI | 07, 08, 22, 25 |
| Permiso/rol | 10, 16, 18, 22, 25 |
| Entidad/migración | 04, 09, 16, 18, 22 |
| Job | 05, 14, 18, 22, 26 |
| Integración | 05, 08, 10, 11, 18, 22 |
| Build/CI | 12, 13, 14, 17, 22 |
| Release remoto | README, 13, 14, 23, 27 |
| Demo/manual | 12, 17, 28 |
| Decisión | 19 y documento temático |

## Procedimiento

1. Actualizar `main` por fast-forward.
2. Leer `AGENTS.md`.
3. Inspeccionar código/config/pruebas afectados.
4. Actualizar documento temático sin copiar código completo.
5. Marcar `CONFIRMADO`, `INFERIDO` o `PENDIENTE`.
6. Actualizar `22-source-index.md`.
7. Actualizar `23-ai-working-context.md` sólo si cambia contexto crítico.
8. Validar links, rutas, símbolos y ausencia de secretos.
9. Revisar diff exclusivamente documental.
10. Commit/push descriptivo.

## Resolución de contradicciones

Código y pruebas prevalecen sobre docs. `AGENTS.md` prevalece sobre `.kiro`. Cuando dos documentos actuales difieren, registrar la contradicción en `21-open-questions.md` y no elegir una versión sin evidencia.

## Trazabilidad

Toda conclusión relevante debe citar ruta y, cuando aporte valor, clase/método. Fechas de validación y SHA base deben registrarse sin intentar auto-referenciar el SHA del commit que contiene el documento.

## Enlaces

Desde esta carpeta:

- raíz: `../../`;
- documentación hermana: `../`;
- documentos de autoreferencia: nombre directo.

Validar que cada link relativo exista. No enlazar artefactos fuera del repo como si fueran versionados.

## Control de crecimiento

- Un concepto tiene un documento propietario.
- Otros documentos enlazan, no duplican.
- `23-ai-working-context.md` debe permanecer compacto.
- Listas mecánicas grandes sólo cuando son contratos, como RBAC/rutas.
- Archivar evidencia histórica fuera de esta base; resumirla en 27.

## Checklist automatizable

- archivos no vacíos;
- encabezado y fecha;
- links internos;
- rutas fuente;
- ausencia de patrones de secretos;
- índice incluye todos los `.md`;
- estados de certeza;
- no hay comandos inventados;
- diff sólo documental.

## Revisión periódica

Revisar tras cada release y, como mínimo, cuando cambie el HEAD operativo de `main`, el número de mappings, migraciones, permisos, rutas UI o tests.
