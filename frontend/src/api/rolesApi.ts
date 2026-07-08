import api from "./axiosConfig";
import type {
  RolDetalleResponse,
  RolModificacionRequest,
  RolRegistroRequest,
  RolResponse,
} from "../types/types";

const listar = async (): Promise<RolResponse[]> =>
  (await api.get<RolResponse[]>("/roles")).data;

const obtener = async (id: number): Promise<RolDetalleResponse> =>
  (await api.get<RolDetalleResponse>(`/roles/${id}`)).data;

const crear = async (request: RolRegistroRequest): Promise<RolDetalleResponse> =>
  (await api.post<RolDetalleResponse>("/roles", request)).data;

const modificar = async (id: number, request: RolModificacionRequest): Promise<RolDetalleResponse> =>
  (await api.put<RolDetalleResponse>(`/roles/${id}`, request)).data;

const desactivar = async (id: number): Promise<void> => {
  await api.delete(`/roles/${id}`);
};

const asignarPermisos = async (id: number, permisos: string[]): Promise<RolDetalleResponse> =>
  (await api.put<RolDetalleResponse>(`/roles/${id}/permisos`, { permisos })).data;

export default { listar, obtener, crear, modificar, desactivar, asignarPermisos };
