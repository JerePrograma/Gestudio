import { useEffect, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { useSearchParams } from "react-router-dom";
import { toast } from "react-toastify";
import alumnosApi from "../../api/alumnosApi";
import { getApiErrorMessage } from "../../api/apiError";
import pagosApi from "../../api/pagosApi";
import Boton from "../../componentes/comunes/Boton";
import EmptyState from "../../componentes/comunes/EmptyState";
import ErrorState from "../../componentes/comunes/ErrorState";
import LoadingState from "../../componentes/comunes/LoadingState";
import PaginationControls from "../../componentes/comunes/PaginationControls";
import { queryKeys } from "../../hooks/queryKeys";
import type { AlumnoResponse, Page, PagoResumenResponse } from "../../types/types";
import { formatMoney } from "../../utils/money";
import FilterBar from "../../componentes/comunes/FilterBar";
import PageHeader from "../../componentes/comunes/PageHeader";
import RowActions from "../../componentes/comunes/RowActions";
import StatusBadge from "../../componentes/comunes/StatusBadge";
import { Ban, Download } from "lucide-react";

const PAGE_SIZE = 50;
const ALUMNOS_SEARCH_SIZE = 8;
const MIN_ALUMNO_SEARCH_LENGTH = 2;

const positiveId = (value: string | null): number => {
  const id = Number(value);
  return Number.isInteger(id) && id > 0 ? id : 0;
};

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

export default function PagosPagina() {
  const [searchParams] = useSearchParams();
  const initialAlumnoId = positiveId(searchParams.get("alumnoId"));

  const [busquedaAlumno, setBusquedaAlumno] = useState("");
  const [alumnoSeleccionado, setAlumnoSeleccionado] = useState<AlumnoResponse | null>(null);
  const [consultaId, setConsultaId] = useState(initialAlumnoId);
  const [page, setPage] = useState(0);

  const queryClient = useQueryClient();
  const busquedaAlumnoNormalizada = busquedaAlumno.trim();

  const alumnoInicial = useQuery<AlumnoResponse>({
    queryKey: queryKeys.alumno(initialAlumnoId),
    queryFn: () => alumnosApi.obtenerPorId(initialAlumnoId),
    enabled: initialAlumnoId > 0,
  });

  useEffect(() => {
    if (!alumnoInicial.data || consultaId !== initialAlumnoId) return;

    setAlumnoSeleccionado(alumnoInicial.data);
    setBusquedaAlumno(nombreCompletoAlumno(alumnoInicial.data));
  }, [alumnoInicial.data, consultaId, initialAlumnoId]);

  const alumnos = useQuery<Page<AlumnoResponse>>({
    queryKey: queryKeys.alumnosBusqueda(busquedaAlumnoNormalizada, 0, ALUMNOS_SEARCH_SIZE),
    queryFn: () => alumnosApi.buscarPorNombre(busquedaAlumnoNormalizada, 0, ALUMNOS_SEARCH_SIZE),
    enabled: alumnoSeleccionado === null && busquedaAlumnoNormalizada.length >= MIN_ALUMNO_SEARCH_LENGTH,
  });

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

  const seleccionarAlumno = (alumno: AlumnoResponse) => {
    setAlumnoSeleccionado(alumno);
    setBusquedaAlumno(nombreCompletoAlumno(alumno));
    setPage(0);
    setConsultaId(alumno.id);
  };

  const limpiarAlumno = () => {
    setAlumnoSeleccionado(null);
    setBusquedaAlumno("");
    setPage(0);
    setConsultaId(0);
  };

  const cambiarBusquedaAlumno = (value: string) => {
    setAlumnoSeleccionado(null);
    setBusquedaAlumno(value);
    setPage(0);
    setConsultaId(0);
  };

  const buscar = (event: React.FormEvent) => {
    event.preventDefault();

    if (!alumnoSeleccionado) {
      toast.error("Seleccioná un alumno de la lista para consultar sus pagos.");
      return;
    }

    setPage(0);
    setConsultaId(alumnoSeleccionado.id);
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
      <PageHeader
        eyebrow="Cobranza"
        title="Pagos"
        description="Consultá recibos, estado y trazabilidad por alumno."
        count={pagos.data?.totalElements}
      />

      <FilterBar label="Consultar pagos">
        <form onSubmit={buscar} className="flex w-full flex-col gap-3 sm:flex-row sm:items-end">
          <div className="field-group min-w-0 sm:w-96">
            <label htmlFor="pagos-buscar-alumno">Alumno</label>
            <div className="flex flex-col gap-2 sm:flex-row">
              <input
                id="pagos-buscar-alumno"
                type="search"
                autoComplete="off"
                className="form-input"
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

            {alumnoInicial.isLoading && consultaId > 0 && !alumnoSeleccionado && (
              <p className="text-xs text-muted-foreground">Cargando alumno del enlace...</p>
            )}

            {alumnoInicial.isError && consultaId > 0 && !alumnoSeleccionado && (
              <p className="text-xs text-destructive">No se pudo cargar el nombre del alumno del enlace.</p>
            )}

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

          <Boton type="submit" disabled={!alumnoSeleccionado || alumnoSeleccionado.id === consultaId}>
            Consultar pagos
          </Boton>
        </form>
      </FilterBar>

      {!consultaId && (
        <EmptyState title="Seleccioná un alumno" message="Cuando elijas un alumno, sus pagos registrados aparecerán acá." />
      )}

      {pagos.isLoading && <LoadingState message="Cargando pagos..." />}
      {pagos.isError && <ErrorState message="No se pudieron cargar los pagos." onRetry={() => void pagos.refetch()} />}
      {pagos.data && pagos.data.content.length === 0 && <EmptyState message="El alumno no tiene pagos registrados." />}

      {pagos.data && pagos.data.content.length > 0 && (
        <div className="page-card">
          <div className="data-table-scroll">
            <table className="data-table">
              <thead>
                <tr>
                  <th scope="col">ID</th>
                  <th scope="col">Fecha</th>
                  <th scope="col">Monto</th>
                  <th scope="col">Estado</th>
                  <th scope="col">Acciones</th>
                </tr>
              </thead>
              <tbody>
                {pagos.data.content.map((pago) => (
                  <tr key={pago.id}>
                    <td>{pago.id}</td>
                    <td>{pago.fecha}</td>
                    <td className="numeric-cell">$ {formatMoney(pago.montoRecibido)}</td>
                    <td>
                      <StatusBadge tone={pago.estado === "REGISTRADO" ? "success" : "neutral"}>
                        {pago.estado}
                      </StatusBadge>
                    </td>
                    <td>
                      <div className="row-actions">
                        <RowActions
                          label={`Acciones del pago ${pago.id}`}
                          actions={[
                            { label: "Descargar recibo", icon: Download, onSelect: () => void descargar(pago.id) },
                            ...(pago.estado === "REGISTRADO"
                              ? [{ label: "Anular pago", icon: Ban, destructive: true, disabled: anulacion.isPending, onSelect: () => anular(pago) }]
                              : []),
                          ]}
                        />
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {pagos.data && (
        <PaginationControls page={page} totalPages={pagos.data.totalPages} onPageChange={setPage} disabled={pagos.isFetching} />
      )}
    </main>
  );
}