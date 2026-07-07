import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "react-toastify";
import { getApiErrorMessage } from "../../api/apiError";
import egresosApi from "../../api/egresosApi";
import metodosPagoApi from "../../api/metodosPagoApi";
import Boton from "../../componentes/comunes/Boton";
import EmptyState from "../../componentes/comunes/EmptyState";
import ErrorState from "../../componentes/comunes/ErrorState";
import LoadingState from "../../componentes/comunes/LoadingState";
import MoneyInput from "../../componentes/comunes/MoneyInput";
import PaginationControls from "../../componentes/comunes/PaginationControls";
import { queryKeys } from "../../hooks/queryKeys";
import { formatMoney, isPositiveMoney, normalizeMoneyInput } from "../../utils/money";
import PageHeader from "../../componentes/comunes/PageHeader";
import SectionCard from "../../componentes/comunes/SectionCard";
import StatusBadge from "../../componentes/comunes/StatusBadge";

const PAGE_SIZE = 50;

export default function EgresosPagina() {
  const [monto, setMonto] = useState("");
  const [metodoPagoId, setMetodoPagoId] = useState(0);
  const [page, setPage] = useState(0);
  const queryClient = useQueryClient();
  const egresos = useQuery({ queryKey: queryKeys.egresos(page, PAGE_SIZE), queryFn: () => egresosApi.listarEgresos(page, PAGE_SIZE) });
  const metodos = useQuery({ queryKey: queryKeys.metodosPago, queryFn: metodosPagoApi.listarMetodosPago });
  const alta = useMutation({
    mutationFn: () => egresosApi.registrarEgreso({
      monto: normalizeMoneyInput(monto)!,
      metodoPagoId,
      idempotencyKey: crypto.randomUUID(),
    }),
    onSuccess: async () => {
      setMonto("");
      await queryClient.invalidateQueries({ queryKey: ["egresos"] });
      toast.success("Egreso registrado.");
    },
    onError: (error) => toast.error(getApiErrorMessage(error, "No se pudo registrar el egreso.")),
  });
  const canSubmit = isPositiveMoney(monto) && metodoPagoId > 0 && !alta.isPending;

  return (
    <main className="page-container">
      <PageHeader eyebrow="Finanzas" title="Egresos" description="Registrá salidas de caja y consultá el historial operativo." count={egresos.data?.totalElements} />
      <SectionCard title="Registrar egreso" description="Completá importe y método de pago para registrar la salida.">
        <div className="grid gap-4 sm:grid-cols-[minmax(12rem,1fr)_minmax(14rem,1fr)_auto] sm:items-end">
        <MoneyInput id="egreso-monto" label="Monto" value={monto} onChange={setMonto} required />
        <label className="field-group" htmlFor="egreso-metodo">
          Método de pago
          <select id="egreso-metodo" className="form-input" value={metodoPagoId} onChange={(event) => setMetodoPagoId(Number(event.target.value))}>
            <option value={0}>Seleccione</option>
            {(metodos.data ?? []).filter((metodo) => metodo.activo)
              .map((metodo) => <option key={metodo.id} value={metodo.id}>{metodo.descripcion}</option>)}
          </select>
        </label>
        <Boton type="button" onClick={() => alta.mutate()} disabled={!canSubmit}>
          {alta.isPending ? "Registrando..." : "Registrar"}
        </Boton>
        </div>
      </SectionCard>
      {egresos.isLoading && <LoadingState message="Cargando egresos..." />}
      {egresos.isError && <ErrorState message="No se pudieron cargar los egresos." onRetry={() => void egresos.refetch()} />}
      {egresos.data?.content.length === 0 && <EmptyState message="No hay egresos registrados." />}
      {egresos.data && egresos.data.content.length > 0 && (
        <SectionCard title="Historial de egresos" description="Últimos egresos registrados." className="p-0 [&_.section-card-header]:m-0 [&_.section-card-header]:p-5">
          <div className="data-table-scroll"><table className="data-table"><thead><tr><th scope="col">Fecha</th><th scope="col">Monto</th><th scope="col">Estado</th></tr></thead>
            <tbody>{egresos.data.content.map((egreso) => <tr key={egreso.id}>
              <td>{egreso.fecha}</td><td className="numeric-cell">$ {formatMoney(egreso.monto)}</td><td><StatusBadge tone={egreso.estado === "REGISTRADO" ? "success" : "neutral"}>{egreso.estado}</StatusBadge></td>
            </tr>)}</tbody></table></div>
        </SectionCard>
      )}
      {egresos.data && <PaginationControls page={page} totalPages={egresos.data.totalPages} onPageChange={setPage} disabled={egresos.isFetching} />}
    </main>
  );
}
