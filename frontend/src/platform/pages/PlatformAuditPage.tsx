import { useQuery } from "@tanstack/react-query";
import { FileSearch } from "lucide-react";
import { useState } from "react";
import { useSearchParams } from "react-router";
import { getApiErrorMessage } from "../../api/apiError";
import ErrorState from "../../componentes/comunes/ErrorState";
import FilterBar from "../../componentes/comunes/FilterBar";
import LoadingState from "../../componentes/comunes/LoadingState";
import PageHeader from "../../componentes/comunes/PageHeader";
import PaginationControls from "../../componentes/comunes/PaginationControls";
import StatusBadge from "../../componentes/comunes/StatusBadge";
import Tabla from "../../componentes/comunes/Tabla";
import useDebounce from "../../hooks/useDebounce";
import { platformApi } from "../platformApi";
import type { AuditResult, PlatformAuditEvent } from "../platformTypes";

const PlatformAuditPage = () => {
  const [searchParams] = useSearchParams();
  const [page, setPage] = useState(0);
  const [tenantId, setTenantId] = useState(() => searchParams.get("tenantId") ?? "");
  const [actor, setActor] = useState("");
  const [action, setAction] = useState("");
  const [result, setResult] = useState<AuditResult | "">("");
  const [from, setFrom] = useState("");
  const [to, setTo] = useState("");
  const [correlationId, setCorrelationId] = useState("");
  const debouncedTenantId = useDebounce(tenantId, 300);
  const debouncedActor = useDebounce(actor, 300);
  const debouncedAction = useDebounce(action, 300);
  const debouncedCorrelationId = useDebounce(correlationId, 300);
  const audit = useQuery({
    queryKey: ["PLATFORM", "audit", page, debouncedTenantId, debouncedActor, debouncedAction, result, from, to, debouncedCorrelationId],
    queryFn: () => platformApi.listAudit({
      page,
      size: 25,
      tenantId: debouncedTenantId.trim(),
      actor: debouncedActor.trim(),
      action: debouncedAction.trim(),
      result,
      from: from ? new Date(from).toISOString() : undefined,
      to: to ? new Date(to).toISOString() : undefined,
      correlationId: debouncedCorrelationId.trim(),
    }),
  });

  const resetPage = () => setPage(0);
  if (audit.isPending) return <LoadingState message="Cargando auditoría de plataforma..." />;
  if (audit.isError) return <ErrorState message={getApiErrorMessage(audit.error, "No se pudo consultar la auditoría.")} onRetry={() => void audit.refetch()} />;

  return (
    <div className="page-container">
      <PageHeader eyebrow="Trazabilidad" title="Auditoría de plataforma" description="Eventos correlacionados de acceso, autorización y mutaciones del control plane." count={audit.data.totalElements} />
      <FilterBar label="Filtrar auditoría">
        <label className="field-group sm:min-w-48" htmlFor="audit-actor">Actor
          <input id="audit-actor" className="form-input" value={actor} onChange={(event) => { setActor(event.target.value); resetPage(); }} placeholder="Usuario o ID" />
        </label>
        <label className="field-group sm:min-w-48" htmlFor="audit-action">Acción
          <input id="audit-action" className="form-input" value={action} onChange={(event) => { setAction(event.target.value); resetPage(); }} placeholder="TENANT_CREATE" />
        </label>
        <label className="field-group sm:min-w-48" htmlFor="audit-result">Resultado
          <select id="audit-result" className="form-select" value={result} onChange={(event) => { setResult(event.target.value as AuditResult | ""); resetPage(); }}>
            <option value="">Todos</option><option value="SUCCESS">Exitoso</option><option value="DENIED">Denegado</option><option value="FAILED">Fallido</option>
          </select>
        </label>
        <label className="field-group sm:min-w-56" htmlFor="audit-tenant">Tenant ID
          <input id="audit-tenant" className="form-input" value={tenantId} onChange={(event) => { setTenantId(event.target.value); resetPage(); }} />
        </label>
        <label className="field-group" htmlFor="audit-from">Desde
          <input id="audit-from" className="form-input" type="datetime-local" value={from} onChange={(event) => { setFrom(event.target.value); resetPage(); }} />
        </label>
        <label className="field-group" htmlFor="audit-to">Hasta
          <input id="audit-to" className="form-input" type="datetime-local" value={to} onChange={(event) => { setTo(event.target.value); resetPage(); }} />
        </label>
        <label className="field-group sm:min-w-64" htmlFor="audit-correlation">Correlation ID
          <input id="audit-correlation" className="form-input" value={correlationId} onChange={(event) => { setCorrelationId(event.target.value); resetPage(); }} />
        </label>
      </FilterBar>

      <Tabla<PlatformAuditEvent>
        headers={["Fecha", "Actor", "Acción", "Resultado", "Objetivo", "Correlación"]}
        data={audit.data.content}
        getRowKey={(event) => event.id}
        emptyMessage="No hay eventos que coincidan con los filtros."
        customRender={(event) => [
          new Date(event.occurredAt).toLocaleString(),
          event.actorUsername ?? (event.actorId ? `ID ${event.actorId}` : "Sistema"),
          <span key="action" className="flex items-center gap-2 font-medium"><FileSearch className="size-4 text-primary" />{event.action}</span>,
          <StatusBadge key="result" tone={event.result === "SUCCESS" ? "success" : event.result === "DENIED" ? "warning" : "danger"}>
            {event.result === "SUCCESS" ? "Exitoso" : event.result === "DENIED" ? "Denegado" : "Fallido"}
          </StatusBadge>,
          event.targetType ? `${event.targetType}${event.targetId ? ` · ${event.targetId}` : ""}` : "—",
          <code key="correlation" className="text-xs">{event.correlationId}</code>,
        ]}
      />
      <PaginationControls page={audit.data.number} totalPages={audit.data.totalPages} onPageChange={setPage} disabled={audit.isFetching} />
    </div>
  );
};

export default PlatformAuditPage;
