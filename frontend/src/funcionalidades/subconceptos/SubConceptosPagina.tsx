"use client";

import { useState, useEffect, useCallback, useMemo } from "react";
import { useNavigate } from "react-router-dom";
import Tabla from "../../componentes/comunes/Tabla";
import subConceptosApi from "../../api/subConceptosApi";
import Boton from "../../componentes/comunes/Boton";
import { PlusCircle, Pencil, Trash2 } from "lucide-react";
import type { SubConceptoResponse } from "../../types/types";
import { toast } from "react-toastify";
import ListaConCargaManual from "../../componentes/comunes/ListaConCargaManual";

const ITEMS_PER_LOAD = 5;

const SubConceptos = () => {
  const [subConceptos, setSubConceptos] = useState<SubConceptoResponse[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // visibleCount controla cuántos registros se muestran
  const [visibleCount, setVisibleCount] = useState<number>(ITEMS_PER_LOAD);
  const navigate = useNavigate();

  const fetchSubConceptos = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await subConceptosApi.listarSubConceptos();
      setSubConceptos(response);
      // Al cargar los datos se inicializan los elementos visibles
      setVisibleCount(ITEMS_PER_LOAD);
    } catch {
      toast.error("Error al cargar subconceptos:");
      setError("Error al cargar subconceptos.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchSubConceptos();
  }, [fetchSubConceptos]);

  // Los elementos que se muestran actualmente (de 0 a visibleCount)
  const currentItems = useMemo(
    () => subConceptos.slice(0, visibleCount),
    [subConceptos, visibleCount]
  );

  // Determina si aún quedan elementos por mostrar
  const hasMore = visibleCount < subConceptos.length;

  // Función que incrementa la cantidad de elementos visibles
  const loadMore = useCallback(() => {
    setVisibleCount((prev) =>
      Math.min(prev + ITEMS_PER_LOAD, subConceptos.length)
    );
  }, [subConceptos.length]);

  const handleEliminarSubConcepto = async (id: number) => {
    try {
      await subConceptosApi.eliminarSubConcepto(id);
      toast.success("Subconcepto eliminado correctamente.");
      fetchSubConceptos();
    } catch {
      toast.error("Error al eliminar el subconcepto.");
    }
  };

  if (loading && subConceptos.length === 0)
    return <div className="text-center py-4">Cargando...</div>;
  if (error && subConceptos.length === 0)
    return <div className="text-center py-4 text-destructive">{error}</div>;

  return (
    <div className="page-container">
      <h1 className="page-title">Subconceptos</h1>
      <div className="page-button-group flex justify-end mb-4">
        <Boton
          onClick={() => navigate("/subconceptos/formulario")}
          className="page-button"
          aria-label="Registrar nuevo subconcepto"
        >
          <PlusCircle className="w-5 h-5 mr-2" />
          Registrar Nuevo Subconcepto
        </Boton>
      </div>
      <div className="page-card">
        <Tabla
          headers={["ID", "Descripcion", "Acciones"]}
          data={currentItems}
          getRowKey={(row) => row.id}
          customRender={(fila: SubConceptoResponse) => [
            fila.id,
            fila.descripcion,
          ]}
          actions={(fila: SubConceptoResponse) => (
            <div className="flex gap-2">
              <Boton
                onClick={() =>
                  navigate(`/subconceptos/formulario?id=${fila.id}`)
                }
                className="page-button-secondary"
                aria-label={`Editar subconcepto ${fila.descripcion}`}
              >
                <Pencil className="w-4 h-4 mr-2" />
                Editar
              </Boton>
              <Boton
                onClick={() => handleEliminarSubConcepto(fila.id)}
                className="page-button-danger"
                aria-label={`Eliminar subconcepto ${fila.descripcion}`}
              >
                <Trash2 className="w-4 h-4 mr-2" />
                Eliminar
              </Boton>
            </div>
          )}
        />
      </div>
      {hasMore && (
        <div className="mt-4">
          <ListaConCargaManual
            onLoadMore={loadMore}
            hasMore={hasMore}
            loading={loading}
            className="justify-center w-full"
            children={undefined}
          />
        </div>
      )}
    </div>
  );
};

export default SubConceptos;
