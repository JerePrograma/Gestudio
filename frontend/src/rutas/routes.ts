import { lazy } from "react";
import { PERMISSIONS, type PermissionCode } from "../config/permissions";

export const prefetch = { dashboard: () => import("../paginas/Dashboard") };

const Login = lazy(() => import("../paginas/Login"));
const Unauthorized = lazy(() => import("../paginas/Unauthorized"));
const Dashboard = lazy(() => import("../paginas/Dashboard"));
const Reportes = lazy(() => import("../paginas/Reportes"));

export const publicRoutes = [
  { path: "/login", Component: Login },
] as const;

export const protectedRoutes = [
  { path: "/", Component: Dashboard },
  { path: "/reportes", Component: Reportes },
  { path: "/unauthorized", Component: Unauthorized },
] as const;

const UsuariosPagina = lazy(() => import("../funcionalidades/usuarios/UsuariosPagina"));
const UsuariosFormulario = lazy(() => import("../funcionalidades/usuarios/UsuariosFormulario"));
const RolesPagina = lazy(() => import("../funcionalidades/roles/RolesPagina"));
const RolesFormulario = lazy(() => import("../funcionalidades/roles/RolesFormulario"));

export const adminRoutes = [
  { path: "/usuarios", Component: UsuariosPagina },
  { path: "/usuarios/formulario", Component: UsuariosFormulario },
  { path: "/roles", Component: RolesPagina },
  { path: "/roles/formulario", Component: RolesFormulario },
] as const;

const ProfesoresPagina = lazy(() => import("../funcionalidades/profesores/ProfesoresPagina"));
const ProfesoresFormulario = lazy(() => import("../funcionalidades/profesores/ProfesoresFormulario"));
const DisciplinasPagina = lazy(() => import("../funcionalidades/disciplinas/DisciplinasPagina"));
const DisciplinasFormulario = lazy(() => import("../funcionalidades/disciplinas/DisciplinasFormulario"));
const TarifasDisciplinaPagina = lazy(() => import("../funcionalidades/disciplinas/TarifasDisciplinaPagina"));
const AlumnosPagina = lazy(() => import("../funcionalidades/alumnos/AlumnosPagina"));
const AlumnosFormulario = lazy(() => import("../funcionalidades/alumnos/AlumnosFormulario"));
const SalonesPagina = lazy(() => import("../funcionalidades/salones/SalonesPagina"));
const SalonesFormulario = lazy(() => import("../funcionalidades/salones/SalonesFormulario"));
const BonificacionesPagina = lazy(() => import("../funcionalidades/bonificaciones/BonificacionesPagina"));
const BonificacionesFormulario = lazy(() => import("../funcionalidades/bonificaciones/BonificacionesFormulario"));
const InscripcionesPagina = lazy(() => import("../funcionalidades/inscripciones/InscripcionesPagina"));
const InscripcionesFormulario = lazy(() => import("../funcionalidades/inscripciones/InscripcionesFormulario"));
const CondicionesEconomicasPagina = lazy(() => import("../funcionalidades/inscripciones/CondicionesEconomicasPagina"));
const AsistenciaDiariaFormulario = lazy(() => import("../funcionalidades/asistencias-diarias/AsistenciaDiariaFormulario"));
const AsistenciaMensualDetalle = lazy(() => import("../funcionalidades/asistencias-mensuales/AsistenciaMensualDetalle"));
const PagosPagina = lazy(() => import("../funcionalidades/pagos/PagosPagina"));
const PagosFormulario = lazy(() => import("../funcionalidades/pagos/PagosFormulario"));
const CajaPagina = lazy(() => import("../funcionalidades/caja/CajaPagina"));
const EgresosPagina = lazy(() => import("../funcionalidades/caja/EgresosPagina"));
const StocksPagina = lazy(() => import("../funcionalidades/stock/StocksPagina"));
const StocksFormulario = lazy(() => import("../funcionalidades/stock/StocksFormulario"));
const ConceptosPagina = lazy(() => import("../funcionalidades/conceptos/ConceptosPagina"));
const ConceptosFormulario = lazy(() => import("../funcionalidades/conceptos/ConceptosFormulario"));
const MetodosPagoPagina = lazy(() => import("../funcionalidades/metodos-pago/MetodosPagoPagina"));
const MetodosPagoFormulario = lazy(() => import("../funcionalidades/metodos-pago/MetodosPagoFormulario"));
const RecargosPagina = lazy(() => import("../funcionalidades/recargos/RecargosPagina"));
const RecargosFormulario = lazy(() => import("../funcionalidades/recargos/RecargosFormulario"));
const AlumnosPorDisciplina = lazy(() => import("../funcionalidades/reportes/AlumnosPorDIsciplina"));
const SubConceptosPagina = lazy(() => import("../funcionalidades/subconceptos/SubConceptosPagina"));
const SubConceptosFormulario = lazy(() => import("../funcionalidades/subconceptos/SubConceptosFormulario"));

