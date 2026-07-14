import { describe, expect, it } from "vitest";
import {
  adminRoutes,
  otherProtectedRoutes,
  protectedRoutes,
  routePermissions,
} from "../rutas/routes";
import { PERMISSIONS } from "./permissions";

const sources = import.meta.glob<string>("../**/*.{ts,tsx}", {
  eager: true,
  import: "default",
  query: "?raw",
});
const source = (relativePath: string): string => sources[`../${relativePath}`];
const isPermissionCatalog = (file: string): boolean => file === "./permissions.ts"
  || file.endsWith("/config/permissions.ts");

describe("contrato frontend RBAC", () => {
  it("declara una política para toda ruta protegida salvo unauthorized", () => {
    const expected = [...protectedRoutes, ...adminRoutes, ...otherProtectedRoutes]
      .map(({ path }) => path)
      .filter((path) => path !== "/unauthorized")
      .sort();

    expect(Object.keys(routePermissions).sort()).toEqual(expected);
  });

  it("mantiene exactamente 32 permisos canónicos únicos", () => {
    expect(Object.keys(PERMISSIONS)).toEqual([
      "APP_ACCESS",
      "USUARIOS_ADMIN",
      "ROLES_ADMIN",
      "AUDITORIA_SEGURIDAD_LEER",
      "MENSUALIDADES_GENERAR_MANUAL",
      "PAGOS_REGISTRAR",
      "PAGOS_ANULAR",
      "EGRESOS_ADMIN",
      "STOCK_ADMIN",
      "STOCK_VENDER",
      "CREDITOS_ADMIN",
      "CREDITOS_CONSUMIR",
      "TARIFAS_ADMIN",
      "TARIFAS_HISTORICAS",
      "CONDICIONES_ECONOMICAS_ADMIN",
      "ALUMNOS_LEER",
      "ALUMNOS_ADMIN",
      "INSCRIPCIONES_LEER",
      "INSCRIPCIONES_ADMIN",
      "DISCIPLINAS_LEER",
      "DISCIPLINAS_ADMIN",
      "PROFESORES_LEER",
      "PROFESORES_ADMIN",
      "ASISTENCIAS_LEER",
      "ASISTENCIAS_REGISTRAR",
      "PAGOS_LEER",
      "CAJA_LEER",
      "STOCK_LEER",
      "REPORTES_LEER",
      "REPORTES_EXPORTAR",
      "CONFIG_LEER",
      "CONFIG_ADMIN",
    ]);
    expect(new Set(Object.values(PERMISSIONS)).size).toBe(32);
    expect(Object.values(PERMISSIONS).every((permission) => permission.startsWith("PER" + "M_"))).toBe(true);
  });

  it.each([
    ["alumnos leer", "/alumnos", PERMISSIONS.ALUMNOS_LEER],
    ["alumnos administrar", "/alumnos/formulario", PERMISSIONS.ALUMNOS_ADMIN],
    ["inscripciones leer", "/inscripciones", PERMISSIONS.INSCRIPCIONES_LEER],
    ["inscripciones administrar", "/inscripciones/formulario", PERMISSIONS.INSCRIPCIONES_ADMIN],
    ["disciplinas leer", "/disciplinas", PERMISSIONS.DISCIPLINAS_LEER],
    ["disciplinas administrar", "/disciplinas/formulario", PERMISSIONS.DISCIPLINAS_ADMIN],
    ["profesores leer", "/profesores", PERMISSIONS.PROFESORES_LEER],
    ["profesores administrar", "/profesores/formulario", PERMISSIONS.PROFESORES_ADMIN],
    ["asistencias leer", "/asistencias/alumnos", PERMISSIONS.ASISTENCIAS_LEER],
    ["pagos leer", "/pagos", PERMISSIONS.PAGOS_LEER],
    ["pagos registrar", "/pagos/formulario", PERMISSIONS.PAGOS_REGISTRAR],
    ["caja", "/caja", PERMISSIONS.CAJA_LEER],
    ["egresos", "/egresos", PERMISSIONS.EGRESOS_ADMIN],
    ["stock leer", "/stocks", PERMISSIONS.STOCK_LEER],
    ["stock administrar", "/stocks/formulario", PERMISSIONS.STOCK_ADMIN],
    ["tarifas", "/disciplinas/:id/tarifas", PERMISSIONS.TARIFAS_ADMIN],
    ["condiciones", "/inscripciones/:id/condiciones-economicas", PERMISSIONS.CONDICIONES_ECONOMICAS_ADMIN],
    ["reportes", "/reportes", PERMISSIONS.REPORTES_LEER],
    ["usuarios", "/usuarios", PERMISSIONS.USUARIOS_ADMIN],
    ["roles", "/roles", PERMISSIONS.ROLES_ADMIN],
    ["configuración leer", "/conceptos", PERMISSIONS.CONFIG_LEER],
    ["configuración administrar", "/conceptos/formulario-concepto", PERMISSIONS.CONFIG_ADMIN],
  ] as const)("conjuga APP con %s", (_surface, route, functionalPermission) => {
    expect(routePermissions[route]).toEqual([PERMISSIONS.APP_ACCESS, functionalPermission]);
  });

  it.each([
    ["alumnos", "funcionalidades/alumnos/AlumnosPagina.tsx", "requiredPermission: PERMISSIONS.ALUMNOS_ADMIN"],
    ["inscripciones", "funcionalidades/inscripciones/InscripcionesPagina.tsx", "requiredPermission: PERMISSIONS.INSCRIPCIONES_ADMIN"],
    ["disciplinas", "funcionalidades/disciplinas/DisciplinasPagina.tsx", "requiredPermission: PERMISSIONS.DISCIPLINAS_ADMIN"],
    ["profesores", "funcionalidades/profesores/ProfesoresPagina.tsx", "requiredPermission: PERMISSIONS.PROFESORES_ADMIN"],
    ["asistencia diaria", "funcionalidades/asistencias-diarias/AsistenciaDiariaFormulario.tsx", "PERMISSIONS.ASISTENCIAS_REGISTRAR"],
    ["asistencia mensual", "funcionalidades/asistencias-mensuales/AsistenciaMensualDetalle.tsx", "PERMISSIONS.ASISTENCIAS_REGISTRAR"],
    ["anulación de pagos", "funcionalidades/pagos/PagosPagina.tsx", "requiredPermission: PERMISSIONS.PAGOS_ANULAR"],
    ["stock", "funcionalidades/stock/StocksPagina.tsx", "requiredPermission: PERMISSIONS.STOCK_ADMIN"],
    ["tarifa", "funcionalidades/disciplinas/TarifasDisciplinaPagina.tsx", "permission={PERMISSIONS.TARIFAS_ADMIN}"],
    ["tarifa histórica", "funcionalidades/disciplinas/TarifasDisciplinaPagina.tsx", "PERMISSIONS.TARIFAS_HISTORICAS"],
    ["condición histórica", "funcionalidades/inscripciones/CondicionesEconomicasPagina.tsx", "PERMISSIONS.TARIFAS_HISTORICAS"],
    ["exportación", "paginas/Reportes.tsx", "permission={PERMISSIONS.REPORTES_EXPORTAR}"],
    ["exportación por disciplina", "funcionalidades/reportes/AlumnosPorDIsciplina.tsx", "permission={PERMISSIONS.REPORTES_EXPORTAR}"],
    ["usuarios", "funcionalidades/usuarios/UsuariosPagina.tsx", "hasPermission(PERMISSIONS.USUARIOS_ADMIN)"],
    ["roles", "funcionalidades/roles/RolesPagina.tsx", "hasPermission(PERMISSIONS.ROLES_ADMIN)"],
    ["configuración", "funcionalidades/conceptos/ConceptosPagina.tsx", "requiredPermission: PERMISSIONS.CONFIG_ADMIN"],
  ] as const)("mantiene gate concreto para %s", (_surface, file, marker) => {
    expect(source(file)).toContain(marker);
  });

  it("no publica venta de stock sin superficie operativa probada", () => {
    const productSources = Object.entries(sources)
      .filter(([file]) => !file.includes(".test.") && !isPermissionCatalog(file));

    expect(productSources.some(([, content]) => content.includes("PERMISSIONS.STOCK_VENDER"))).toBe(false);
  });

  it("centraliza literales, y no deja STOMP ni Observaciones de profesores activas", () => {
    const product = Object.entries(sources).filter(([file]) => !file.includes(".test."));
    const forbiddenPermissionLiteral = "PER" + "M_";

    expect(product
      .filter(([file]) => !isPermissionCatalog(file))
      .filter(([, content]) => content.includes(forbiddenPermissionLiteral))
      .map(([file]) => file))
      .toEqual([]);
    expect(product.some(([file, content]) => /stomp|useNotificacionesWebSocket|observacionProfesorApi|ConsultaObservacionesProfesores/i.test(
      `${file}\n${content}`,
    ))).toBe(false);
  });
});
