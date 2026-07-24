# Estrategia de pruebas

> Estado: PARCIAL  
> Última revisión: 2026-07-24  
> Fuentes principales: `backend/pom.xml`, `frontend/package.json`, `docs/testing`

## Backend

Spring Boot Test, Spring Security Test, JUnit Jupiter, Testcontainers PostgreSQL, Mockito como javaagent y JaCoCo 0.8.15.

## Frontend

Vitest 4, Testing Library, jsdom y checks Node para nginx. `npm test` ejecuta ambos grupos.

## Operativas

`validate.ps1`, smoke local, seed demo, backup/restore, rollback, observabilidad y recorridos humanos por rol.

## Criterios

Cubrir éxito, autorización, validación, nulos/límites y persistencia. Una prueba fallida bloquea publicación; no afirmar éxito sin ejecutar.

## PENDIENTE

Cobertura real por módulo y áreas concretas sin tests.