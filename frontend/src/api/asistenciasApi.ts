// src/asistenciasApi.ts

import api from "./axiosConfig";
import axios from "axios";
import { toast } from "react-toastify";
import type {
  AsistenciaDiariaRegistroRequest,
  AsistenciaDiariaResponse,
  AsistenciaMensualModificacionRequest,
  AsistenciaMensualDetalleResponse,
  AsistenciaMensualListadoResponse,
  PageResponse,
  AsistenciaMensualRegistroRequest,
  DisciplinaListadoResponse,
  AsistenciasActivasResponse,
} from "../types/types";

const asistenciasApi = {
  // Obtiene el detalle de la asistencia mensual según parámetros (disciplina, mes, anio)
  obtenerAsistenciaMensualDetallePorParametros: async (
    disciplinaId: number,
    mes: number,
    anio: number
  ): Promise<AsistenciaMensualDetalleResponse | null> => {
    try {
      const response = await api.get<AsistenciaMensualDetalleResponse>("/asistencias-mensuales/por-disciplina/detalle", {
        params: { disciplinaId, mes, anio },
      });
      return response.data;
    } catch {
      toast.error("Error al obtener la asistencia mensual. Intente nuevamente.");
      return null;
    }
  },

  // Crea una asistencia mensual (planilla) para una disciplina
  // Se adapta al endpoint POST "/asistencias-mensuales"
  crearAsistenciaMensualPorDisciplina: async (
    request: AsistenciaMensualRegistroRequest
  ): Promise<AsistenciaMensualDetalleResponse> => {
    try {
      const response = await api.post<AsistenciaMensualDetalleResponse>("/asistencias-mensuales", request);
      return response.data;
    } catch (error) {
      toast.error("Error al crear la asistencia mensual. Intente nuevamente.");
      throw error;
    }
  },

  // Lista las planillas mensuales según criterios (opcional: profesor, disciplina, mes, anio)
  listarAsistenciasMensuales: async (
    profesorId?: number,
    disciplinaId?: number,
    mes?: number,
    anio?: number
  ): Promise<AsistenciaMensualListadoResponse[]> => {
    try {
      const response = await api.get<AsistenciaMensualListadoResponse[]>("/asistencias-mensuales", {
        params: { profesorId, disciplinaId, mes, anio },
      });
      return response.data;
    } catch (error) {
      if (axios.isAxiosError(error) && error.response?.status === 404) {
        toast.warn("No se encontraron asistencias para los criterios seleccionados.");
        return [];
      }
      toast.error("Error al obtener listado de asistencias. Intente nuevamente.");
      throw error;
    }
  },

  // Actualiza la asistencia mensual (por ejemplo, observaciones de cada alumno)
  actualizarAsistenciaMensual: async (
    id: number,
    asistencia: AsistenciaMensualModificacionRequest
  ): Promise<AsistenciaMensualDetalleResponse> => {
    try {
      const response = await api.put<AsistenciaMensualDetalleResponse>(`/asistencias-mensuales/${id}`, asistencia);
      return response.data;
    } catch (error) {
      toast.error("Error al actualizar asistencia. Intente nuevamente.");
      throw error;
    }
  },

  // Obtiene una página de asistencias diarias filtradas por disciplina y fecha
  obtenerAsistenciasPorDisciplinaYFecha: async (
    disciplinaId: number,
    fecha: string,
    page = 0,
    size = 10
  ): Promise<PageResponse<AsistenciaDiariaResponse>> => {
    try {
      const response = await api.get<PageResponse<AsistenciaDiariaResponse>>("/asistencias-diarias/por-disciplina-y-fecha", {
        params: { disciplinaId, fecha, page, size },
      });
      return response.data;
    } catch (error) {
      toast.error("Error al obtener asistencias. Intente nuevamente.");
      throw error;
    }
  },

  // Obtiene las asistencias diarias para una planilla (por el id de la planilla)
  obtenerAsistenciasDiarias: async (
    asistenciaMensualId: number
  ): Promise<AsistenciaDiariaResponse[]> => {
    try {
      const response = await api.get<AsistenciaDiariaResponse[]>(`/asistencias-diarias/por-asistencia-mensual/${asistenciaMensualId}`);
      return response.data;
    } catch (error) {
      toast.error("Error al obtener asistencias. Intente nuevamente.");
      throw error;
    }
  },

  // Registra (o actualiza) una asistencia diaria
  // Se utiliza PUT a la ruta "/asistencias-diarias" para ambas operaciones
  registrarAsistenciaDiaria: async (
    request: AsistenciaDiariaRegistroRequest
  ): Promise<AsistenciaDiariaResponse> => {
    try {
      const response = await api.put<AsistenciaDiariaResponse>("/asistencias-diarias/registrar", request);
      return response.data;
    } catch (error) {
      toast.error("No se pudo registrar la asistencia. Verifica los datos.");
      throw error;
    }
  },

  // Modifica una asistencia diaria existente
  modificarAsistenciaDiaria: async (
    id: number,
    request: AsistenciaDiariaRegistroRequest
  ): Promise<AsistenciaDiariaResponse> => {
    try {
      const response = await api.put<AsistenciaDiariaResponse>(`/asistencias-diarias/${id}`, request);
      return response.data;
    } catch (error) {
      toast.error("No se pudo modificar la asistencia. Intente nuevamente.");
      throw error;
    }
  },

  // Elimina una asistencia diaria por su id
  eliminarAsistenciaDiaria: async (id: number): Promise<void> => {
    try {
      await api.delete(`/asistencias-diarias/${id}`);
      toast.success("Asistencia eliminada correctamente.");
    } catch (error) {
      toast.error("Error al eliminar asistencia. Intente nuevamente.");
      throw error;
    }
  },

  // Crea las asistencias para inscripciones activas (creación masiva)
  crearAsistenciasParaInscripcionesActivas: async (): Promise<AsistenciasActivasResponse> => {
    try {
      const response = await api.post<AsistenciasActivasResponse>("/asistencias-mensuales/crear-asistencias-activos-detallado");
      return response.data;
    } catch (error) {
      toast.error("Error al crear las asistencias. Intente nuevamente.");
      throw error;
    }
  },

  // Lista las disciplinas simplificadas
  listarDisciplinasSimplificadas: async (): Promise<DisciplinaListadoResponse[]> => {
    try {
      const response = await api.get<DisciplinaListadoResponse[]>("/disciplinas/listado");
      return response.data;
    } catch (error) {
      toast.error("Error al obtener disciplinas. Intente nuevamente.");
      throw error;
    }
  },
};

export default asistenciasApi;
