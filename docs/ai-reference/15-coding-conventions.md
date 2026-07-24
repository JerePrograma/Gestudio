# Convenciones de código

> Estado: CONFIRMADO  
> Última revisión: 2026-07-24  
> Fuentes principales: `../../AGENTS.md`, configuración y patrones observados

## Principio general

Seguir el patrón existente y realizar el cambio mínimo. No convertir la aplicación a otra arquitectura dentro de una tarea funcional.

## Java/Spring

- Paquetes y nombres en español según dominio existente.
- Inyección por constructor.
- DTO request/response explícitos; preferir records públicos.
- No exponer entidades JPA.
- Bean Validation en frontera.
- Servicios concretos salvo frontera externa real.
- Transacción a nivel de caso de uso.
- `BigDecimal` para dinero; `compareTo`, escala y redondeo explícitos.
- `Clock` y zona explícita para fecha de negocio.
- Spring Boot BOM administra dependencias Spring.
- MapStruct/Lombok sólo siguiendo configuración Maven.
- No `@Data` indiscriminado en entidades con relaciones.

## Persistencia

- Flyway es fuente de verdad.
- `ddl-auto=validate`.
- No modificar migraciones aplicadas.
- No borrar historia financiera/auditable.
- Revisar `cascade`, `orphanRemoval` y `ON DELETE CASCADE`.
- No usar `clear()` para alterar una respuesta JSON.

## API y errores

- Ruta y método deben entrar en la matriz RBAC.
- 401 para autenticación; 403 para autorización.
- Errores estándar mediante `TratadorDeErrores`.
- No exponer mensajes internos.
- Mantener contratos legacy hasta versionarlos deliberadamente.

## Logging

Un evento útil por operación. Registrar IDs, estado y resultado, no payload completo, token, contraseña, email body, entidad completa ni datos personales extensos. Cálculo detallado a DEBUG.

## Frontend

- TypeScript estricto.
- `import.meta.env`.
- Axios compartido.
- React Query donde ya existe.
- Formik/Yup para formularios existentes.
- Backend autoridad de cálculo.
- 401 con refresh serializado; 403 sin cerrar sesión.
- No `localStorage.clear()`, `as unknown as`, IP productiva hardcodeada ni librería duplicada.

## Pruebas

Regresión primero para bug; caracterización antes de refactor financiero. PostgreSQL/Testcontainers para comportamiento DB. No probar privados por reflexión si existe contrato público.

## Dependencias

No añadir/actualizar para ocultar un problema. Versionar lockfile y usar `npm ci`. No usar `npm audit fix --force` sin análisis.

## Git

Cambios enfocados, diff revisado, sin temporales ni secretos. En este proyecto, cuando se ordena publicación directa, usar `main` y `origin/main` sin force ni reescritura.

## Inconsistencias observadas

Hay imports duplicados, comentarios legacy, respuestas HTTP heterogéneas y controladores con manejo local de excepciones. Son deuda; no constituyen una convención a imitar.
