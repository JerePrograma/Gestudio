# Referencia backend

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: `backend/pom.xml`, `backend/src/main/java/gestudio`

## Stack

Java 21, Spring Boot 3.5.16, Maven Wrapper, Web, Security, Validation, Data JPA, Actuator, Mail, PostgreSQL, Flyway, JWT Auth0, MapStruct, Lombok y OpenPDF.

## Controladores relevantes

`gestudio/controladores`: autenticación, alumnos, usuarios, roles, permisos, profesores, disciplinas, salones, inscripciones, asistencias, matrículas, mensualidades, cargos, pagos, caja, créditos, egresos, inventario, reportes y notificaciones.

Especializados: `gestudio/tarifas/api/*`, `gestudio/integraciones/jereplatform/api/StudentSourceExportController`, `gestudio/infra/errores/TratadorDeErrores`.

## Convenciones

DTO, Bean Validation, servicios transaccionales, repositorios JPA y mappers. Revisar consumidores antes de modificar contratos.

## PENDIENTE

Inventariar servicios, repositorios, entidades, jobs y eventos símbolo por símbolo.