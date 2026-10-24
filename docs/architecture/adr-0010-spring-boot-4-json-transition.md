# ADR-0010: Spring Boot 4 y transición del contrato JSON

## Decisión

Usar Java 21 y Spring Boot 4.0.9, con Spring Framework 7.0.10, Spring Security
7.0.8, Tomcat 11 y las dependencias gestionadas por ese BOM. La migración
resuelve la línea de Framework afectada por CVE-2026-47884 y CVE-2026-47890
sin depender de una suscripción Spring Enterprise ni mezclar Framework 7 con
Boot 3. El resultado de seguridad se acredita con scans de las imágenes
exactas; la elección de versiones por sí sola no constituye un PASS.

Se conservan PostgreSQL, las migraciones Flyway publicadas, los DTO, permisos,
aislamiento tenant/platform y reglas financieras. No se convierte ningún
importe a punto flotante ni se altera el historial del esquema.

## Compatibilidad JSON explícita

El módulo oficial `spring-boot-jackson2` conserva los consumidores actuales de
`com.fasterxml.jackson.databind.ObjectMapper`. `jackson-2-bom.version` fija
Jackson 2 en 2.22.4; el BOM Jackson 3 gestionado por Boot permanece independiente.
`spring.http.converters.preferred-json-mapper=jackson2` selecciona el conversor
MVC y `spring.jackson2.time-zone` conserva la zona horaria configurada.

Este puente está deprecado y previsto para eliminación en Boot 4.3. Antes de
subir a esa línea debe migrarse a Jackson 3 mediante un cambio específico,
inventariando serializadores, anotaciones, errores, auditoría, exportación
firmada, fechas e importes. No se debe retirar el puente sólo para silenciar
una advertencia.

Los starters modulares de Web MVC, Flyway y pruebas declaran sus capacidades
explícitamente. Angus Mail se declara directamente porque el adaptador SMTP
usa su excepción de proveedor para clasificar respuestas; se mantiene la
versión del BOM y la política de correo NOOP/sin red predeterminada.

## Evidencia exigida

- Compilar todo el código y conservar todos los escenarios anteriores.
- Ejecutar `clean verify`, incluyendo PostgreSQL, migraciones, RLS, seguridad,
  observabilidad y los nuevos contratos de descubrimiento del guard de
  producción y conversor JSON efectivo por HTTP.
- Ejecutar el recorrido financiero real con PDF y aislamiento Beta, seguido
  de backup, restore y retorno entre imágenes históricas y actuales.
- Reconstruir las imágenes sin caché y vincular runtime, archivo exportado,
  SBOM y scan de vulnerabilidades. Los resultados previos a esta migración
  son históricos y no se heredan.

## Fuentes

- [Guía oficial de migración a Boot 4](https://github.com/spring-projects/spring-boot/wiki/Spring-Boot-4.0-Migration-Guide)
- [Compatibilidad oficial con Jackson 2](https://docs.spring.io/spring-boot/4.0/reference/features/json.html#features.json.jackson2)
- [BOM Spring Boot 4.0.9](https://repo.maven.apache.org/maven2/org/springframework/boot/spring-boot-dependencies/4.0.9/spring-boot-dependencies-4.0.9.pom)
