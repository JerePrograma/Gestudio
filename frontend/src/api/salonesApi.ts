import api from "./axiosConfig";
import type {
  SalonRegistroRequest,
  SalonModificacionRequest,
  SalonResponse,
  Page,
} from "../types/types";

const salonesApi = {
  registrarSalon: async (
    salon: SalonRegistroRequest
  ): Promise<SalonResponse> => {
    const response = await api.post<SalonResponse>("/salones", salon);
    return response.data;
  },

  listarSalones: async (page = 0, size = 10): Promise<Page<SalonResponse>> => {
    const response = await api.get<Page<SalonResponse>>("/salones", { params: { page, size } });
    return response.data;
  },

  obtenerSalonPorId: async (id: number): Promise<SalonResponse> => {
    const response = await api.get<SalonResponse>(`/salones/${id}`);
    return response.data;
  },

  actualizarSalon: async (
    id: number,
    salon: SalonModificacionRequest
  ): Promise<SalonResponse> => {
    const response = await api.put<SalonResponse>(`/salones/${id}`, salon);
    return response.data;
  },

  eliminarSalon: async (id: number): Promise<void> => {
    await api.delete(`/salones/${id}`);
  },
};

export default salonesApi;
