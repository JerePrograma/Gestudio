import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { toast } from "react-toastify";
import alumnosApi from "../../api/alumnosApi";
import { getApiErrorMessage } from "../../api/apiError";
import cargosApi from "../../api/cargosApi";
import metodosPagoApi from "../../api/metodosPagoApi";
import pagosApi from "../../api/pagosApi";
import type { AlumnoResponse, CargoResponse, MetodoPagoResponse, Page } from "../../types/types";
import { queryKeys } from "../../hooks/queryKeys";
import { formatMoney, isPositiveMoney, normalizeMoneyInput } from "../../utils/money";
import Boton from "../../componentes/comunes/Boton";
import EmptyState from "../../componentes/comunes/EmptyState";
import ErrorState from "../../componentes/comunes/ErrorState";
import LoadingState from "../../componentes/comunes/LoadingState";
import MoneyInput from "../../componentes/comunes/MoneyInput";
import PageHeader from "../../componentes/comunes/PageHeader";
import PaginationControls from "../../componentes/comunes/PaginationControls";
import SectionCard from "../../componentes/comunes/SectionCard";

const PAGE_SIZE = 50;
const ALUMNOS_SEARCH_SIZE = 8;
const MIN_ALUMNO_SEARCH_LENGTH = 2;

const nombreCompletoAlumno = (alumno: AlumnoResponse): string =>
  [alumno.nombre, alumno.apellido].filter(Boolean).join(" ").trim();

const detalleAlumno = (alumno: AlumnoResponse): string => {
  const partes = [
    alumno.documento ? `DNI ${alumno.documento}` : null,
    alumno.celular1 || null,
    alumno.email || null,
  ].filter(Boolean);

  return partes.length > 0 ? partes.join(" · ") : "Sin datos de contacto cargados";
};

const centsFromMoney = (value: string): number | null => {
  const normalized = normalizeMoneyInput(value);
  if (normalized === null) return null;

  const [integer, decimal] = normalized.split(".");
  return Number(integer) * 100 + Number(decimal);
};

const moneyFromCents = (cents: number): string => {
  const absolute = Math.abs(cents);
  const integer = Math.trunc(absolute / 100);
  const decimal = String(absolute % 100).padStart(2, "0");

  return `${integer}.${decimal}`;
};

const formatCents = (cents: number): string =>
  `$ ${formatMoney(moneyFromCents(cents))}`;

