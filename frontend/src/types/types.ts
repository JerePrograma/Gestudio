// ==========================================
// UTILITY TYPES & ENUMS
// ==========================================
export type LocalDate = string;
export type LocalTime = string;

export enum DiaSemana {
  LUNES = "LUNES",
  MARTES = "MARTES",
  MIERCOLES = "MIERCOLES",
  JUEVES = "JUEVES",
  VIERNES = "VIERNES",
  SABADO = "SABADO",
  DOMINGO = "DOMINGO",
}

export enum EstadoInscripcion {
  ACTIVA = "ACTIVA",
  INACTIVA = "INACTIVA",
  FINALIZADA = "FINALIZADA",
}

// types.ts
export interface Page<T> {
  content: T[];
  totalElements: number;
  totalPages: number;
  size: number;
  number: number;
  first: boolean;
  last: boolean;
}

// ==========================================
// ALUMNO
// ==========================================
export interface AlumnoResponse {
  id: number;
  nombre: string;
  apellido: string;
  fechaNacimiento: string; // formato ISO (ej. "2023-08-30")
  fechaIncorporacion: string; // formato ISO
  edad: number;
  celular1: string;
  celular2: string;
  email: string;
  documento: string;
  fechaDeBaja: string | null; // puede ser null si no se dio de baja
  nombrePadres: string;
  autorizadoParaSalirSolo: boolean;
  activo: boolean;
  otrasNotas: string;
  inscripciones: InscripcionResponse[]; // Asegúrate de que InscripcionResponse esté definido según tu DTO
}

export interface AlumnoRegistroRequest {
  id?: number;
  nombre: string;
  apellido: string;
  fechaNacimiento: string; // en formato ISO, ej. "2023-08-30"
  fechaIncorporacion: string; // en formato ISO
  celular1?: string;
  celular2?: string;
  email?: string;
  documento?: string;
  fechaDeBaja?: string | null;
  nombrePadres?: string;
  autorizadoParaSalirSolo?: boolean;
  activo: boolean;
  otrasNotas?: string;
  inscripciones?: InscripcionRegistroRequest[];
}

export type AlumnoRegistro = AlumnoRegistroRequest;

// ==========================================
// PROFESOR
// ==========================================
export interface ProfesorRegistroRequest {
  nombre: string;
  apellido: string;
  fechaNacimiento?: LocalDate;
  telefono?: string;
}

export interface ProfesorModificacionRequest {
  nombre: string;
  apellido: string;
  fechaNacimiento?: LocalDate;
  telefono?: string;
  activo: boolean;
}

export interface ProfesorDetalleResponse {
  id: number;
  nombre: string;
  apellido: string;
  fechaNacimiento: string;
  edad: number;
  telefono?: string;
  activo: boolean;
  disciplinas: DisciplinaListadoResponse[];
}

export interface ProfesorListadoResponse {
  id: number;
  nombre: string;
  apellido: string;
  activo: boolean;
}

// ==========================================
// DISCIPLINA
// ==========================================
export interface DisciplinaHorarioRequest {
  id?: number;
  diaSemana: DiaSemana;
  horarioInicio: LocalTime;
  duracion: number;
}

export interface DisciplinaRegistroRequest {
  id?: number;
  nombre: string;
  salonId: number;
  profesorId: number;
  valorCuota: string;
  matricula: string;
  claseSuelta?: string;
  clasePrueba?: string;
  horarios: DisciplinaHorarioRequest[];
}

export interface DisciplinaModificacionRequest {
  nombre: string;
  salonId: number;
  profesorId: number;
  valorCuota: string;
  matricula: string;
  claseSuelta?: string;
  clasePrueba?: string;
  activo: boolean;
  horarios: DisciplinaHorarioRequest[];
}

export interface DisciplinaHorarioResponse {
  id: number;
  diaSemana: DiaSemana;
  horarioInicio: string;
  duracion: number;
}

export interface DisciplinaResponse {
  id: number;
  nombre: string;
  salon: string;
  salonId: number; // Agregado
  valorCuota: string;
  matricula: string;
  profesorNombre: string;
  profesorApellido: string;
  profesorId: number | null;
  inscritos: number;
  activo: boolean;
  claseSuelta?: string;
  clasePrueba?: string;
  horarios: DisciplinaHorarioResponse[];
}

export interface DisciplinaListadoResponse extends DisciplinaResponse {
  horarioInicio?: string;
}

export type DisciplinaDetalleResponse = DisciplinaResponse;

// ==========================================
// ASISTENCIA
// ==========================================
// types/types.ts
export enum EstadoAsistencia {
  PRESENTE = "PRESENTE",
  AUSENTE = "AUSENTE",
}

// Para crear o actualizar una asistencia diaria (igual que antes)
export interface AsistenciaDiariaRegistroRequest {
  id?: number; // Opcional en creación
  fecha: string; // Formato ISO (YYYY-MM-DD)
  estado: EstadoAsistencia;
  asistenciaAlumnoMensualId: number;
  observacion?: string;
}

