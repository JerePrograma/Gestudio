import api from "./axiosConfig";
import type {
  DisciplinaRegistroRequest,
  DisciplinaModificacionRequest,
  DisciplinaDetalleResponse,
  DisciplinaListadoResponse,
  AlumnoResponse,
  ProfesorListadoResponse,
} from "../types/types";

const disciplinasApi = {
  registrarDisciplina: async (
    disciplina: DisciplinaRegistroRequest
  ): Promise<DisciplinaDetalleResponse> => {
    const response = await api.post<DisciplinaDetalleResponse>("/disciplinas", disciplina);
    return response.data;
  },

  listarDisciplinas: async (): Promise<DisciplinaDetalleResponse[]> => {
    const response = await api.get<DisciplinaDetalleResponse[]>("/disciplinas");
    return response.data;
  },

  obtenerDisciplinaPorId: async (
    id: number
  ): Promise<DisciplinaDetalleResponse> => {
    const response = await api.get<DisciplinaDetalleResponse>(`/disciplinas/${id}`);
    return response.data;
  },

  actualizarDisciplina: async (
    id: number,
    disciplina: DisciplinaModificacionRequest
  ): Promise<DisciplinaDetalleResponse> => {
    const response = await api.put<DisciplinaDetalleResponse>(`/disciplinas/${id}`, disciplina);
    return response.data;
  },

  eliminarDisciplina: async (id: number): Promise<void> => {
    await api.delete(`/disciplinas/${id}`);
  },

  darBajaDisciplina: async (id: number): Promise<void> => {
    await api.delete(`/disciplinas/dar-baja/${id}`);
  },

  listarDisciplinasSimplificadas: async (): Promise<
    DisciplinaListadoResponse[]
  > => {
    const response = await api.get<DisciplinaListadoResponse[]>("/disciplinas/listado");
    return response.data;
  },

  obtenerDisciplinasPorFecha: async (
    fecha: string
  ): Promise<DisciplinaListadoResponse[]> => {
    const response = await api.get<DisciplinaListadoResponse[]>(
      `/disciplinas/por-fecha?fecha=${encodeURIComponent(fecha)}`
    );
    return response.data;
  },

  obtenerAlumnosDeDisciplina: async (
    disciplinaId: number
  ): Promise<AlumnoResponse[]> => {
    const response = await api.get<AlumnoResponse[]>(`/disciplinas/${disciplinaId}/alumnos`);
    return response.data;
  },

  obtenerProfesorDeDisciplina: async (
    disciplinaId: number
  ): Promise<ProfesorListadoResponse> => {
    const response = await api.get<ProfesorListadoResponse>(`/disciplinas/${disciplinaId}/profesor`);
    return response.data;
  },

  obtenerDisciplinasPorHorario: async (
    horario: string
  ): Promise<DisciplinaListadoResponse[]> => {
    const response = await api.get<DisciplinaListadoResponse[]>(
      `/disciplinas/por-horario?horario=${encodeURIComponent(horario)}`
    );
    return response.data;
  },

  buscarPorNombre: async (nombre: string): Promise<DisciplinaListadoResponse[]> => {
    const response = await api.get<DisciplinaListadoResponse[]>(
      `/disciplinas/buscar?nombre=${encodeURIComponent(nombre)}`
    );
    return response.data;
  },
};

export default disciplinasApi;
