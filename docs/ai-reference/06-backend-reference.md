# Referencia backend

> Estado: CONFIRMADO  
> Última revisión: 2026-07-24  
> Fuentes principales: `../../backend/pom.xml`, paquetes bajo `backend/src/main/java/gestudio`

## Stack

Java 21; Spring Boot 3.5.16; Spring Web, Security, Validation, Data JPA y Actuator; PostgreSQL y Flyway; Auth0 Java JWT; MapStruct; Lombok; OpenPDF; Spring Mail; Micrometer Prometheus; Maven Wrapper.

Pruebas: Spring Boot Test, Spring Security Test, JUnit, Mockito, Testcontainers PostgreSQL y JaCoCo.

## Organización

| Paquete | Responsabilidad |
|---|---|
| `gestudio.controladores` | API general |
| `gestudio.servicios.<capacidad>` | casos de uso |
| `gestudio.entidades` | JPA |
| `gestudio.repositorios` | Spring Data |
| `gestudio.dto` | request/response y mappers |
| `gestudio.infra.seguridad` | JWT, filtros, CORS y RBAC |
| `gestudio.infra.errores` | error contract |
| `gestudio.infra.observabilidad` | métricas y correlación |
| `gestudio.tarifas` | tarifas y condiciones por vigencia |
| `gestudio.cuotas` | liquidación |
| `gestudio.integraciones.jereplatform` | exportación firmada |

## Controladores por capacidad

- Seguridad: `AutenticacionControlador`, `UsuarioControlador`, `RolControlador`, `PermisoControlador`.
- Académico: `AlumnoControlador`, `ProfesorControlador`, `DisciplinaControlador`, `SalonControlador`, `InscripcionControlador`.
- Asistencia: `AsistenciaDiariaControlador`, `AsistenciaMensualControlador`.
- Economía: `TarifaDisciplinaControlador`, `CondicionEconomicaControlador`, `MatriculaControlador`, `MensualidadControlador`, `CargoControlador`.
- Cobranza: `PagoControlador`, `MetodoPagoControlador`, `CreditoControlador`, `CajaControlador`, `EgresoControlador`.
- Configuración/stock: `StockControlador`, `ConceptoControlador`, `SubConceptoControlador`, `BonificacionControlador`, `RecargoControlador`.
- Salida: `ReporteControlador`, `NotificacionControlador`.
- Integración: `StudentSourceExportController`.
- Dormante: `ObservacionProfesorControlador`, denegado por seguridad.

## Servicios relevantes

- `PagoServicio`, `CargoServicio`, `CreditoServicio`, `CajaServicio`, `EgresoServicio`, `StockServicio`.
- `MensualidadServicio`, `MatriculaServicio`, `LiquidacionCargoServicio`.
- `TarifaDisciplinaServicio`, `CondicionEconomicaServicio`.
- `AutenticacionService`, `TokenService`, servicios de usuario/rol/permiso.
- `ReciboStorageService`, `PdfService`, `IEmailService`.
- `StudentSourceExportService`.
- `ScheduledTasks`.

## DTO y mapeo

Los controladores nuevos/actualizados deben exponer DTO explícitos; no entidades JPA. Se prefieren records inmutables. `PageResponse` es el wrapper estable usado en varios endpoints, pero aún existen respuestas `Page`/`PageImpl` legacy.

## Validación y errores

Bean Validation protege requests y parámetros. `TratadorDeErrores` devuelve `ApiErrorResponse` con timestamp, status, code, message y field errors. Códigos relevantes: `VALIDATION_ERROR`, `UNAUTHORIZED`, `FORBIDDEN`, `NOT_FOUND`, `IDEMPOTENCY_CONFLICT`, `OVERAPPLICATION`, `INSUFFICIENT_CREDIT`, `INSUFFICIENT_STOCK`, `HISTORICAL_PRICING_NOT_DEFINED`.

## Seguridad

Toda familia API se declara en `SecurityConfigurations`; el fallback es `denyAll`. La política se duplica como contrato ejecutable en `SecurityHttpIntegrationTest`, que inventaría 146 mappings.

## Convenciones de extensión

1. Añadir endpoint y DTO.
2. Declarar permiso backend.
3. Actualizar contrato dinámico de seguridad.
4. Actualizar cliente/tipo/ruta UI si aplica.
5. Añadir regresión.
6. Ejecutar `clean verify`, frontend gates y smoke según impacto.
