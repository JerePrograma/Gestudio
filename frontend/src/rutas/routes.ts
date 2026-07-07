import { lazy } from "react";

export const prefetch = { dashboard: () => import("../paginas/Dashboard") };

const Login = lazy(() => import("../paginas/Login"));
const Unauthorized = lazy(() => import("../paginas/Unauthorized"));
const Dashboard = lazy(() => import("../paginas/Dashboard"));
const Reportes = lazy(() => import("../paginas/Reportes"));

export const publicRoutes = [
  { path: "/login", Component: Login },
];
export const protectedRoutes = [
  { path: "/", Component: Dashboard },
  { path: "/reportes", Component: Reportes },
  { path: "/unauthorized", Component: Unauthorized },
];

const UsuariosPagina = lazy(() => import("../funcionalidades/usuarios/UsuariosPagina"));
const UsuariosFormulario = lazy(() => import("../funcionalidades/usuarios/UsuariosFormulario"));
const RolesPagina = lazy(() => import("../funcionalidades/roles/RolesPagina"));
const RolesFormulario = lazy(() => import("../funcionalidades/roles/RolesFormulario"));
export const adminRoutes = [
  { path: "/usuarios", Component: UsuariosPagina },
  { path: "/usuarios/formulario", Component: UsuariosFormulario },
  { path: "/roles", Component: RolesPagina },
  { path: "/roles/formulario", Component: RolesFormulario },
];

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
];
