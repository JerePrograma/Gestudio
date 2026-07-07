"use client";

import { useEffect, useState, useCallback, useMemo } from "react";
import { useNavigate } from "react-router-dom";
import Tabla from "../../componentes/comunes/Tabla";
import Boton from "../../componentes/comunes/Boton";
import { PlusCircle, Pencil, Trash2 } from "lucide-react";
import type { UsuarioResponse } from "../../types/types";
import usuariosApi from "../../api/usuariosApi";
import { toast } from "react-toastify";
import ListaConCargaManual from "../../componentes/comunes/ListaConCargaManual";

const itemsPerPage = 25;

const UsuariosPagina = () => {
  const [usuarios, setUsuarios] = useState<UsuarioResponse[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Se utiliza visibleCount en lugar de currentPage para la lógica de infinite scroll
  const [visibleCount, setVisibleCount] = useState(itemsPerPage);
  const navigate = useNavigate();

  const fetchUsuarios = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const usuariosData = await usuariosApi.listarUsuarios();
      setUsuarios(usuariosData);
    } catch {
      toast.error("Error al cargar usuarios:");
      setError("Error al cargar usuarios.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchUsuarios();
  }, [fetchUsuarios]);

  // Se obtiene el subconjunto de usuarios a mostrar, desde el inicio hasta visibleCount
  const currentItems = useMemo(
    () => usuarios.slice(0, visibleCount),
    [usuarios, visibleCount]
  );

  // Determina si existen más elementos para cargar
  const hasMore = useMemo(
    () => visibleCount < usuarios.length,
    [visibleCount, usuarios.length]
  );

  // Función que incrementa visibleCount en bloques
  const onLoadMore = useCallback(() => {
    if (hasMore) {
      setVisibleCount((prev) => prev + itemsPerPage);
    }
  }, [hasMore]);

  const handleEliminarUsuario = useCallback(async (id: number) => {
    if (window.confirm("¿Seguro que deseas eliminar este usuario?")) {
      try {
        await usuariosApi.eliminarUsuario(id);
        setUsuarios((prev) => prev.filter((u) => u.id !== id));
      } catch {
        toast.error("Error al eliminar usuario:");
      }
    }
  }, []);

  if (loading && usuarios.length === 0)
    return <div className="text-center py-4">Cargando...</div>;
  if (error)
    return <div className="text-center py-4 text-destructive">{error}</div>;

  return (
    <div className="page-container">
      <h1 className="page-title">Usuarios</h1>
      <div className="page-button-group flex justify-end mb-4">
        <Boton
          onClick={() => navigate("/usuarios/formulario")}
          className="page-button"
          aria-label="Registrar nuevo usuario"
        >
          <PlusCircle className="w-5 h-5 mr-2" />
          Registrar Nuevo Usuario
        </Boton>
      </div>
      <div className="page-card">
        <Tabla
          headers={["ID", "Nombre", "Rol"]}
          data={currentItems}
          getRowKey={(row) => row.id}
          customRender={(fila: UsuarioResponse) => [
            fila.id,
            fila.nombreUsuario,
            fila.rol,
          ]}
          actions={(fila: UsuarioResponse) => (
            <div className="flex gap-2">
              <Boton
                onClick={() => navigate(`/usuarios/formulario?id=${fila.id}`)}
                className="page-button-secondary"
                aria-label={`Editar usuario ${fila.nombreUsuario}`}
              >
                <Pencil className="w-4 h-4 mr-2" />
                Editar
              </Boton>
              <Boton
                onClick={() => handleEliminarUsuario(fila.id)}
                className="page-button-danger"
                aria-label={`Eliminar usuario ${fila.nombreUsuario}`}
              >
                <Trash2 className="w-4 h-4 mr-2" />
                Eliminar
              </Boton>
            </div>
          )}
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

export default UsuariosPagina;
