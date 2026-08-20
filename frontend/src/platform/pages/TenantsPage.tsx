import { useQuery } from "@tanstack/react-query";
import { ArrowRight, Building2, PlusCircle } from "lucide-react";
import { useState } from "react";
import { useNavigate } from "react-router";
import Boton from "../../componentes/comunes/Boton";
import ErrorState from "../../componentes/comunes/ErrorState";
import FilterBar from "../../componentes/comunes/FilterBar";
import LoadingState from "../../componentes/comunes/LoadingState";
import PageHeader from "../../componentes/comunes/PageHeader";
import PaginationControls from "../../componentes/comunes/PaginationControls";
import SearchInput from "../../componentes/comunes/SearchInput";
import StatusBadge from "../../componentes/comunes/StatusBadge";
import Tabla from "../../componentes/comunes/Tabla";
import useDebounce from "../../hooks/useDebounce";
import { getApiErrorMessage } from "../../api/apiError";
import { platformApi } from "../platformApi";
import type { PlatformTenantStatus, PlatformTenantSummary } from "../platformTypes";

const statusLabel: Record<PlatformTenantStatus, string> = {
  ACTIVE: "Activa",
  SUSPENDED: "Suspendida",
  ARCHIVED: "Archivada",
};

const statusTone = (status: PlatformTenantStatus) =>
  status === "ACTIVE" ? "success" : status === "SUSPENDED" ? "warning" : "neutral";

const TenantsPage = () => {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<PlatformTenantStatus | "">("");
  const [page, setPage] = useState(0);
  const debouncedQuery = useDebounce(query, 300);
  const navigate = useNavigate();
  const tenants = useQuery({
    queryKey: ["PLATFORM", "tenants", page, debouncedQuery.trim(), status],
    queryFn: () => platformApi.listTenants({ page, size: 25, q: debouncedQuery.trim(), status }),
  });

  const changeQuery = (value: string) => {
    setQuery(value);
    setPage(0);
  };

  const changeStatus = (value: PlatformTenantStatus | "") => {
    setStatus(value);
    setPage(0);
  };

  if (tenants.isPending) return <LoadingState message="Cargando organizaciones..." />;
  if (tenants.isError) {
    return <ErrorState message={getApiErrorMessage(tenants.error, "No se pudieron cargar las organizaciones.")} onRetry={() => void tenants.refetch()} />;
  }

  return (
    <div className="page-container">
      <PageHeader
        eyebrow="Control plane"
        title="Organizaciones"
        description="Administrá el ciclo de vida y los accesos de cada organización sin ingresar a sus datos de negocio."
        count={tenants.data.totalElements}
        actions={(
          <Boton onClick={() => navigate("/platform/tenants/new")}>
            <PlusCircle className="size-4" aria-hidden="true" />
            Nueva organización
          </Boton>
        )}
      />

      <FilterBar label="Filtrar organizaciones">
        <SearchInput
          id="tenant-search"
          label="Buscar por nombre o código"
          placeholder="Buscar por nombre o código"
          value={query}
          onChange={(event) => changeQuery(event.target.value)}
        />
        <label className="field-group sm:min-w-48" htmlFor="tenant-status">
          <span>Estado</span>
          <select
            id="tenant-status"
            className="form-select"
            value={status}
            onChange={(event) => changeStatus(event.target.value as PlatformTenantStatus | "")}
          >
            <option value="">Todos</option>
            <option value="ACTIVE">Activas</option>
            <option value="SUSPENDED">Suspendidas</option>
            <option value="ARCHIVED">Archivadas</option>
          </select>
        </label>
      </FilterBar>

      <Tabla<PlatformTenantSummary>
        headers={["Organización", "Código", "Estado", "Membresías", "Acciones"]}
        data={tenants.data.content}
        getRowKey={(tenant) => tenant.id}
        emptyMessage="No hay organizaciones que coincidan con los filtros."
        customRender={(tenant) => [
          <span className="flex items-center gap-2 font-semibold" key="name"><Building2 className="size-4 text-primary" aria-hidden="true" />{tenant.name}</span>,
          <code key="code" className="rounded bg-muted px-2 py-1 text-xs">{tenant.code}</code>,
          <StatusBadge key="status" tone={statusTone(tenant.status)}>{statusLabel[tenant.status]}</StatusBadge>,
          tenant.membershipCount ?? "—",
        ]}
        actions={(tenant) => (
          <Boton className="page-button-secondary" onClick={() => navigate(`/platform/tenants/${tenant.id}`)} aria-label={`Ver ${tenant.name}`}>
            Ver detalle <ArrowRight className="size-4" aria-hidden="true" />
          </Boton>
        )}
      />

      <PaginationControls
        page={tenants.data.number}
        totalPages={tenants.data.totalPages}
        onPageChange={setPage}
        disabled={tenants.isFetching}
      />
    </div>
  );
};

export default TenantsPage;