export const otherProtectedRoutes = [
  { path: "/profesores", Component: ProfesoresPagina },
  { path: "/profesores/formulario", Component: ProfesoresFormulario },
  { path: "/disciplinas", Component: DisciplinasPagina },
  { path: "/disciplinas/formulario", Component: DisciplinasFormulario },
  { path: "/disciplinas/:id/tarifas", Component: TarifasDisciplinaPagina },
  { path: "/alumnos", Component: AlumnosPagina },
  { path: "/alumnos/formulario", Component: AlumnosFormulario },
  { path: "/salones", Component: SalonesPagina },
  { path: "/salones/formulario", Component: SalonesFormulario },
  { path: "/bonificaciones", Component: BonificacionesPagina },
  { path: "/bonificaciones/formulario", Component: BonificacionesFormulario },
  { path: "/inscripciones", Component: InscripcionesPagina },
  { path: "/inscripciones/formulario", Component: InscripcionesFormulario },
  { path: "/inscripciones/:id/condiciones-economicas", Component: CondicionesEconomicasPagina },
  { path: "/asistencias/alumnos", Component: AsistenciaDiariaFormulario },
  { path: "/asistencias-mensuales", Component: AsistenciaMensualDetalle },
  { path: "/pagos", Component: PagosPagina },
  { path: "/pagos/formulario", Component: PagosFormulario },
  { path: "/caja", Component: CajaPagina },
  { path: "/egresos", Component: EgresosPagina },
  { path: "/stocks", Component: StocksPagina },
  { path: "/stocks/formulario", Component: StocksFormulario },
  { path: "/conceptos", Component: ConceptosPagina },
  { path: "/conceptos/formulario-concepto", Component: ConceptosFormulario },
  { path: "/metodos-pago", Component: MetodosPagoPagina },
  { path: "/metodos-pago/formulario", Component: MetodosPagoFormulario },
  { path: "/recargos", Component: RecargosPagina },
  { path: "/recargos/formulario", Component: RecargosFormulario },
  { path: "/alumnos-por-disciplina", Component: AlumnosPorDisciplina },
  { path: "/subconceptos", Component: SubConceptosPagina },
  { path: "/subconceptos/formulario", Component: SubConceptosFormulario },
] as const;

export type ProtectedRoutePath =
  | (typeof protectedRoutes)[number]["path"]
  | (typeof adminRoutes)[number]["path"]
  | (typeof otherProtectedRoutes)[number]["path"];

type PermissionedRoutePath = Exclude<ProtectedRoutePath, "/unauthorized">;

