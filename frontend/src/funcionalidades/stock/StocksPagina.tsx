import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Pencil, PlusCircle, Trash2 } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { toast } from "react-toastify";
import { getApiErrorMessage } from "../../api/apiError";
import stocksApi from "../../api/stocksApi";
import Boton from "../../componentes/comunes/Boton";
import ErrorState from "../../componentes/comunes/ErrorState";
import LoadingState from "../../componentes/comunes/LoadingState";
import PageHeader from "../../componentes/comunes/PageHeader";
import PaginationControls from "../../componentes/comunes/PaginationControls";
import RowActions from "../../componentes/comunes/RowActions";
import StatusBadge from "../../componentes/comunes/StatusBadge";
import Tabla from "../../componentes/comunes/Tabla";
import { queryKeys } from "../../hooks/queryKeys";
import { formatMoney } from "../../utils/money";

const PAGE_SIZE = 50;

const StocksPagina = () => {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [page, setPage] = useState(0);
  const stocks = useQuery({ queryKey: queryKeys.stocks(page, PAGE_SIZE), queryFn: () => stocksApi.listarStocks(page, PAGE_SIZE) });
  const baja = useMutation({
    mutationFn: (id: number) => stocksApi.eliminarStock(id),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.all.stocks });
      toast.success("Producto dado de baja.");
    },
    onError: (error) => toast.error(getApiErrorMessage(error, "No se pudo dar de baja el producto.")),
  });

  if (stocks.isLoading) return <LoadingState message="Cargando stock..." />;
  if (stocks.isError) return <ErrorState message="No se pudo cargar stock." onRetry={() => void stocks.refetch()} />;

  return <div className="page-container">
    <PageHeader eyebrow="Inventario" title="Stock" description="Productos, precios y disponibilidad actual." count={stocks.data?.totalElements ?? 0}
      actions={<Boton onClick={() => navigate("/stocks/formulario")} className="page-button"><PlusCircle className="size-4" /> Nuevo producto</Boton>} />
    <div><Tabla headers={["ID", "Producto", "Precio", "Stock", "Estado"]} data={stocks.data?.content ?? []} getRowKey={(row) => row.id}
      customRender={(row) => [row.id, <span className="font-semibold" key="nombre">{row.nombre}</span>, <span className="numeric-cell block" key="precio">$ {formatMoney(row.precio)}</span>, <span className="numeric-cell block" key="stock">{row.stock}</span>, <StatusBadge key="estado" tone={row.activo ? "success" : "neutral"}>{row.activo ? "Activo" : "Baja"}</StatusBadge>]}
      actions={(row) => <RowActions label={`Acciones de ${row.nombre}`} actions={[
        { label: "Editar", icon: Pencil, onSelect: () => navigate(`/stocks/formulario?id=${row.id}`) },
        ...(row.activo ? [{ label: "Dar de baja", icon: Trash2, destructive: true, disabled: baja.isPending, onSelect: () => { if (window.confirm(`¿Dar de baja ${row.nombre}?`)) baja.mutate(row.id); } }] : []),
      ]} /> } /></div>
    <PaginationControls page={page} totalPages={stocks.data?.totalPages ?? 0} onPageChange={setPage} disabled={stocks.isFetching} />
  </div>;
};

export default StocksPagina;
