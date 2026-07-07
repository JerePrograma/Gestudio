"use client";

import { useEffect, useState, useCallback, useMemo } from "react";
import { useNavigate } from "react-router-dom";
import Tabla from "../../componentes/comunes/Tabla";
import api from "../../api/axiosConfig";
import Boton from "../../componentes/comunes/Boton";
import { PlusCircle, Pencil, Trash2 } from "lucide-react";
import { toast } from "react-toastify";
import ListaConCargaManual from "../../componentes/comunes/ListaConCargaManual";

interface Rol {
  id: number;
  descripcion: string;
}

const RolesPagina = () => {
  const [roles, setRoles] = useState<Rol[]>([]);
  const [visibleCount, setVisibleCount] = useState(5);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const itemsPerPage = 25;
  const navigate = useNavigate();

  const fetchRoles = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await api.get<Rol[]>("/roles");
      setRoles(response.data);
    } catch {
      toast.error("Error al cargar roles:");
      setError("Error al cargar roles.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchRoles();
  }, [fetchRoles]);

  // Calcula el subconjunto de roles a mostrar
  const currentItems = useMemo(
    () => roles.slice(0, visibleCount),
    [roles, visibleCount]
  );
  // Determina si hay más roles por mostrar
  const hasMore = useMemo(
    () => visibleCount < roles.length,
    [visibleCount, roles.length]
  );

  // Función que incrementa la cantidad de elementos visibles
  const onLoadMore = useCallback(() => {
    if (hasMore) {
      setVisibleCount((prev) => prev + itemsPerPage);
    }
  }, [hasMore, itemsPerPage]);

  if (loading && roles.length === 0)
    return <div className="text-center py-4">Cargando...</div>;
  if (error)
    return <div className="text-center py-4 text-destructive">{error}</div>;

  return (
    <div className="page-container">
      <h1 className="page-title">Roles</h1>
      <div className="page-button-group flex justify-end mb-4">
        <Boton
          onClick={() => navigate("/roles/formulario")}
          className="page-button"
          aria-label="Registrar Nuevo Rol"
        >
          <PlusCircle className="w-5 h-5 mr-2" />
          Registrar Nuevo Rol
        </Boton>
      </div>
      <div className="page-card">
        <Tabla
          headers={["ID", "Descripcion", "Acciones"]}
          data={currentItems}
          getRowKey={(row) => row.id}
          actions={(fila) => (
            <div className="flex gap-2">
              <Boton
                onClick={() => navigate(`/roles/formulario?id=${fila.id}`)}
                className="page-button-secondary"
                aria-label={`Editar rol ${fila.descripcion}`}
              >
                <Pencil className="w-4 h-4 mr-2" />
                Editar
              </Boton>
              <Boton
                className="page-button-danger"
                aria-label={`Eliminar rol ${fila.descripcion}`}
              >
                <Trash2 className="w-4 h-4 mr-2" />
                Eliminar
              </Boton>
            </div>
          )}
          customRender={(fila) => [fila.id, fila.descripcion]}
        />
      </div>
      {hasMore && (
        <ListaConCargaManual
          onLoadMore={onLoadMore}
          hasMore={hasMore}
          loading={loading}
          className="mt-4"
        >
          {loading && <div className="text-center py-2">Cargando más...</div>}
        </ListaConCargaManual>
      )}
    </div>
  );
};

export default RolesPagina;
