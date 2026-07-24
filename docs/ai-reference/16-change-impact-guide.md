# Guía de impacto de cambios

> Estado: CONFIRMADO/PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: arquitectura y scripts de validación

## Contrato/endpoint

Revisar controlador, DTO, validación, servicio, repositorio, seguridad, cliente HTTP, pantallas y pruebas; verificar status codes y compatibilidad.

## Entidad/persistencia

Revisar entidad, repositorios, mappers, DTO, migración nueva, constraints, consultas, seed, backup/restore y rollback. No editar V1–V7.

## Permisos

Revisar catálogo, roles, guards backend, navegación frontend, demo de cinco roles y pruebas fail-closed.

## Finanzas

Preservar vigencias y snapshot `cargo_liquidaciones`; probar fechas límite, histórico y rechazo legacy.

## Pre-commit

`git diff`, `git status`, validación canónica, smoke aplicable, ausencia de secretos/artefactos, enlaces y alcance.