// Response de una asistencia diaria, ahora con un objeto "alumno"
export interface AsistenciaDiariaResponse {
  id: number;
  fecha: string;
  estado: EstadoAsistencia;
  asistenciaAlumnoMensualId: number;
  alumno: AlumnoResponse;
  asistenciaMensualId: number;
  disciplinaId: number;
  observacion?: string;
}

// Para crear una asistencia mensual (planilla)
export interface AsistenciaMensualRegistroRequest {
  mes: number;
  anio: number;
  disciplinaId: number;
  asistenciasDiarias?: AsistenciaDiariaRegistroRequest[];
}

// Para modificar la asistencia mensual (actualizando observaciones y, opcionalmente, asistencias diarias)
export interface AsistenciaMensualModificacionRequest {
  asistenciasAlumnoMensual: {
    id: number; // id del registro AsistenciaAlumnoMensual
    observacion: string;
    asistenciasDiarias?: AsistenciaDiariaRegistroRequest[];
  }[];
}

// Respuesta de cada registro de asistencia mensual de un alumno,
// ahora con el alumno anidado en lugar de campos sueltos
export interface AsistenciaAlumnoMensualDetalleResponse {
  id: number;
  asistenciaMensualId: number;
  inscripcionId: number;
  alumno: AlumnoResponse;
  observacion: string;
  asistenciasDiarias: AsistenciaDiariaResponse[];
}

// Respuesta detallada de la asistencia mensual (planilla)
// Incluye la disciplina como objeto anidado y el listado de registros de alumno
export interface AsistenciaMensualDetalleResponse {
  id: number;
  mes: number;
  anio: number;
  disciplina: DisciplinaResponse;
  profesor: string;
  alumnos: AsistenciaAlumnoMensualDetalleResponse[];
}

// Respuesta para listado de planillas mensuales
export interface AsistenciaMensualListadoResponse {
  id: number;
  mes: number;
  anio: number;
  disciplina: DisciplinaResponse;
  profesor: string;
  cantidadAlumnos: number;
}

export interface AsistenciasActivasResponse {
  totalInscripcionesProcesadas: number;
  totalPlanillasCreadas: number;
  totalAsistenciasDiariasGeneradas: number;
  detalles: string[];
}

export type PageResponse<T> = Page<T>;

// ==========================================
// INSCRIPCIÓN
// ==========================================

// Tipo para la solicitud de inscripción
export interface InscripcionRegistroRequest {
  id?: number | null;
  alumnoId: number;
  disciplinaId: number;
  bonificacionId?: number | null;
  fechaInscripcion: string;
  costoParticular?: string;
}
// Tipo para la respuesta de inscripción
export interface InscripcionResponse {
  id: number;
  alumnoId: number;
  alumno: string;
  disciplinaId: number;
  disciplina: string;
  bonificacionId?: number;
  fechaInscripcion: string;
  fechaBaja?: string;
  estado: "ACTIVA" | "BAJA" | string;
  costoParticular?: string;
}

export interface BonificacionRegistroRequest {
  descripcion: string;
  porcentajeDescuento?: string;
  observaciones?: string;
  valorFijo?: string;
}

export interface BonificacionModificacionRequest {
  descripcion: string;
  porcentajeDescuento?: string;
  activo: boolean;
  observaciones?: string;
  valorFijo?: string;
}

export interface BonificacionResponse {
  id: number;
  descripcion: string;
  porcentajeDescuento: string;
  activo: boolean;
  observaciones?: string;
  valorFijo?: string;
}

// ==========================================
// RECARGOS - Tipos de datos
// ==========================================

/** Request para registrar un nuevo recargo */
export interface RecargoRegistroRequest {
  descripcion: string;
  porcentaje: string;
  valorFijo?: string;
  diaDelMesAplicacion: number; // ✅ Cambiado de fechaAplicacion a diaDelMesAplicacion
}

/** Request para actualizar un recargo */
export type RecargoModificacionRequest = Partial<RecargoRegistroRequest>;

/** Respuesta del backend al obtener un recargo */
export interface RecargoResponse {
  id: number;
  descripcion: string;
  porcentaje: string;
  valorFijo?: string;
  diaDelMesAplicacion: number; // ✅ Actualizado
}

// ==========================================
// STOCK
// ==========================================
export interface StockRegistroRequest {
  nombre: string;
  precio: string;
  stock: number;
  requiereControlDeStock: boolean;
  codigoBarras?: string;
  activo?: boolean;
  idempotencyKey: string;
}

export interface StockModificacionRequest extends StockRegistroRequest {
  activo: boolean;
}

export interface StockResponse {
  id: number;
  nombre: string;
  precio: string;
  stock: number;
  requiereControlDeStock: boolean;
  codigoBarras?: string;
  activo: boolean;
}

// ==========================================
// USUARIO Y ROLES
// ==========================================
// types.ts

export interface UsuarioRegistroRequest {
  nombreUsuario: string;
  contrasena: string;
  roles: string[];
}

export interface UsuarioModificacionRequest {
  nombreUsuario: string;
  // La contraseña se hace opcional, para permitir actualizarla o dejarla sin cambios
  contrasena?: string;
  roles: string[];
  activo: boolean;
}

