"use client";

import { useEffect, useState, useCallback, useMemo } from "react";
import { useNavigate } from "react-router-dom";
import Tabla from "../../componentes/comunes/Tabla";
import api from "../../api/axiosConfig";
import Boton from "../../componentes/comunes/Boton";
import { PlusCircle, Pencil, Trash2 } from "lucide-react";
import type { BonificacionResponse } from "../../types/types";
import { toast } from "react-toastify";
import ListaConCargaManual from "../../componentes/comunes/ListaConCargaManual";

const Bonificaciones = () => {
  const [bonificaciones, setBonificaciones] = useState<BonificacionResponse[]>(
    []
  );
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const itemsPerLoad = 25;
  // visibleCount controla cuántos elementos se muestran actualmente
  const [visibleCount, setVisibleCount] = useState<number>(0);
  const navigate = useNavigate();

  const fetchBonificaciones = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await api.get<BonificacionResponse[]>("/bonificaciones");
      setBonificaciones(response.data);
      // Se muestran inicialmente los primeros itemsPerLoad elementos
      setVisibleCount(itemsPerLoad);
    } catch {
      toast.error("Error al cargar bonificaciones:");
      setError("Error al cargar bonificaciones.");
    } finally {
      setLoading(false);
    }
  }, [itemsPerLoad]);

  useEffect(() => {
    fetchBonificaciones();
  }, [fetchBonificaciones]);

  // Los elementos que se muestran actualmente
  const currentItems = useMemo(
    () => bonificaciones.slice(0, visibleCount),
    [bonificaciones, visibleCount]
  );

  // Determina si quedan más elementos por mostrar
  const hasMore = visibleCount < bonificaciones.length;

  // Función para incrementar la cantidad de elementos visibles
  const loadMore = useCallback(() => {
    setVisibleCount((prev) =>
      Math.min(prev + itemsPerLoad, bonificaciones.length)
    );
  }, [itemsPerLoad, bonificaciones.length]);

  if (loading && bonificaciones.length === 0)
    return <div className="text-center py-4">Cargando...</div>;
  if (error && bonificaciones.length === 0)
    return <div className="text-center py-4 text-destructive">{error}</div>;

  return (
    <div className="page-container">
      <h1 className="page-title">Bonificaciones</h1>
      <div className="page-button-group flex justify-end mb-4">
        <Boton
          onClick={() => navigate("/bonificaciones/formulario")}
          className="page-button"
          aria-label="Registrar nueva bonificacion"
        >
          <PlusCircle className="w-5 h-5 mr-2" />
          Registrar Nueva Bonificacion
        </Boton>
      </div>
      <div className="page-card">
        <Tabla
          headers={[
            "ID",
            "Descripcion",
            "Descuento (%)",
            "Descuento (monto)",
            "Activo",
            "Acciones",
          ]}
          data={currentItems}
          getRowKey={(row) => row.id}
          customRender={(fila) => [
            fila.id,
            fila.descripcion,
            fila.porcentajeDescuento,
            fila.valorFijo,
            fila.activo ? "Si" : "No",
          ]}
          actions={(fila) => (
            <div className="flex gap-2">
              <Boton
                onClick={() =>
                  navigate(`/bonificaciones/formulario?id=${fila.id}`)
                }
                className="page-button-secondary"
                aria-label={`Editar bonificacion ${fila.descripcion}`}
              >
                <Pencil className="w-4 h-4 mr-2" />
                Editar
              </Boton>
              <Boton
                className="page-button-danger"
                aria-label={`Eliminar bonificacion ${fila.descripcion}`}
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
          onLoadMore={loadMore}
          hasMore={hasMore}
          loading={loading}
          className="mt-4"
          children={undefined}
        />
      )}
    </div>
  );
};

export default Bonificaciones;
