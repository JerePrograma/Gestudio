// src/alumnosApi.ts
import api from "./axiosConfig";
import type {
  AlumnoRegistro,
  DisciplinaListadoResponse,
  AlumnoResponse,
  Page,
} from "../types/types";

const alumnosApi = {
  listar: async (page = 0, size = 50): Promise<Page<AlumnoResponse>> => {
    const response = await api.get<Page<AlumnoResponse>>("/alumnos", { params: { page, size } });
    return response.data;
  },

  obtenerPorId: async (id: number): Promise<AlumnoResponse> => {
    const response = await api.get<AlumnoResponse>(`/alumnos/${id}`);
    return response.data;
  },

  registrar: async (alumno: AlumnoRegistro): Promise<AlumnoResponse> => {
    const response = await api.post<AlumnoResponse>("/alumnos", alumno);
    return response.data;
  },

  actualizar: async (
    id: number,
    alumno: AlumnoRegistro
  ): Promise<AlumnoResponse> => {
    const response = await api.put<AlumnoResponse>(`/alumnos/${id}`, alumno);
    return response.data;
  },

  darBaja: async (id: number): Promise<void> => {
    await api.delete(`/alumnos/${id}`);
  },

  buscarPorNombre: async (nombre: string, page = 0, size = 50): Promise<Page<AlumnoResponse>> => {
    const response = await api.get<Page<AlumnoResponse>>("/alumnos/buscar", { params: { nombre, page, size } });
    return response.data;
  },

  obtenerDisciplinas: async (
    alumnoId: number
  ): Promise<DisciplinaListadoResponse[]> => {
    const response = await api.get(`/alumnos/${alumnoId}/disciplinas`);
    return response.data;
  },
};

export default alumnosApi;
