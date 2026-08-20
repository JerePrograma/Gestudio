Feature: Provisionamiento seguro de tenants desde el backoffice

  Scenario: SUPERADMIN crea una escuela
    Given un SUPERADMIN de plataforma autenticado y autorizado
    And no existe el tenant Escuela Danza Marcos Paz
    When crea Escuela Danza Marcos Paz con administradora inicial
    Then existe exactamente un tenant activo para la escuela
    And no se crean datos demo
    And se registra auditoría de creación

  Scenario: Tenant admin intenta crear otra organización
    Given un administrador tenant sin capacidad de plataforma
    When intenta crear Tenant Beta desde el endpoint de plataforma
    Then Tenant Beta no existe

  Scenario: La administradora inicial puede autenticarse sólo en su tenant
    Given existe Escuela Danza Marcos Paz con administradora pendiente
    When la administradora activa su identidad e inicia sesión
    Then existe una única membership administradora
    And sólo administra su tenant

  Scenario: Manipulación cross-tenant
    Given existen Tenant Alpha y Tenant Beta
    When se combina la membership de Alpha con el ID de Beta
    Then la operación cross-tenant es denegada sin filtrar datos de Beta

  Scenario: Tenant suspendido
    Given un tenant activo con una administradora habilitada
    When SUPERADMIN suspende el tenant
    Then la autenticación tenant es rechazada y los datos permanecen intactos

  Scenario: Provisioning concurrente
    Given dos requests equivalentes para una misma escuela
    When ambos provisionamientos se ejecutan concurrentemente
    Then existe una única entidad final consistente
