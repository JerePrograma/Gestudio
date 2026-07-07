"use client";

import { useEffect, useState, useCallback, useMemo } from "react";
import { useNavigate } from "react-router-dom";
import Tabla from "../../componentes/comunes/Tabla";
import conceptosApi from "../../api/conceptosApi";
import Boton from "../../componentes/comunes/Boton";
import { PlusCircle, Pencil, Trash2 } from "lucide-react";
import type { ConceptoResponse } from "../../types/types";
import { toast } from "react-toastify";
import ListaConCargaManual from "../../componentes/comunes/ListaConCargaManual";
import ErrorState from "../../componentes/comunes/ErrorState";
import LoadingState from "../../componentes/comunes/LoadingState";
import PageHeader from "../../componentes/comunes/PageHeader";
import RowActions from "../../componentes/comunes/RowActions";
import { formatMoney } from "../../utils/money";

const itemsPerPage = 25;

const ConceptosPagina = () => {
  const [conceptos, setConceptos] = useState<ConceptoResponse[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  // Se utiliza visibleCount en lugar de currentPage para determinar cuántos elementos se muestran
  const [visibleCount, setVisibleCount] = useState(itemsPerPage);
  const navigate = useNavigate();

  const fetchConceptos = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await conceptosApi.listarConceptos();
      setConceptos(response);
    } catch {
      toast.error("Error al cargar conceptos:");
      setError("Error al cargar conceptos.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchConceptos();
  }, [fetchConceptos]);

  // Se obtiene un subconjunto de los conceptos a mostrar
  const currentItems = useMemo(
    () => conceptos.slice(0, visibleCount),
    [conceptos, visibleCount]
  );

  // Determina si hay más elementos para cargar
  const hasMore = useMemo(
    () => visibleCount < conceptos.length,
    [visibleCount, conceptos.length]
  );

  // Incrementa la cantidad visible en bloques
  const onLoadMore = useCallback(() => {
    if (hasMore) {
      setVisibleCount((prev) => prev + itemsPerPage);
    }
  }, [hasMore]);

  const handleEliminarConcepto = async (id: number) => {
    try {
      await conceptosApi.eliminarConcepto(id);
      toast.success("Concepto eliminado correctamente.");
      fetchConceptos();
    } catch {
      toast.error("Error al eliminar el concepto.");
    }
  };

  if (loading && conceptos.length === 0)
    return <LoadingState message="Cargando conceptos..." />;
  if (error)
    return <ErrorState message={error} onRetry={() => void fetchConceptos()} />;

  return (
    <div className="page-container">
      <PageHeader eyebrow="Administración" title="Conceptos" description="Conceptos facturables y valores vigentes." count={conceptos.length}
        actions={<Boton
          onClick={() => navigate("/conceptos/formulario-concepto")}
          className="page-button"
          aria-label="Registrar nuevo concepto"
        >
          <PlusCircle className="size-4" /> Nuevo concepto
        </Boton>} />
      <div>
        <Tabla
          headers={["ID", "Descripción", "Precio", "Subconcepto"]}
          data={currentItems}
          getRowKey={(row) => row.id}
          actions={(fila: ConceptoResponse) => (
            <RowActions label={`Acciones de ${fila.descripcion}`} actions={[
              { label: "Editar", icon: Pencil, onSelect: () => navigate(`/conceptos/formulario-concepto?id=${fila.id}`) },
              { label: "Eliminar", icon: Trash2, destructive: true, onSelect: () => void handleEliminarConcepto(fila.id) },
            ]} />
          )}
          customRender={(fila: ConceptoResponse) => [
            fila.id,
            fila.descripcion,
            <span className="numeric-cell block" key="precio">$ {formatMoney(fila.precio)}</span>,
            fila.subConcepto.descripcion,
          ]}
        />
      </div>
      {hasMore && (
        <div className="mt-4">
          <ListaConCargaManual
            onLoadMore={onLoadMore}
            hasMore={hasMore}
            loading={loading}
            className="justify-center w-full"
          >
            {loading && <div className="text-center py-2">Cargando más...</div>}
          </ListaConCargaManual>
        </div>
      )}
    </div>
  );
};

export default ConceptosPagina;
