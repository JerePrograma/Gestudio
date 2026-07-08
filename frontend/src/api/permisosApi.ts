import api from "./axiosConfig";
import type { PermisoResponse } from "../types/types";

const listar = async (modulo?: string): Promise<PermisoResponse[]> =>
  (await api.get<PermisoResponse[]>("/permisos", { params: modulo ? { modulo } : undefined })).data;

export default { listar };
