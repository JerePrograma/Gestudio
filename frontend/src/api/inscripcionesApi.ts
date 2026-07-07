// src/inscripcionesApi.ts
import api from "./axiosConfig";
import type {
  InscripcionRegistroRequest,
  InscripcionResponse,
  Page,
} from "../types/types";

const crear = async (request: InscripcionRegistroRequest): Promise<InscripcionResponse> => {
  const response = await api.post<InscripcionResponse>("/inscripciones", request);
  return response.data;
};

const listar = async (page = 0, size = 50, filtro = ""): Promise<Page<InscripcionResponse>> => {
  const response = await api.get<Page<InscripcionResponse>>("/inscripciones", { params: { page, size, filtro } });
  return response.data;
};

const obtenerPorId = async (id: number): Promise<InscripcionResponse> => {
  const response = await api.get<InscripcionResponse>(`/inscripciones/${id}`);
  return response.data;
};

const actualizar = async (
  id: number,
  request: InscripcionRegistroRequest
): Promise<InscripcionResponse> => {
  const response = await api.put<InscripcionResponse>(`/inscripciones/${id}`, request);
  return response.data;
};

const eliminar = async (id: number): Promise<void> => {
  await api.delete(`/inscripciones/${id}`);
};

const obtenerInscripcionesActivas = async (alumnoId: number): Promise<InscripcionResponse[]> => {
  const { data } = await api.get<InscripcionResponse[]>(`/inscripciones/alumno/${alumnoId}/activas`);
  return data;
};

const inscripcionesApi = {
  crear,
  listar,
  obtenerPorId,
  actualizar,
  eliminar,
  obtenerInscripcionesActivas
};

export default inscripcionesApi;