export const routePermissions = {
  "/": [PERMISSIONS.APP_ACCESS],
  "/reportes": [PERMISSIONS.APP_ACCESS, PERMISSIONS.REPORTES_LEER],

  "/usuarios": [PERMISSIONS.APP_ACCESS, PERMISSIONS.USUARIOS_ADMIN],
  "/usuarios/formulario": [PERMISSIONS.APP_ACCESS, PERMISSIONS.USUARIOS_ADMIN],
  "/roles": [PERMISSIONS.APP_ACCESS, PERMISSIONS.ROLES_ADMIN],
  "/roles/formulario": [PERMISSIONS.APP_ACCESS, PERMISSIONS.ROLES_ADMIN],

  "/profesores": [PERMISSIONS.APP_ACCESS, PERMISSIONS.PROFESORES_LEER],
  "/profesores/formulario": [PERMISSIONS.APP_ACCESS, PERMISSIONS.PROFESORES_ADMIN],
  "/disciplinas": [PERMISSIONS.APP_ACCESS, PERMISSIONS.DISCIPLINAS_LEER],
  "/disciplinas/formulario": [PERMISSIONS.APP_ACCESS, PERMISSIONS.DISCIPLINAS_ADMIN],
  "/disciplinas/:id/tarifas": [PERMISSIONS.APP_ACCESS, PERMISSIONS.TARIFAS_ADMIN],
  "/alumnos": [PERMISSIONS.APP_ACCESS, PERMISSIONS.ALUMNOS_LEER],
  "/alumnos/formulario": [PERMISSIONS.APP_ACCESS, PERMISSIONS.ALUMNOS_ADMIN],
  "/salones": [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_LEER],
  "/salones/formulario": [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_ADMIN],
  "/bonificaciones": [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_LEER],
  "/bonificaciones/formulario": [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_ADMIN],
  "/inscripciones": [PERMISSIONS.APP_ACCESS, PERMISSIONS.INSCRIPCIONES_LEER],
  "/inscripciones/formulario": [PERMISSIONS.APP_ACCESS, PERMISSIONS.INSCRIPCIONES_ADMIN],
  "/inscripciones/:id/condiciones-economicas": [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONDICIONES_ECONOMICAS_ADMIN],
  "/asistencias/alumnos": [PERMISSIONS.APP_ACCESS, PERMISSIONS.ASISTENCIAS_LEER],
  "/asistencias-mensuales": [PERMISSIONS.APP_ACCESS, PERMISSIONS.ASISTENCIAS_LEER],

  "/pagos": [PERMISSIONS.APP_ACCESS, PERMISSIONS.PAGOS_LEER],
  "/pagos/formulario": [PERMISSIONS.APP_ACCESS, PERMISSIONS.PAGOS_REGISTRAR],
  "/caja": [PERMISSIONS.APP_ACCESS, PERMISSIONS.CAJA_LEER],
  "/egresos": [PERMISSIONS.APP_ACCESS, PERMISSIONS.EGRESOS_ADMIN],
  "/stocks": [PERMISSIONS.APP_ACCESS, PERMISSIONS.STOCK_LEER],
  "/stocks/formulario": [PERMISSIONS.APP_ACCESS, PERMISSIONS.STOCK_ADMIN],
  "/conceptos": [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_LEER],
  "/conceptos/formulario-concepto": [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_ADMIN],
  "/metodos-pago": [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_LEER],
  "/metodos-pago/formulario": [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_ADMIN],
  "/recargos": [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_LEER],
  "/recargos/formulario": [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_ADMIN],
  "/alumnos-por-disciplina": [PERMISSIONS.APP_ACCESS, PERMISSIONS.REPORTES_LEER, PERMISSIONS.DISCIPLINAS_LEER],
  "/subconceptos": [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_LEER],
  "/subconceptos/formulario": [PERMISSIONS.APP_ACCESS, PERMISSIONS.CONFIG_ADMIN],
} satisfies Record<PermissionedRoutePath, readonly PermissionCode[]>;

export const permissionsForRoute = (path: ProtectedRoutePath): readonly PermissionCode[] | undefined =>
  path === "/unauthorized" ? undefined : routePermissions[path];
