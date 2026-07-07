export const queryKeys = {
  all: {
    alumnos: ["alumnos"] as const,
    inscripciones: ["inscripciones"] as const,
    disciplinas: ["disciplinas"] as const,
    stocks: ["stocks"] as const,
    usuarios: ["usuarios"] as const,
    roles: ["roles"] as const,
  },
  alumnos: (page: number, size: number, filtro: string) =>
    ["alumnos", page, size, filtro.trim(), "id,asc"] as const,
  cargosPendientes: (alumnoId: number, page: number, size: number) =>
    ["cargos", "pendientes", alumnoId, page, size, "fechaVencimiento,asc;id,asc"] as const,
  caja: (desde: string, hasta: string, page: number, size: number) =>
    ["caja", desde, hasta, page, size, "fecha,asc;id,asc"] as const,
  egresos: (page: number, size: number) => ["egresos", page, size, "fecha,desc;id,desc"] as const,
  metodosPago: ["metodos-pago"] as const,
  pagos: (alumnoId: number, page: number, size: number) =>
    ["pagos", alumnoId, page, size, "fecha,desc;id,desc"] as const,
  inscripciones: (page: number, size: number, filtro: string) =>
    ["inscripciones", page, size, filtro.trim(), "id,desc"] as const,
  stocks: (page: number, size: number) => ["stocks", page, size, "nombre,asc;id,asc"] as const,
  alumno: (id: number) => ["alumnos", "detalle", id] as const,
  inscripcion: (id: number) => ["inscripciones", "detalle", id] as const,
  disciplinas: ["disciplinas", "listado"] as const,
  disciplina: (id: number) => ["disciplinas", "detalle", id] as const,
  bonificaciones: ["bonificaciones", "listado"] as const,
  stock: (id: number) => ["stocks", "detalle", id] as const,
  usuarios: ["usuarios", "listado"] as const,
  usuario: (id: number) => ["usuarios", "detalle", id] as const,
  roles: ["roles", "listado"] as const,
};
