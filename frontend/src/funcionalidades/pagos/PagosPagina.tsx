import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useSearchParams } from "react-router-dom";
import { toast } from "react-toastify";
import { getApiErrorMessage } from "../../api/apiError";
import pagosApi from "../../api/pagosApi";
import Boton from "../../componentes/comunes/Boton";
import EmptyState from "../../componentes/comunes/EmptyState";
import ErrorState from "../../componentes/comunes/ErrorState";
import LoadingState from "../../componentes/comunes/LoadingState";
import PaginationControls from "../../componentes/comunes/PaginationControls";
import { queryKeys } from "../../hooks/queryKeys";
import type { PagoResumenResponse } from "../../types/types";
import { formatMoney } from "../../utils/money";
import FilterBar from "../../componentes/comunes/FilterBar";
import PageHeader from "../../componentes/comunes/PageHeader";
import RowActions from "../../componentes/comunes/RowActions";
import StatusBadge from "../../componentes/comunes/StatusBadge";
import { Ban, Download } from "lucide-react";

const PAGE_SIZE = 50;

const positiveId = (value: string | null): number => {
  const id = Number(value);
  return Number.isInteger(id) && id > 0 ? id : 0;
};

export default function PagosPagina() {
  const [searchParams] = useSearchParams();
  const initialAlumnoId = positiveId(searchParams.get("alumnoId"));
  const [alumnoId, setAlumnoId] = useState(initialAlumnoId ? String(initialAlumnoId) : "");
  const [consultaId, setConsultaId] = useState(initialAlumnoId);
  const [page, setPage] = useState(0);
  const queryClient = useQueryClient();
  const pagos = useQuery({
    queryKey: queryKeys.pagos(consultaId, page, PAGE_SIZE),
    queryFn: () => pagosApi.listarPagosPorAlumno(consultaId, page, PAGE_SIZE),
    enabled: consultaId > 0,
  });
  const anulacion = useMutation({
    mutationFn: ({ pago, motivo }: { pago: PagoResumenResponse; motivo: string }) =>
      pagosApi.anularPago(pago.id, { motivo, idempotencyKey: crypto.randomUUID() }),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: ["pagos", consultaId] });
      toast.success("Pago anulado.");
    },
    onError: (error) => toast.error(getApiErrorMessage(error, "No fue posible anular el pago.")),
  });

  const buscar = () => {
    const id = positiveId(alumnoId);
    if (id > 0) {
      setPage(0);
      setConsultaId(id);
    }
  };
  const anular = (pago: PagoResumenResponse) => {
    const motivo = window.prompt("Motivo de la anulación");
    if (motivo?.trim()) anulacion.mutate({ pago, motivo: motivo.trim() });
  };
  const descargar = async (pagoId: number) => {
    try {
      await pagosApi.descargarRecibo(pagoId);
    } catch (error) {
      toast.error(getApiErrorMessage(error, "No se pudo descargar el recibo."));
    }
  };

  return (
    <main className="page-container">
      <PageHeader eyebrow="Cobranza" title="Pagos" description="Consultá recibos, estado y trazabilidad por alumno." count={pagos.data?.totalElements} />
      <FilterBar label="Consultar pagos">
        <label className="field-group sm:w-64" htmlFor="pagos-alumno-id">
          Alumno ID
          <input
            id="pagos-alumno-id"
            type="number"
            min="1"
            className="form-input"
            value={alumnoId}
            onChange={(event) => setAlumnoId(event.target.value)}
          />
        </label>
        <Boton type="button" onClick={buscar} disabled={positiveId(alumnoId) === 0}>Consultar pagos</Boton>
      </FilterBar>
      {pagos.isLoading && <LoadingState message="Cargando pagos..." />}
      {pagos.isError && <ErrorState message="No se pudieron cargar los pagos." onRetry={() => void pagos.refetch()} />}
      {pagos.data && pagos.data.content.length === 0 && <EmptyState message="El alumno no tiene pagos registrados." />}
      {pagos.data && pagos.data.content.length > 0 && (
        <div className="page-card">
          <div className="data-table-scroll"><table className="data-table">
            <thead><tr><th scope="col">ID</th><th scope="col">Fecha</th><th scope="col">Monto</th><th scope="col">Estado</th><th scope="col">Acciones</th></tr></thead>
            <tbody>{pagos.data.content.map((pago) => (
              <tr key={pago.id}>
                <td>{pago.id}</td><td>{pago.fecha}</td><td className="numeric-cell">$ {formatMoney(pago.montoRecibido)}</td><td><StatusBadge tone={pago.estado === "REGISTRADO" ? "success" : "neutral"}>{pago.estado}</StatusBadge></td>
                <td><div className="row-actions"><RowActions label={`Acciones del pago ${pago.id}`} actions={[
                  { label: "Descargar recibo", icon: Download, onSelect: () => void descargar(pago.id) },
                  ...(pago.estado === "REGISTRADO" ? [{ label: "Anular pago", icon: Ban, destructive: true, disabled: anulacion.isPending, onSelect: () => anular(pago) }] : []),
                ]} /></div></td>
              </tr>
            ))}</tbody></table></div>
        </div>
      )}
      {pagos.data && (
        <PaginationControls page={page} totalPages={pagos.data.totalPages} onPageChange={setPage} disabled={pagos.isFetching} />
      )}
    </main>
  );
}