export default function PagosFormulario() {
  const queryClient = useQueryClient();

  const [busquedaAlumno, setBusquedaAlumno] = useState("");
  const [alumnoSeleccionado, setAlumnoSeleccionado] = useState<AlumnoResponse | null>(null);
  const [metodoPagoId, setMetodoPagoId] = useState(0);
  const [monto, setMonto] = useState("");
  const [aplicaciones, setAplicaciones] = useState<Record<number, string>>({});
  const [generarCredito, setGenerarCredito] = useState(false);
  const [cargoPage, setCargoPage] = useState(0);
  const [enviando, setEnviando] = useState(false);

  const alumnoId = alumnoSeleccionado?.id ?? 0;
  const busquedaAlumnoNormalizada = busquedaAlumno.trim();

  const metodos = useQuery<MetodoPagoResponse[]>({
    queryKey: queryKeys.metodosPago,
    queryFn: metodosPagoApi.listarMetodosPago,
  });

  const alumnos = useQuery<Page<AlumnoResponse>>({
    queryKey: queryKeys.alumnosBusqueda(busquedaAlumnoNormalizada, 0, ALUMNOS_SEARCH_SIZE),
    queryFn: () => alumnosApi.buscarPorNombre(busquedaAlumnoNormalizada, 0, ALUMNOS_SEARCH_SIZE),
    enabled: alumnoSeleccionado === null && busquedaAlumnoNormalizada.length >= MIN_ALUMNO_SEARCH_LENGTH,
  });

  const cargos = useQuery<Page<CargoResponse>>({
    queryKey: queryKeys.cargosPendientes(alumnoId, cargoPage, PAGE_SIZE),
    queryFn: () => cargosApi.listarPendientes(alumnoId, cargoPage, PAGE_SIZE),
    enabled: alumnoId > 0,
  });

  const seleccionadas = useMemo(() => Object.entries(aplicaciones)
    .map(([cargoId, importe]) => {
      const normalizado = normalizeMoneyInput(importe);
      if (normalizado === null || normalizado === "0.00") return null;

      return { cargoId: Number(cargoId), importe: normalizado };
    })
    .filter((aplicacion): aplicacion is { cargoId: number; importe: string } => aplicacion !== null), [aplicaciones]);

  const totalAplicadoCents = useMemo(() => seleccionadas.reduce((total, aplicacion) => {
    const cents = centsFromMoney(aplicacion.importe);
    return total + (cents ?? 0);
  }, 0), [seleccionadas]);

  const montoCents = centsFromMoney(monto);
  const excedenteCents = montoCents === null ? null : montoCents - totalAplicadoCents;
  const hayExcedente = excedenteCents !== null && excedenteCents > 0;

  const seleccionarAlumno = (alumno: AlumnoResponse) => {
    setAlumnoSeleccionado(alumno);
    setBusquedaAlumno(nombreCompletoAlumno(alumno));
    setCargoPage(0);
    setAplicaciones({});
  };

  const limpiarAlumno = () => {
    setAlumnoSeleccionado(null);
    setBusquedaAlumno("");
    setCargoPage(0);
    setAplicaciones({});
  };

  const cambiarBusquedaAlumno = (value: string) => {
    setAlumnoSeleccionado(null);
    setBusquedaAlumno(value);
    setCargoPage(0);
    setAplicaciones({});
  };

  const normalizarAplicacion = (cargoId: number, value: string) => {
    const normalizado = normalizeMoneyInput(value);
    if (normalizado === null) return;

    setAplicaciones((current) => ({ ...current, [cargoId]: normalizado }));
  };

  const registrar = async (event: React.FormEvent) => {
    event.preventDefault();

    const montoNormalizado = normalizeMoneyInput(monto);

    if (!alumnoId || !metodoPagoId || montoNormalizado === null || !isPositiveMoney(montoNormalizado)) {
      toast.error("Completá alumno, método e importe con hasta dos decimales");
      return;
    }

    setEnviando(true);
    try {
      const pago = await pagosApi.registrarPago({
        alumnoId,
        metodoPagoId,
        montoRecibido: montoNormalizado,
        idempotencyKey: crypto.randomUUID(),
        aplicaciones: seleccionadas,
        generarCredito,
      });

      toast.success(`Pago ${pago.id} registrado`);
      setMonto("");
      setAplicaciones({});
      await queryClient.invalidateQueries({ queryKey: ["cargos", "pendientes", alumnoId] });
    } catch (error) {
      toast.error(getApiErrorMessage(error, "El backend rechazó el pago; revisá saldos y aplicaciones"));
    } finally {
      setEnviando(false);
    }
  };

  return <main className="page-container">
    <PageHeader eyebrow="Cobranza" title="Registrar pago" description="Buscá el alumno, seleccioná el medio de pago y aplicá el importe a sus cargos pendientes." />
    <form onSubmit={registrar} className="grid items-start gap-5 xl:grid-cols-[minmax(0,1.45fr)_minmax(18rem,0.55fr)]">
      <div className="space-y-5">
        <SectionCard title="Datos del pago" description="Los campos marcados son necesarios para continuar.">
          <div className="form-grid lg:grid-cols-3">
            <div className="field-group lg:col-span-3">
              <label htmlFor="buscar-alumno-pago">Alumno</label>
              <div className="flex flex-col gap-2 sm:flex-row">
                <input
                  id="buscar-alumno-pago"
                  className="form-input"
                  type="search"
                  autoComplete="off"
                  value={busquedaAlumno}
                  onChange={(event) => cambiarBusquedaAlumno(event.target.value)}
                  placeholder="Buscar por nombre o apellido"
                />
                {alumnoSeleccionado && (
                  <Boton type="button" secondary onClick={limpiarAlumno} className="shrink-0">
                    Cambiar
                  </Boton>
                )}
              </div>
              <span className="form-help">Buscá el alumno por nombre o apellido. El ID queda sólo para uso interno del sistema.</span>

              {!alumnoSeleccionado && busquedaAlumnoNormalizada.length > 0 && busquedaAlumnoNormalizada.length < MIN_ALUMNO_SEARCH_LENGTH && (
                <p className="text-xs text-muted-foreground">Escribí al menos {MIN_ALUMNO_SEARCH_LENGTH} caracteres para buscar.</p>
              )}

              {!alumnoSeleccionado && alumnos.isLoading && (
                <LoadingState message="Buscando alumnos..." />
              )}

              {!alumnoSeleccionado && alumnos.isError && (
                <ErrorState message="No se pudieron buscar alumnos." onRetry={() => void alumnos.refetch()} />
              )}

              {!alumnoSeleccionado && alumnos.data?.content.length === 0 && (
                <EmptyState title="Sin resultados" message="No se encontraron alumnos con esa búsqueda." />
              )}

              {!alumnoSeleccionado && alumnos.data && alumnos.data.content.length > 0 && (
                <div className="mt-3 space-y-2">
                  {alumnos.data.content.map((alumno) => (
                    <button
                      key={alumno.id}
                      type="button"
                      disabled={!alumno.activo}
                      aria-label={`Seleccionar ${nombreCompletoAlumno(alumno)}`}
                      onClick={() => seleccionarAlumno(alumno)}
                      className="w-full rounded-xl border border-border bg-card p-3 text-left transition hover:border-primary hover:bg-muted/50 disabled:cursor-not-allowed disabled:opacity-60"
                    >
                      <span className="flex flex-wrap items-center justify-between gap-2">
                        <span className="font-semibold">{nombreCompletoAlumno(alumno)}</span>
                        <span className="rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground">
                          {alumno.activo ? "Activo" : "Baja"}
                        </span>
                      </span>
                      <span className="mt-1 block text-xs text-muted-foreground">{detalleAlumno(alumno)}</span>
                    </button>
                  ))}
                </div>
              )}

              {alumnoSeleccionado && (
                <div className="mt-3 rounded-xl border border-border bg-muted/35 p-3">
                  <p className="text-sm font-semibold">{nombreCompletoAlumno(alumnoSeleccionado)}</p>
                  <p className="mt-1 text-xs text-muted-foreground">{detalleAlumno(alumnoSeleccionado)}</p>
                </div>
              )}
            </div>

            <label className="field-group">Método de pago
              <select
                className="form-input"
                value={metodoPagoId}
                onChange={(e) => setMetodoPagoId(Number(e.target.value))}
                disabled={metodos.isLoading}
              >
                <option value={0}>{metodos.isLoading ? "Cargando métodos..." : "Seleccionar método"}</option>
                {(metodos.data ?? []).filter((method) => method.activo)
                  .map((m) => <option key={m.id} value={m.id}>{m.descripcion}</option>)}
              </select>
              {metodos.isError && <span className="form-help text-destructive">No se pudieron cargar los métodos de pago.</span>}
            </label>

            <MoneyInput id="monto-recibido" label="Monto recibido" value={monto} onChange={setMonto} required />
          </div>
        </SectionCard>

        <SectionCard title="Aplicación a cargos" description={alumnoSeleccionado ? "Distribuí el importe entre los cargos pendientes." : "Seleccioná un alumno para consultar sus cargos."}>
          {!alumnoSeleccionado && <EmptyState title="Seleccioná un alumno" message="Cuando elijas un alumno, sus cargos pendientes aparecerán acá." />}
          {cargos.isLoading && <LoadingState message="Cargando cargos pendientes..." />}
          {cargos.isError && <ErrorState message="No se pudieron cargar los cargos del alumno." onRetry={() => void cargos.refetch()} />}
          {cargos.data?.content.length === 0 && <EmptyState title="Sin cargos pendientes" message="Este alumno no tiene cargos disponibles para aplicar." />}
          {cargos.data && cargos.data.content.length > 0 && <div className="space-y-3">
            {cargos.data.content.map((cargo) => <div key={cargo.id} className="grid gap-3 rounded-xl border border-border bg-muted/35 p-3 sm:grid-cols-[minmax(0,1fr)_12rem] sm:items-center">
              <div className="min-w-0">
                <p className="truncate text-sm font-semibold">{cargo.descripcion}</p>
                <p className="mt-1 text-xs text-muted-foreground">
                  Saldo pendiente <span className="font-bold text-foreground">$ {formatMoney(cargo.saldo)}</span>
                </p>
                <p className="mt-1 text-xs text-muted-foreground">
                  {cargo.tipo} · Vence {cargo.fechaVencimiento}
                </p>
              </div>
              <label className="field-group"><span className="sr-only">Aplicar a {cargo.descripcion}</span>
                <input
                  className="form-input text-right tabular-nums"
                  aria-label={`Aplicar a ${cargo.descripcion}`}
                  inputMode="decimal"
                  value={aplicaciones[cargo.id] ?? ""}
                  onChange={(e) => setAplicaciones((current) => ({ ...current, [cargo.id]: e.target.value }))}
                  onBlur={(e) => normalizarAplicacion(cargo.id, e.target.value)}
                  placeholder="$ 0.00"
                />
              </label>
            </div>)}
            <PaginationControls page={cargoPage} totalPages={cargos.data.totalPages} onPageChange={setCargoPage} disabled={cargos.isFetching} />
          </div>}
        </SectionCard>
      </div>

      <SectionCard title="Confirmación" description="Revisá la configuración antes de registrar." className="xl:sticky xl:top-[calc(var(--header-height)+1.5rem)]">
        <dl className="space-y-3 text-sm">
          <div className="flex items-center justify-between gap-4">
            <dt className="text-muted-foreground">Alumno</dt>
            <dd className="text-right font-semibold">{alumnoSeleccionado ? nombreCompletoAlumno(alumnoSeleccionado) : "Sin seleccionar"}</dd>
          </div>
          <div className="flex items-center justify-between gap-4">
            <dt className="text-muted-foreground">Cargos aplicados</dt>
            <dd className="font-semibold">{seleccionadas.length}</dd>
          </div>
          <div className="flex items-center justify-between gap-4">
            <dt className="text-muted-foreground">Total aplicado</dt>
            <dd className="font-semibold">{formatCents(totalAplicadoCents)}</dd>
          </div>
          <div className="flex items-center justify-between gap-4">
            <dt className="text-muted-foreground">Excedente</dt>
            <dd className="text-right font-semibold">
              {excedenteCents === null
                ? "Sin calcular"
                : excedenteCents >= 0
                  ? formatCents(excedenteCents)
                  : `Aplicado de más ${formatCents(Math.abs(excedenteCents))}`}
            </dd>
          </div>
        </dl>

        {hayExcedente && !generarCredito && (
          <div className="mt-5 rounded-xl border border-border bg-muted/35 p-3 text-xs leading-5 text-muted-foreground">
            Hay un excedente sin marcar como crédito. El backend rechazará el pago si el importe recibido supera lo aplicado y no autorizás generar crédito.
          </div>
        )}

        <label className="mt-5 flex cursor-pointer items-start gap-3 rounded-xl border border-border bg-muted/35 p-3 text-sm">
          <input className="mt-0.5 size-4 accent-[hsl(var(--primary))]" type="checkbox" checked={generarCredito} onChange={(e) => setGenerarCredito(e.target.checked)} />
          <span><strong className="block font-semibold">Generar crédito con el excedente</strong><span className="mt-1 block text-xs leading-5 text-muted-foreground">El backend validará el excedente y la aplicación final.</span></span>
        </label>

        <Boton type="submit" className="page-button mt-5 w-full" disabled={enviando || metodos.isLoading}>
          {enviando ? "Registrando…" : "Registrar pago"}
        </Boton>
      </SectionCard>
    </form>
  </main>;
}