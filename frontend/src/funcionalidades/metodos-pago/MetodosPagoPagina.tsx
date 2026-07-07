"use client";

import { useEffect, useState, useCallback, useMemo } from "react";
import { useNavigate } from "react-router-dom";
import Tabla from "../../componentes/comunes/Tabla";
import metodosPagoApi from "../../api/metodosPagoApi";
import Boton from "../../componentes/comunes/Boton";
import { PlusCircle, Pencil, Trash2 } from "lucide-react";
import { toast } from "react-toastify";
import type { MetodoPagoResponse } from "../../types/types";
import ListaConCargaManual from "../../componentes/comunes/ListaConCargaManual";
import ErrorState from "../../componentes/comunes/ErrorState";
import LoadingState from "../../componentes/comunes/LoadingState";
import PageHeader from "../../componentes/comunes/PageHeader";
import RowActions from "../../componentes/comunes/RowActions";

const itemsPerPage = 25;

const MetodosPagoPagina = () => {
  const [metodos, setMetodos] = useState<MetodoPagoResponse[]>([]);
  const [visibleCount, setVisibleCount] = useState(itemsPerPage);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const navigate = useNavigate();

  const fetchMetodos = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await metodosPagoApi.listarMetodosPago();
      setMetodos(response);
    } catch {
      toast.error("Error al cargar métodos de pago:");
      setError("Error al cargar métodos de pago.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchMetodos();
  }, [fetchMetodos]);

  // Se muestra un subconjunto de la lista completa
  const currentItems = useMemo(
    () => metodos.slice(0, visibleCount),
    [metodos, visibleCount]
  );

  // Indica si hay más elementos para cargar
  const hasMore = useMemo(
    () => visibleCount < metodos.length,
    [visibleCount, metodos.length]
  );

  // Incrementa la cantidad visible en bloques
  const onLoadMore = useCallback(() => {
    if (hasMore) {
      setVisibleCount((prev) => prev + itemsPerPage);
    }
  }, [hasMore]);

  const handleEliminarMetodo = async (id: number) => {
    try {
      await metodosPagoApi.eliminarMetodoPago(id);
      toast.success("Método de pago eliminado correctamente.");
      fetchMetodos();
    } catch {
      toast.error("Error al eliminar el método de pago.");
    }
  };

  if (loading && metodos.length === 0)
    return <LoadingState message="Cargando métodos de pago..." />;
  if (error)
    return <ErrorState message={error} onRetry={() => void fetchMetodos()} />;

  return (
    <div className="page-container">
      <PageHeader eyebrow="Administración" title="Métodos de pago" description="Medios habilitados y recargos configurados." count={metodos.length}
        actions={<Boton
          onClick={() => navigate("/metodos-pago/formulario")}
          className="page-button"
          aria-label="Registrar nuevo método de pago"
        >
          <PlusCircle className="size-4" /> Nuevo método
        </Boton>} />
      <div>
        <Tabla
          headers={["ID", "Descripción", "Recargo"]}
          data={currentItems}
          getRowKey={(row) => row.id}
          actions={(fila: MetodoPagoResponse) => (
            <RowActions label={`Acciones de ${fila.descripcion}`} actions={[
              { label: "Editar", icon: Pencil, onSelect: () => navigate(`/metodos-pago/formulario?id=${fila.id}`) },
              { label: "Eliminar", icon: Trash2, destructive: true, onSelect: () => void handleEliminarMetodo(fila.id) },
            ]} />
          )}
          customRender={(fila: MetodoPagoResponse) => [
            fila.id,
            fila.descripcion,
            fila.recargo,
          ]}
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

export default MetodosPagoPagina;
