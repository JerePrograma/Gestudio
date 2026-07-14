import api from "./axiosConfig";
import type {
  RolAsignableResponse,
  UsuarioRegistroRequest,
  UsuarioModificacionRequest,
  UsuarioResponse,
} from "../types/types";

const listarRolesAsignables = async (): Promise<RolAsignableResponse[]> => {
  const { data } = await api.get<RolAsignableResponse[]>("/usuarios/roles-asignables");
  return data;
};

const registrarUsuario = async (
  usuario: UsuarioRegistroRequest
): Promise<UsuarioResponse> => {
  const { data } = await api.post<UsuarioResponse>("/usuarios/registro", usuario);
  return data;
};

const obtenerUsuarioPorId = async (id: number): Promise<UsuarioResponse> => {
  const { data } = await api.get<UsuarioResponse>(`/usuarios/${id}`);
  return data;
};

const listarUsuarios = async (): Promise<UsuarioResponse[]> => {
  const { data } = await api.get<UsuarioResponse[]>("/usuarios");
  return data;
};

const actualizarUsuario = async (
  id: number,
  usuario: UsuarioModificacionRequest
): Promise<UsuarioResponse> => {
  const { data } = await api.put<UsuarioResponse>(`/usuarios/${id}`, usuario);
  return data;
};

const eliminarUsuario = async (id: number): Promise<void> => {
  await api.delete(`/usuarios/${id}`);
};

const usuariosApi = {
  listarRolesAsignables,
  registrarUsuario,
  obtenerUsuarioPorId,
  listarUsuarios,
  actualizarUsuario,
  eliminarUsuario,
};

export default usuariosApi;
