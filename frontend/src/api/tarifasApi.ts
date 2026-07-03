import api from "./axiosConfig";

export interface TarifaDisciplina {
  id: number;
  disciplinaId: number;
  vigenteDesde: string;
  valorCuota: string;
  matricula: string;
  claseSuelta: string;
  clasePrueba: string;
  motivo: string;
  creadaPorUsuarioId: number;
  creadaPorUsername: string;
  createdAt: string;
  utilizada: boolean;
}

export interface CrearTarifaDisciplina {
  vigenteDesde: string;
  valorCuota: string;
  matricula: string;
  claseSuelta: string;
  clasePrueba: string;
  motivo: string;
}

const tarifasApi = {
  listar: async (disciplinaId: number): Promise<TarifaDisciplina[]> =>
    (await api.get(`/disciplinas/${disciplinaId}/tarifas`)).data,
  crear: async (disciplinaId: number, request: CrearTarifaDisciplina): Promise<TarifaDisciplina> =>
    (await api.post(`/disciplinas/${disciplinaId}/tarifas`, request)).data,
};

export default tarifasApi;
