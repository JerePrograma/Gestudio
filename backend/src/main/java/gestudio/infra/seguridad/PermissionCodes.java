package gestudio.infra.seguridad;

import java.util.Set;

public final class PermissionCodes {
    public static final String PERM_APP_ACCESO = "PERM_APP_ACCESO";
    public static final String PERM_USUARIOS_ADMIN = "PERM_USUARIOS_ADMIN";
    public static final String PERM_ROLES_ADMIN = "PERM_ROLES_ADMIN";
    public static final String PERM_AUDITORIA_SEGURIDAD_LEER = "PERM_AUDITORIA_SEGURIDAD_LEER";
    public static final String PERM_MENSUALIDADES_GENERAR_MANUAL = "PERM_MENSUALIDADES_GENERAR_MANUAL";
    public static final String PERM_PAGOS_REGISTRAR = "PERM_PAGOS_REGISTRAR";
    public static final String PERM_PAGOS_ANULAR = "PERM_PAGOS_ANULAR";
    public static final String PERM_EGRESOS_ADMIN = "PERM_EGRESOS_ADMIN";
    public static final String PERM_STOCK_ADMIN = "PERM_STOCK_ADMIN";
    public static final String PERM_STOCK_VENDER = "PERM_STOCK_VENDER";
    public static final String PERM_CREDITOS_ADMIN = "PERM_CREDITOS_ADMIN";
    public static final String PERM_CREDITOS_CONSUMIR = "PERM_CREDITOS_CONSUMIR";
    public static final String PERM_TARIFAS_ADMIN = "PERM_TARIFAS_ADMIN";
    public static final String PERM_TARIFAS_HISTORICAS = "PERM_TARIFAS_HISTORICAS";
    public static final String PERM_CONDICIONES_ECONOMICAS_ADMIN = "PERM_CONDICIONES_ECONOMICAS_ADMIN";
    public static final String PERM_ALUMNOS_LEER = "PERM_ALUMNOS_LEER";
    public static final String PERM_ALUMNOS_ADMIN = "PERM_ALUMNOS_ADMIN";
    public static final String PERM_INSCRIPCIONES_LEER = "PERM_INSCRIPCIONES_LEER";
    public static final String PERM_INSCRIPCIONES_ADMIN = "PERM_INSCRIPCIONES_ADMIN";
    public static final String PERM_DISCIPLINAS_LEER = "PERM_DISCIPLINAS_LEER";
    public static final String PERM_DISCIPLINAS_ADMIN = "PERM_DISCIPLINAS_ADMIN";
    public static final String PERM_PROFESORES_LEER = "PERM_PROFESORES_LEER";
    public static final String PERM_PROFESORES_ADMIN = "PERM_PROFESORES_ADMIN";
    public static final String PERM_ASISTENCIAS_LEER = "PERM_ASISTENCIAS_LEER";
    public static final String PERM_ASISTENCIAS_REGISTRAR = "PERM_ASISTENCIAS_REGISTRAR";
    public static final String PERM_PAGOS_LEER = "PERM_PAGOS_LEER";
    public static final String PERM_CAJA_LEER = "PERM_CAJA_LEER";
    public static final String PERM_STOCK_LEER = "PERM_STOCK_LEER";
    public static final String PERM_REPORTES_LEER = "PERM_REPORTES_LEER";
    public static final String PERM_REPORTES_EXPORTAR = "PERM_REPORTES_EXPORTAR";
    public static final String PERM_CONFIG_LEER = "PERM_CONFIG_LEER";
    public static final String PERM_CONFIG_ADMIN = "PERM_CONFIG_ADMIN";

    public static final Set<String> ALL = Set.of(
            PERM_APP_ACCESO,
            PERM_USUARIOS_ADMIN,
            PERM_ROLES_ADMIN,
            PERM_AUDITORIA_SEGURIDAD_LEER,
            PERM_MENSUALIDADES_GENERAR_MANUAL,
            PERM_PAGOS_REGISTRAR,
            PERM_PAGOS_ANULAR,
            PERM_EGRESOS_ADMIN,
            PERM_STOCK_ADMIN,
            PERM_STOCK_VENDER,
            PERM_CREDITOS_ADMIN,
            PERM_CREDITOS_CONSUMIR,
            PERM_TARIFAS_ADMIN,
            PERM_TARIFAS_HISTORICAS,
            PERM_CONDICIONES_ECONOMICAS_ADMIN,
            PERM_ALUMNOS_LEER,
            PERM_ALUMNOS_ADMIN,
            PERM_INSCRIPCIONES_LEER,
            PERM_INSCRIPCIONES_ADMIN,
            PERM_DISCIPLINAS_LEER,
            PERM_DISCIPLINAS_ADMIN,
            PERM_PROFESORES_LEER,
            PERM_PROFESORES_ADMIN,
            PERM_ASISTENCIAS_LEER,
            PERM_ASISTENCIAS_REGISTRAR,
            PERM_PAGOS_LEER,
            PERM_CAJA_LEER,
            PERM_STOCK_LEER,
            PERM_REPORTES_LEER,
            PERM_REPORTES_EXPORTAR,
            PERM_CONFIG_LEER,
            PERM_CONFIG_ADMIN
    );

    private PermissionCodes() {
    }
}
