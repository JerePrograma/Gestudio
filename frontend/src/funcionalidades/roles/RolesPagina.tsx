import { useCallback, useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Pencil, PlusCircle, Trash2 } from "lucide-react";
import { toast } from "react-toastify";
import rolesApi from "../../api/rolesApi";
import Boton from "../../componentes/comunes/Boton";
import Tabla from "../../componentes/comunes/Tabla";
import type { RolResponse } from "../../types/types";

const RolesPagina = () => {
  const [roles, setRoles] = useState<RolResponse[]>([]);
  const [loading, setLoading] = useState(true);
  const navigate = useNavigate();

  const cargar = useCallback(() => {
    setLoading(true);
    rolesApi.listar()
      .then(setRoles)
      .catch(() => toast.error("No se pudieron cargar los roles."))
      .finally(() => setLoading(false));
  }, []);

  useEffect(cargar, [cargar]);

  const desactivar = async (rol: RolResponse) => {
    if (!window.confirm(`¿Desactivar el rol ${rol.nombre}?`)) return;
    try {
      await rolesApi.desactivar(rol.id);
      cargar();
    } catch {
      toast.error("No se pudo desactivar el rol.");
    }
  };

  if (loading && roles.length === 0) return <div className="text-center py-4">Cargando...</div>;

  return (
    <div className="page-container">
      <h1 className="page-title">Roles y permisos</h1>
      <div className="page-button-group flex justify-end mb-4">
        <Boton onClick={() => navigate("/roles/formulario")} className="page-button">
          <PlusCircle className="w-5 h-5 mr-2" />Nuevo rol
        </Boton>
      </div>
      <div className="page-card">
        <Tabla
          headers={["Código", "Nombre", "Estado", "Tipo", "Permisos"]}
          data={roles}
          getRowKey={(rol) => rol.id}
          customRender={(rol) => [
            rol.codigo,
            rol.nombre,
            rol.activo ? "Activo" : "Inactivo",
            rol.sistema ? "Sistema" : "Personalizado",
            rol.cantidadPermisos,
          ]}
          actions={(rol) => (
            <div className="flex gap-2">
              <Boton
                onClick={() => navigate(`/roles/formulario?id=${rol.id}`)}
                className="page-button-secondary"
                disabled={!rol.editable}
              >
                <Pencil className="w-4 h-4 mr-2" />Editar
              </Boton>
              <Boton
                onClick={() => desactivar(rol)}
                className="page-button-danger"
                disabled={rol.sistema || !rol.activo}
              >
                <Trash2 className="w-4 h-4 mr-2" />Desactivar
              </Boton>
            </div>
          )}
        />
      </div>
    </div>
  );
};

export default RolesPagina;
