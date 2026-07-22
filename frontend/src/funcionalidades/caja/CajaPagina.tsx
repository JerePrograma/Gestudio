import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import cajaApi from "../../api/cajaApi";
import Boton from "../../componentes/comunes/Boton";
import EmptyState from "../../componentes/comunes/EmptyState";
import ErrorState from "../../componentes/comunes/ErrorState";
import LoadingState from "../../componentes/comunes/LoadingState";
import PaginationControls from "../../componentes/comunes/PaginationControls";
import { queryKeys } from "../../hooks/queryKeys";
import { formatMoney } from "../../utils/money";
import FilterBar from "../../componentes/comunes/FilterBar";
import PageHeader from "../../componentes/comunes/PageHeader";
import SectionCard from "../../componentes/comunes/SectionCard";
import StatCard from "../../componentes/comunes/StatCard";
import StatusBadge from "../../componentes/comunes/StatusBadge";
import { APP_TIME_ZONE } from "../../config/environment";
import { currentDateInTimeZone } from "../../utils/civilDate";

const PAGE_SIZE = 50;

export default function CajaPagina() {
  const today = currentDateInTimeZone(APP_TIME_ZONE);
  const [desde, setDesde] = useState(today);
  const [hasta, setHasta] = useState(today);
  const [consulta, setConsulta] = useState<{ desde: string; hasta: string; page: number }>();
  const resumen = useQuery({
    queryKey: queryKeys.caja(consulta?.desde ?? "", consulta?.hasta ?? "", consulta?.page ?? 0, PAGE_SIZE),
    queryFn: () => cajaApi.obtenerResumen(consulta!.desde, consulta!.hasta, consulta!.page, PAGE_SIZE),
    enabled: Boolean(consulta),
  });
  const consultar = () => setConsulta({ desde, hasta, page: 0 });
  const cambiarPagina = (page: number) => setConsulta((actual) => actual && { ...actual, page });

  return (
    <main className="page-container">
      <PageHeader eyebrow="Finanzas" title="Caja" description="Resumen ejecutivo y detalle de movimientos por período." />
      <FilterBar label="Filtrar movimientos de caja">
        <label className="field-group sm:w-52" htmlFor="caja-desde">Desde<input id="caja-desde" className="form-input" type="date" value={desde} onChange={(event) => setDesde(event.target.value)} /></label>
        <label className="field-group sm:w-52" htmlFor="caja-hasta">Hasta<input id="caja-hasta" className="form-input" type="date" value={hasta} min={desde} onChange={(event) => setHasta(event.target.value)} /></label>
        <Boton type="button" onClick={consultar} disabled={!desde || !hasta || desde > hasta}>Consultar</Boton>
      </FilterBar>
      {resumen.isLoading && <LoadingState message="Consultando caja..." />}
      {resumen.isError && <ErrorState message="No se pudo consultar la caja." onRetry={() => void resumen.refetch()} />}
      {resumen.data && (
        <>
          <section className="stat-grid" aria-label="Resumen de caja">
            <StatCard label="Ingresos" value={`$ ${formatMoney(resumen.data.totalIngresos)}`} detail="Ingresos efectivos del período" />
            <StatCard label="Egresos" value={`$ ${formatMoney(resumen.data.totalEgresos)}`} detail="Egresos efectivos del período" />
            <StatCard label="Saldo" value={`$ ${formatMoney(resumen.data.saldo)}`} detail="Resultado neto del período" />
            <StatCard label="Ajustes" value={`+$ ${formatMoney(resumen.data.ajustesIngreso)}`} detail={`Egresos -$ ${formatMoney(resumen.data.ajustesEgreso)}`} />
          </section>
          <SectionCard title="Ajustes y reversos" description="Movimientos complementarios incluidos en el resumen.">
            <div className="grid gap-3 text-sm sm:grid-cols-2 lg:grid-cols-4">
              <p><span className="block text-xs text-muted-foreground">Ajustes de ingreso</span><strong className="tabular-nums">$ {formatMoney(resumen.data.ajustesIngreso)}</strong></p>
              <p><span className="block text-xs text-muted-foreground">Ajustes de egreso</span><strong className="tabular-nums">$ {formatMoney(resumen.data.ajustesEgreso)}</strong></p>
              <p><span className="block text-xs text-muted-foreground">Reversos de ingreso</span><strong className="tabular-nums">$ {formatMoney(resumen.data.reversosIngreso)}</strong></p>
              <p><span className="block text-xs text-muted-foreground">Reversos de egreso</span><strong className="tabular-nums">$ {formatMoney(resumen.data.reversosEgreso)}</strong></p>
            </div>
          </SectionCard>
          {resumen.data.movimientos.content.length === 0 ? (
            <EmptyState message="No hay movimientos en el período." />
          ) : (
            <div className="page-card"><div className="data-table-scroll">
              <table className="data-table"><thead><tr><th scope="col">Fecha</th><th scope="col">Tipo</th><th scope="col">Importe</th><th scope="col">Origen</th></tr></thead>
                <tbody>{resumen.data.movimientos.content.map((movimiento) => <tr key={movimiento.id}>
                  <td>{movimiento.fecha}</td><td><StatusBadge tone="info">{movimiento.tipo}</StatusBadge></td><td className="numeric-cell">$ {formatMoney(movimiento.importe)}</td>
                  <td>{movimiento.pagoId ? `Pago ${movimiento.pagoId}` : movimiento.egresoId ? `Egreso ${movimiento.egresoId}` : movimiento.motivo}</td>
                </tr>)}</tbody></table></div>
            </div>
          )}
          <PaginationControls
            page={consulta?.page ?? 0}
            totalPages={resumen.data.movimientos.totalPages}
            onPageChange={cambiarPagina}
            disabled={resumen.isFetching}
          />
        </>
      )}
    </main>
  );
}
