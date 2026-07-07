import api from "./axiosConfig";

export interface CondicionEconomica {
  id: number;
  inscripcionId: number;
  vigenteDesde: string;
  costoParticular: string | null;
  bonificacionId: number | null;
  bonificacionDescripcion: string | null;
  bonificacionPorcentaje: string;
  bonificacionValorFijo: string;
  motivo: string;
  creadaPorUsuarioId: number;
  creadaPorUsername: string;
  createdAt: string;
  utilizada: boolean;
}

export interface CrearCondicionEconomica {
  vigenteDesde: string;
  costoParticular: string | null;
  bonificacionId: number | null;
  motivo: string;
}

const condicionesEconomicasApi = {
  listar: async (inscripcionId: number): Promise<CondicionEconomica[]> =>
    (await api.get<CondicionEconomica[]>(`/inscripciones/${inscripcionId}/condiciones-economicas`)).data,
  crear: async (inscripcionId: number, request: CrearCondicionEconomica): Promise<CondicionEconomica> =>
    (await api.post<CondicionEconomica>(`/inscripciones/${inscripcionId}/condiciones-economicas`, request)).data,
};

export default condicionesEconomicasApi;
