import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "react-toastify";
import cargosApi from "../../api/cargosApi";
import metodosPagoApi from "../../api/metodosPagoApi";
import pagosApi from "../../api/pagosApi";
import type { CargoResponse, MetodoPagoResponse, Page } from "../../types/types";
import { queryKeys } from "../../hooks/queryKeys";
import { isPositiveMoney } from "../../utils/money";
import Boton from "../../componentes/comunes/Boton";
import EmptyState from "../../componentes/comunes/EmptyState";
import ErrorState from "../../componentes/comunes/ErrorState";
import LoadingState from "../../componentes/comunes/LoadingState";
import MoneyInput from "../../componentes/comunes/MoneyInput";
import PageHeader from "../../componentes/comunes/PageHeader";
import PaginationControls from "../../componentes/comunes/PaginationControls";
import SectionCard from "../../componentes/comunes/SectionCard";
import { formatMoney } from "../../utils/money";

const PAGE_SIZE = 50;

export default function PagosFormulario() {
  const queryClient = useQueryClient();
  const metodos = useQuery<MetodoPagoResponse[]>({
    queryKey: queryKeys.metodosPago,
    queryFn: metodosPagoApi.listarMetodosPago,
  });
  const [alumnoId, setAlumnoId] = useState(0);
  const [metodoPagoId, setMetodoPagoId] = useState(0);
  const [monto, setMonto] = useState("");
  const [aplicaciones, setAplicaciones] = useState<Record<number, string>>({});
  const [generarCredito, setGenerarCredito] = useState(false);
  const [cargoPage, setCargoPage] = useState(0);
  const [enviando, setEnviando] = useState(false);

  const cargos = useQuery<Page<CargoResponse>>({
    queryKey: queryKeys.cargosPendientes(alumnoId, cargoPage, PAGE_SIZE),
    queryFn: () => cargosApi.listarPendientes(alumnoId, cargoPage, PAGE_SIZE),
    enabled: alumnoId > 0,
  });

  const seleccionadas = useMemo(() => Object.entries(aplicaciones)
    .filter(([, importe]) => isPositiveMoney(importe))
    .map(([cargoId, importe]) => ({ cargoId: Number(cargoId), importe })), [aplicaciones]);

  const registrar = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!alumnoId || !metodoPagoId || !isPositiveMoney(monto)) {
      toast.error("Completá alumno, método e importe con hasta dos decimales");
      return;
    }
    setEnviando(true);
    try {
      const pago = await pagosApi.registrarPago({
        alumnoId,
        metodoPagoId,
        montoRecibido: monto,
        idempotencyKey: crypto.randomUUID(),
        aplicaciones: seleccionadas,
        generarCredito,
      });
      toast.success(`Pago ${pago.id} registrado`);
      setMonto("");
      setAplicaciones({});
      await queryClient.invalidateQueries({ queryKey: ["cargos", "pendientes", alumnoId] });
    } catch {
      toast.error("El backend rechazó el pago; revisá saldos y aplicaciones");
    } finally {
      setEnviando(false);
    }
  };

  return <main className="page-container">
    <PageHeader eyebrow="Cobranza" title="Registrar pago" description="Seleccioná el alumno, el medio de pago y cómo aplicar el importe a sus cargos pendientes." />
    <form onSubmit={registrar} className="grid items-start gap-5 xl:grid-cols-[minmax(0,1.45fr)_minmax(18rem,0.55fr)]">
      <div className="space-y-5">
        <SectionCard title="Datos del pago" description="Los campos marcados son necesarios para continuar.">
          <div className="form-grid lg:grid-cols-3">
            <label className="field-group">Alumno ID
              <input className="form-input" type="number" min="1" value={alumnoId || ""} onChange={(e) => { setCargoPage(0); setAlumnoId(Number(e.target.value)); }} placeholder="Ej. 125" />
              <span className="form-help">Ingresá el identificador del alumno.</span>
            </label>
            <label className="field-group">Método de pago
              <select className="form-input" value={metodoPagoId} onChange={(e) => setMetodoPagoId(Number(e.target.value))}>
                <option value={0}>Seleccionar método</option>
                {(metodos.data ?? []).filter((method) => method.activo)
                  .map((m) => <option key={m.id} value={m.id}>{m.descripcion}</option>)}
              </select>
            </label>
            <MoneyInput id="monto-recibido" label="Monto recibido" value={monto} onChange={setMonto} required />
          </div>
        </SectionCard>

        <SectionCard title="Aplicación a cargos" description={alumnoId > 0 ? "Distribuí el importe entre los cargos pendientes." : "Ingresá un alumno para consultar sus cargos."}>
          {!alumnoId && <EmptyState title="Seleccioná un alumno" message="Cuando ingreses un ID válido, sus cargos pendientes aparecerán acá." />}
          {cargos.isLoading && <LoadingState message="Cargando cargos pendientes..." />}
          {cargos.isError && <ErrorState message="No se pudieron cargar los cargos del alumno." onRetry={() => void cargos.refetch()} />}
          {cargos.data?.content.length === 0 && <EmptyState title="Sin cargos pendientes" message="Este alumno no tiene cargos disponibles para aplicar." />}
          {cargos.data && cargos.data.content.length > 0 && <div className="space-y-3">
            {cargos.data.content.map((cargo) => <div key={cargo.id} className="grid gap-3 rounded-xl border border-border bg-muted/35 p-3 sm:grid-cols-[minmax(0,1fr)_12rem] sm:items-center">
              <div className="min-w-0">
                <p className="truncate text-sm font-semibold">{cargo.descripcion}</p>
                <p className="mt-1 text-xs text-muted-foreground">Saldo pendiente <span className="font-bold text-foreground">$ {formatMoney(cargo.saldo)}</span></p>
              </div>
              <label className="field-group"><span className="sr-only">Aplicar a {cargo.descripcion}</span>
                <input className="form-input text-right tabular-nums" aria-label={`Aplicar a ${cargo.descripcion}`} inputMode="decimal"
                  value={aplicaciones[cargo.id] ?? ""}
                  onChange={(e) => setAplicaciones((current) => ({ ...current, [cargo.id]: e.target.value }))}
                  placeholder="$ 0.00" />
              </label>
            </div>)}
            <PaginationControls page={cargoPage} totalPages={cargos.data.totalPages} onPageChange={setCargoPage} disabled={cargos.isFetching} />
          </div>}
        </SectionCard>
      </div>

      <SectionCard title="Confirmación" description="Revisá la configuración antes de registrar." className="xl:sticky xl:top-[calc(var(--header-height)+1.5rem)]">
        <dl className="space-y-3 text-sm">
          <div className="flex items-center justify-between gap-4"><dt className="text-muted-foreground">Alumno</dt><dd className="font-semibold">{alumnoId || "Sin seleccionar"}</dd></div>
          <div className="flex items-center justify-between gap-4"><dt className="text-muted-foreground">Cargos aplicados</dt><dd className="font-semibold">{seleccionadas.length}</dd></div>
        </dl>
        <label className="mt-5 flex cursor-pointer items-start gap-3 rounded-xl border border-border bg-muted/35 p-3 text-sm">
          <input className="mt-0.5 size-4 accent-[hsl(var(--primary))]" type="checkbox" checked={generarCredito} onChange={(e) => setGenerarCredito(e.target.checked)} />
          <span><strong className="block font-semibold">Generar crédito con el excedente</strong><span className="mt-1 block text-xs leading-5 text-muted-foreground">El backend validará el excedente y la aplicación final.</span></span>
        </label>
        <Boton type="submit" className="page-button mt-5 w-full" disabled={enviando}>{enviando ? "Registrando…" : "Registrar pago"}</Boton>
      </SectionCard>
    </form>
  </main>;
}