export interface UsuarioResponse {
  id: number;
  nombreUsuario: string;
  roles: string[];
  permisos: string[];
  activo: boolean;
}

export interface RolRegistroRequest {
  codigo: string;
  nombre: string;
  descripcionFuncional?: string;
}

export interface RolModificacionRequest {
  nombre: string;
  descripcionFuncional?: string;
  activo: boolean;
}

export interface RolResponse {
  id: number;
  codigo: string;
  nombre: string;
  descripcionFuncional?: string;
  activo: boolean;
  sistema: boolean;
  editable: boolean;
  cantidadPermisos: number;
}

export interface PermisoResponse {
  id: number;
  codigo: string;
  descripcion: string;
  modulo: string;
  activo: boolean;
  sistema: boolean;
}

export interface RolDetalleResponse extends Omit<RolResponse, "cantidadPermisos"> {
  permisos: PermisoResponse[];
}

// src/types/conceptosTypes.ts
export interface ConceptoRegistroRequest {
  descripcion: string;
  precio: string;
  subConcepto: SubConceptoResponse;
  activo?: boolean;
}

export interface ConceptoResponse {
  version: number;
  id: number;
  descripcion: string;
  precio: string;
  subConcepto: SubConceptoResponse;
  activo?: boolean;
}

export interface SubConceptoRegistroRequest {
  descripcion: string;
}

export interface SubConceptoModificacionRequest {
  descripcion: string;
}

export interface SubConceptoResponse {
  id: number;
  descripcion: string;
}

// --- Metodos de Pago ---
// Interfaces actualizadas

export interface MetodoPagoRegistroRequest {
  descripcion: string;
  recargo: string;
}

export interface MetodoPagoModificacionRequest {
  descripcion: string;
  activo: boolean;
  recargo: string;
}

export interface MetodoPagoResponse {
  id: number;
  descripcion: string;
  activo: boolean;
  recargo: string;
}

export interface SalonRegistroRequest {
  nombre: string;
  descripcion: string;
}

export interface SalonModificacionRequest {
  nombre: string;
  descripcion: string;
}

export interface SalonResponse {
  id: number;
  nombre: string;
  descripcion: string;
}

export interface PagoRegistroRequest {
  alumnoId: number;
  metodoPagoId: number;
  montoRecibido: string;
  idempotencyKey: string;
  observaciones?: string;
  aplicaciones: AplicacionPagoRequest[];
  generarCredito: boolean;
}

export interface AplicacionPagoRequest {
  cargoId: number;
  importe: string;
}

export interface AplicacionPagoResponse {
  id: number;
  cargoId: number;
  importeAplicado: string;
  estado: string;
  saldoCargo: string;
}

export interface PagoResponse {
  id: number;
  alumnoId: number;
  metodoPagoId: number;
  usuarioId: number;
  fecha: string;
  montoRecibido: string;
  estado: string;
  idempotencyKey: string;
  observaciones?: string;
  creditoGenerado: string;
  aplicaciones: AplicacionPagoResponse[];
}

export interface PagoResumenResponse {
  id: number;
  fecha: string;
  montoRecibido: string;
  estado: string;
}

export interface PagoAnulacionRequest {
  idempotencyKey: string;
  motivo: string;
}

export interface CargoResponse {
  id: number;
  alumnoId: number;
  tipo: string;
  descripcion: string;
  importeOriginal: string;
  importeAplicado: string;
  saldo: string;
  fechaEmision: string;
  fechaVencimiento: string;
  estado: string;
}

export interface MensualidadRegistroRequest {
  inscripcionId: number;
  anio: number;
  mes: number;
}

export interface MensualidadResponse {
  id: number;
  inscripcionId: number;
  anio: number;
  mes: number;
  descripcion: string;
  estado: string;
  cargoId: number;
  importe: string;
}
export interface EgresoRegistroRequest {
  fecha?: string;
  monto: string;
  observaciones?: string;
  metodoPagoId: number;
  idempotencyKey: string;
}

export interface EgresoResponse {
  id: number;
  fecha: string;
  monto: string;
  observaciones?: string;
  metodoPagoId: number;
  usuarioId: number;
  estado: string;
  idempotencyKey: string;
}

export interface MovimientoCajaResponse {
  id: number;
  tipo: string;
  fecha: string;
  importe: string;
  metodoPagoId?: number;
  pagoId?: number;
  egresoId?: number;
  motivo?: string;
  createdAt: string;
}

export interface ResumenCajaResponse {
  desde: string;
  hasta: string;
  ingresos: string;
  egresos: string;
  ajustesIngreso: string;
  ajustesEgreso: string;
  reversosIngreso: string;
  reversosEgreso: string;
  totalIngresos: string;
  totalEgresos: string;
  saldo: string;
  movimientos: Page<MovimientoCajaResponse>;
}

export type ObservacionProfesorResponse = {
  id: number;
  profesorId: number;
  fecha: string; // ISO date string
  observacion: string;
};

export type ObservacionProfesorRequest = {
  profesorId: number;
  fecha: string; // ISO date string
  observacion: string;
};
