import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Archive, CheckCircle2, Pencil, PlusCircle, ShieldOff, UserRoundCog } from "lucide-react";
import { useEffect, useRef, useState, type FormEvent, type KeyboardEvent } from "react";
import { Link, useParams } from "react-router";
import { getApiErrorMessage } from "../../api/apiError";
import Boton from "../../componentes/comunes/Boton";
import ErrorState from "../../componentes/comunes/ErrorState";
import FilterBar from "../../componentes/comunes/FilterBar";
import LoadingState from "../../componentes/comunes/LoadingState";
import PageHeader from "../../componentes/comunes/PageHeader";
import PaginationControls from "../../componentes/comunes/PaginationControls";
import SearchInput from "../../componentes/comunes/SearchInput";
import SectionCard from "../../componentes/comunes/SectionCard";
import StatusBadge from "../../componentes/comunes/StatusBadge";
import Tabla from "../../componentes/comunes/Tabla";
import useDebounce from "../../hooks/useDebounce";
import ConfirmDialog from "../ConfirmDialog";
import OneTimeActivationNotice from "../OneTimeActivationNotice";
import { newIdempotencyKey, platformApi } from "../platformApi";
import type {
  ActivationDelivery,
  MembershipStatus,
  PlatformAuditEvent,
  PlatformMembership,
  PlatformTenantStatus,
  StepUpDescriptor,
  StepUpHeaders,
} from "../platformTypes";
import { useStepUp } from "../stepUpContext";

type DetailTab = "general" | "memberships" | "audit";

const detailTabs: readonly { value: DetailTab; label: string }[] = [
  { value: "general", label: "General" },
  { value: "memberships", label: "Membresías" },
  { value: "audit", label: "Auditoría" },
];

interface Confirmation {
  title: string;
  description: string;
  confirmLabel: string;
  danger: boolean;
  descriptor: StepUpDescriptor;
  operation: (headers: StepUpHeaders) => Promise<void>;
}

const tenantStatusLabel: Record<PlatformTenantStatus, string> = {
  ACTIVE: "Activa",
  SUSPENDED: "Suspendida",
  ARCHIVED: "Archivada",
};

const membershipStatusLabel: Record<MembershipStatus, string> = {
  ACTIVE: "Activa",
  SUSPENDED: "Suspendida",
  REVOKED: "Revocada",
};

const TenantDetailPage = () => {
  const { tenantId = "" } = useParams();
  const [tab, setTab] = useState<DetailTab>("general");
  const [name, setName] = useState("");
  const [membershipQuery, setMembershipQuery] = useState("");
  const [membershipStatus, setMembershipStatus] = useState<MembershipStatus | "">("");
  const [membershipPage, setMembershipPage] = useState(0);
  const [auditPage, setAuditPage] = useState(0);
  const [identityMode, setIdentityMode] = useState<"EXISTING" | "NEW">("EXISTING");
  const [identityValue, setIdentityValue] = useState("");
  const [validUntil, setValidUntil] = useState("");
  const [selectedRoles, setSelectedRoles] = useState<string[]>(["ADMINISTRADOR"]);
  const [editingMembership, setEditingMembership] = useState<PlatformMembership | null>(null);
  const [confirmation, setConfirmation] = useState<Confirmation | null>(null);
  const [activation, setActivation] = useState<ActivationDelivery | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [membershipValidationError, setMembershipValidationError] = useState("");
  const membershipIdentityRef = useRef<HTMLInputElement>(null);
  const tabRefs = useRef<Record<DetailTab, HTMLButtonElement | null>>({
    general: null,
    memberships: null,
    audit: null,
  });
  const debouncedMembershipQuery = useDebounce(membershipQuery, 300);
  const queryClient = useQueryClient();
  const { executeWithStepUp } = useStepUp();

  const tenant = useQuery({
    queryKey: ["PLATFORM", "tenant", tenantId],
    queryFn: () => platformApi.getTenant(tenantId),
    enabled: tenantId.length > 0,
  });
  const memberships = useQuery({
    queryKey: ["PLATFORM", "tenant", tenantId, "memberships", membershipPage, debouncedMembershipQuery.trim(), membershipStatus],
    queryFn: () => platformApi.listMemberships(tenantId, { page: membershipPage, size: 20, q: debouncedMembershipQuery.trim(), status: membershipStatus }),
    enabled: tenantId.length > 0 && tab === "memberships",
  });
  const roles = useQuery({
    queryKey: ["PLATFORM", "tenant", tenantId, "roles"],
    queryFn: () => platformApi.listRoles(tenantId),
    enabled: tenantId.length > 0 && tab === "memberships",
  });
  const audit = useQuery({
    queryKey: ["PLATFORM", "audit", "tenant", tenantId, auditPage],
    queryFn: () => platformApi.listAudit({ tenantId, page: auditPage, size: 20 }),
    enabled: tenantId.length > 0 && tab === "audit",
  });

  useEffect(() => {
    if (tenant.data) setName(tenant.data.name);
  }, [tenant.data]);

  const refreshTenant = async () => {
    await queryClient.invalidateQueries({ queryKey: ["PLATFORM", "tenant", tenantId] });
    await queryClient.invalidateQueries({ queryKey: ["PLATFORM", "tenants"] });
  };

  const refreshMemberships = async () => {
    await queryClient.invalidateQueries({ queryKey: ["PLATFORM", "tenant", tenantId, "memberships"] });
    await refreshTenant();
  };

  const run = async (
    descriptor: StepUpDescriptor,
    operation: (headers: StepUpHeaders) => Promise<void>,
    after: () => Promise<void>,
  ) => {
    setBusy(true);
    setError("");
    try {
      await executeWithStepUp(descriptor, operation);
      await after();
    } catch (operationError) {
      setError(getApiErrorMessage(operationError, "No se pudo completar la operación."));
      throw operationError;
    } finally {
      setBusy(false);
    }
  };

  const saveName = async (event: FormEvent) => {
    event.preventDefault();
    if (!tenant.data || !name.trim() || name.trim() === tenant.data.name) return;
    const currentTenant = tenant.data;
    const idempotencyKey = newIdempotencyKey();
    await run(
      { action: "TENANT_UPDATE", targetType: "TENANT", targetId: tenantId, idempotencyKey },
      async (headers) => { await platformApi.updateTenant(tenantId, { name: name.trim(), expectedVersion: currentTenant.version }, headers); },
      refreshTenant,
    ).catch(() => undefined);
  };

  const askTenantStatus = (status: PlatformTenantStatus) => {
    if (!tenant.data) return;
    const currentTenant = tenant.data;
    const idempotencyKey = newIdempotencyKey();
    setConfirmation({
      title: `${status === "ACTIVE" ? "Reactivar" : status === "SUSPENDED" ? "Suspender" : "Archivar"} organización`,
      description: status === "ACTIVE"
        ? `Se reactivará ${currentTenant.name}. Las memberships conservarán su propio estado.`
        : status === "SUSPENDED"
          ? `Se invalidará el acceso tenant de ${currentTenant.name}. La operación no borra datos.`
          : `Se archivará ${currentTenant.name} sin eliminar su historial.`,
      confirmLabel: status === "ACTIVE" ? "Reactivar" : status === "SUSPENDED" ? "Suspender" : "Archivar",
      danger: status !== "ACTIVE",
      descriptor: { action: "TENANT_STATUS", targetType: "TENANT", targetId: tenantId, idempotencyKey },
      operation: async (headers) => {
        await platformApi.changeTenantStatus(tenantId, {
          status,
          expectedVersion: currentTenant.version,
          reason: "Cambio confirmado desde el control plane",
        }, headers);
      },
    });
  };

  const createMembership = async (event: FormEvent) => {
    event.preventDefault();
    const missingIdentity = !identityValue.trim();
    const missingRoles = selectedRoles.length === 0;
    if (missingIdentity || missingRoles) {
      setMembershipValidationError(
        missingIdentity && missingRoles
          ? "Completá la identidad y seleccioná al menos un rol."
          : missingIdentity
            ? "Completá la identidad."
            : "Seleccioná al menos un rol.",
      );
      if (missingIdentity) membershipIdentityRef.current?.focus();
      else document.querySelector<HTMLInputElement>("#membership-roles input")?.focus();
      return;
    }
    setMembershipValidationError("");
    setActivation(null);
    const idempotencyKey = newIdempotencyKey();
    setBusy(true);
    setError("");
    try {
      const result = await executeWithStepUp(
        { action: "MEMBERSHIP_CREATE", targetType: "TENANT", targetId: tenantId, idempotencyKey },
        (headers) => platformApi.createMembership(tenantId, {
          identity: identityMode === "EXISTING"
            ? { mode: "EXISTING", usuarioId: Number(identityValue) }
            : { mode: "NEW", nombreUsuario: identityValue.trim() },
          roles: selectedRoles,
          validUntil: validUntil ? new Date(validUntil).toISOString() : null,
        }, headers),
      );
      setActivation(result.activation ?? null);
      await refreshMemberships();
      setIdentityValue("");
      setValidUntil("");
    } catch (operationError) {
      setError(getApiErrorMessage(operationError, "No se pudo completar la operación."));
    } finally {
      setBusy(false);
    }
  };

  const saveMembershipRoles = async () => {
    if (!editingMembership || selectedRoles.length === 0) return;
    const idempotencyKey = newIdempotencyKey();
    await run(
      { action: "MEMBERSHIP_ROLES", targetType: "TENANT_MEMBERSHIP", targetId: editingMembership.id, idempotencyKey },
      async (headers) => {
        await platformApi.updateMembershipRoles(tenantId, editingMembership.id, {
          roles: selectedRoles,
          expectedVersion: editingMembership.version,
        }, headers);
      },
      refreshMemberships,
    ).then(() => setEditingMembership(null)).catch(() => undefined);
  };

  const updateSelectedRole = (roleCode: string, checked: boolean) => {
    setMembershipValidationError("");
    setSelectedRoles((current) => checked
      ? [...new Set([...current, roleCode])]
      : current.filter((code) => code !== roleCode));
  };

  const askMembershipStatus = (membership: PlatformMembership, status: MembershipStatus) => {
    const idempotencyKey = newIdempotencyKey();
    setConfirmation({
      title: `${status === "ACTIVE" ? "Reactivar" : status === "SUSPENDED" ? "Suspender" : "Revocar"} membership`,
      description: `${membership.nombreUsuario} pasará a estado ${membershipStatusLabel[status].toLowerCase()}. El backend protegerá al último administrador tenant.`,
      confirmLabel: status === "ACTIVE" ? "Reactivar" : status === "SUSPENDED" ? "Suspender" : "Revocar",
      danger: status !== "ACTIVE",
      descriptor: { action: "MEMBERSHIP_STATUS", targetType: "TENANT_MEMBERSHIP", targetId: membership.id, idempotencyKey },
      operation: async (headers) => {
        await platformApi.changeMembershipStatus(tenantId, membership.id, {
          status,
          expectedVersion: membership.version,
          reason: "Cambio confirmado desde el control plane",
        }, headers);
      },
    });
  };

  const handleTabKeyDown = (event: KeyboardEvent<HTMLButtonElement>, currentTab: DetailTab) => {
    const currentIndex = detailTabs.findIndex(({ value }) => value === currentTab);
    let nextIndex: number | null = null;
    if (event.key === "ArrowRight") nextIndex = (currentIndex + 1) % detailTabs.length;
    if (event.key === "ArrowLeft") nextIndex = (currentIndex - 1 + detailTabs.length) % detailTabs.length;
    if (event.key === "Home") nextIndex = 0;
    if (event.key === "End") nextIndex = detailTabs.length - 1;
    if (nextIndex === null) return;

    event.preventDefault();
    const nextTab = detailTabs[nextIndex].value;
    setTab(nextTab);
    tabRefs.current[nextTab]?.focus();
  };

  const confirm = async () => {
    if (!confirmation) return;
    const after = confirmation.descriptor.targetType === "TENANT_MEMBERSHIP" ? refreshMemberships : refreshTenant;
    await run(confirmation.descriptor, confirmation.operation, after)
      .then(() => setConfirmation(null))
      .catch(() => setConfirmation(null));
  };

  if (tenant.isPending) return <LoadingState message="Cargando organización..." />;
  if (tenant.isError) return <ErrorState message={getApiErrorMessage(tenant.error, "No se pudo cargar la organización.")} onRetry={() => void tenant.refetch()} />;

  const tenantTone = tenant.data.status === "ACTIVE" ? "success" : tenant.data.status === "SUSPENDED" ? "warning" : "neutral";
  return (
    <div className="page-container">
      <PageHeader
        eyebrow="Organización"
        title={tenant.data.name}
        description={`Código inmutable: ${tenant.data.code}`}
        actions={<StatusBadge tone={tenantTone}>{tenantStatusLabel[tenant.data.status]}</StatusBadge>}
      />

      {error && <div className="rounded-lg border border-destructive/20 bg-destructive/10 p-3 text-sm font-medium text-destructive" role="alert">{error}</div>}

      {activation && (
        <OneTimeActivationNotice activation={activation} onDismiss={() => setActivation(null)} />
      )}

      <div className="flex overflow-x-auto border-b border-border" role="tablist" aria-label="Detalle de organización">
        {detailTabs.map(({ value, label }) => (
          <button
            key={value}
            ref={(element) => { tabRefs.current[value] = element; }}
            id={`tenant-tab-trigger-${value}`}
            type="button"
            role="tab"
            aria-selected={tab === value}
            aria-controls={`tenant-tab-${value}`}
            tabIndex={tab === value ? 0 : -1}
            className={tab === value ? "border-b-2 border-primary px-4 py-3 text-sm font-semibold text-primary" : "border-b-2 border-transparent px-4 py-3 text-sm font-medium text-muted-foreground hover:text-foreground"}
            onClick={() => setTab(value)}
            onKeyDown={(event) => handleTabKeyDown(event, value)}
          >
            {label}
          </button>
        ))}
      </div>

      {tab === "general" && (
        <div id="tenant-tab-general" role="tabpanel" aria-labelledby="tenant-tab-trigger-general" className="grid gap-5 xl:grid-cols-2">
          <SectionCard title="Datos generales" description="El código no se modifica para preservar integraciones y auditoría.">
            <form className="space-y-4" onSubmit={(event) => void saveName(event)}>
              <label className="field-group" htmlFor="tenant-detail-code">Código
                <input id="tenant-detail-code" className="form-input" value={tenant.data.code} disabled />
              </label>
              <label className="field-group" htmlFor="tenant-detail-name">Nombre
                <input id="tenant-detail-name" className="form-input" value={name} maxLength={150} onChange={(event) => setName(event.target.value)} />
              </label>
              <div className="form-actions"><Boton type="submit" disabled={busy || !name.trim() || name.trim() === tenant.data.name}><Pencil className="size-4" /> Guardar nombre</Boton></div>
            </form>
          </SectionCard>
          <SectionCard title="Ciclo de vida" description="Los cambios invalidan accesos cuando corresponde y nunca eliminan datos históricos.">
            <div className="space-y-3">
              {tenant.data.status === "ACTIVE" && <Boton className="page-button-danger w-full" onClick={() => askTenantStatus("SUSPENDED")}><ShieldOff className="size-4" /> Suspender organización</Boton>}
              {tenant.data.status === "SUSPENDED" && (
                <>
                  <Boton className="w-full" onClick={() => askTenantStatus("ACTIVE")}><CheckCircle2 className="size-4" /> Reactivar organización</Boton>
                  <Boton className="page-button-danger w-full" onClick={() => askTenantStatus("ARCHIVED")}><Archive className="size-4" /> Archivar organización</Boton>
                </>
              )}
              {tenant.data.status === "ARCHIVED" && <p className="text-sm text-muted-foreground">La organización está archivada. No se ofrecen acciones destructivas.</p>}
            </div>
          </SectionCard>
        </div>
      )}

      {tab === "memberships" && (
        <div id="tenant-tab-memberships" role="tabpanel" aria-labelledby="tenant-tab-trigger-memberships" className="space-y-5">
          <SectionCard title="Agregar membership" description="Vinculá una identidad global o creá una nueva; los roles siempre pertenecen a este tenant.">
            <form className="space-y-4" onSubmit={(event) => void createMembership(event)}>
              <div className="form-grid">
                <label className="field-group" htmlFor="membership-mode">Identidad
                  <select id="membership-mode" className="form-select" value={identityMode} onChange={(event) => { setIdentityMode(event.target.value as "EXISTING" | "NEW"); setIdentityValue(""); setMembershipValidationError(""); }}>
                    <option value="EXISTING">Existente por ID</option><option value="NEW">Nueva por usuario</option>
                  </select>
                </label>
                <label className="field-group" htmlFor="membership-identity">{identityMode === "EXISTING" ? "ID de identidad" : "Nombre de usuario"}
                  <input
                    ref={membershipIdentityRef}
                    id="membership-identity"
                    className="form-input"
                    type={identityMode === "EXISTING" ? "number" : "text"}
                    min={identityMode === "EXISTING" ? 1 : undefined}
                    value={identityValue}
                    onChange={(event) => { setIdentityValue(event.target.value); setMembershipValidationError(""); }}
                    aria-invalid={Boolean(membershipValidationError && !identityValue.trim())}
                    aria-describedby={membershipValidationError && !identityValue.trim() ? "membership-form-error" : undefined}
                  />
                </label>
                <label className="field-group" htmlFor="membership-valid-until">Válida hasta (opcional)
                  <input id="membership-valid-until" className="form-input" type="datetime-local" value={validUntil} onChange={(event) => setValidUntil(event.target.value)} />
                </label>
              </div>
              <fieldset id="membership-roles" aria-describedby={membershipValidationError && selectedRoles.length === 0 ? "membership-form-error" : undefined}>
                <legend className="mb-2 text-sm font-semibold">Roles tenant</legend>
                <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                  {(roles.data ?? []).filter((role) => role.active).map((role) => (
                    <label key={role.code} className="checkbox-field">
                      <input type="checkbox" checked={selectedRoles.includes(role.code)} onChange={(event) => updateSelectedRole(role.code, event.target.checked)} />
                      <span><span className="block">{role.name}</span><code className="text-xs text-muted-foreground">{role.code}</code></span>
                    </label>
                  ))}
                </div>
              </fieldset>
              {membershipValidationError && <p id="membership-form-error" className="form-error" role="alert">{membershipValidationError}</p>}
              <div className="form-actions"><Boton type="submit" disabled={busy}><PlusCircle className="size-4" /> Agregar membership</Boton></div>
            </form>
          </SectionCard>

          {editingMembership && (
            <SectionCard title={`Editar roles de ${editingMembership.nombreUsuario}`} description="La actualización reemplaza el conjunto de roles tenant de esta membership.">
              <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                {(roles.data ?? []).filter((role) => role.active).map((role) => (
                  <label key={role.code} className="checkbox-field"><input type="checkbox" checked={selectedRoles.includes(role.code)} onChange={(event) => updateSelectedRole(role.code, event.target.checked)} />{role.name}</label>
                ))}
              </div>
              <div className="form-actions mt-4"><Boton className="page-button-secondary" onClick={() => setEditingMembership(null)}>Cancelar</Boton><Boton onClick={() => void saveMembershipRoles()} disabled={busy || selectedRoles.length === 0}>Guardar roles</Boton></div>
            </SectionCard>
          )}

          <FilterBar label="Filtrar memberships">
            <SearchInput id="membership-search" placeholder="Buscar por usuario" value={membershipQuery} onChange={(event) => { setMembershipQuery(event.target.value); setMembershipPage(0); }} />
            <label className="field-group sm:min-w-48" htmlFor="membership-status">Estado
              <select id="membership-status" className="form-select" value={membershipStatus} onChange={(event) => { setMembershipStatus(event.target.value as MembershipStatus | ""); setMembershipPage(0); }}>
                <option value="">Todas</option><option value="ACTIVE">Activas</option><option value="SUSPENDED">Suspendidas</option><option value="REVOKED">Revocadas</option>
              </select>
            </label>
          </FilterBar>
          {memberships.isPending ? <LoadingState message="Cargando memberships..." /> : memberships.isError ? <ErrorState message={getApiErrorMessage(memberships.error, "No se pudieron cargar las memberships.")} onRetry={() => void memberships.refetch()} /> : (
            <>
              <Tabla<PlatformMembership>
                headers={["Usuario", "Roles", "Estado", "Vigencia", "Acciones"]}
                data={memberships.data.content}
                getRowKey={(membership) => membership.id}
                emptyMessage="No hay memberships que coincidan con los filtros."
                customRender={(membership) => [
                  <span key="user" className="flex items-center gap-2 font-semibold"><UserRoundCog className="size-4 text-primary" />{membership.nombreUsuario}</span>,
                  membership.roles.join(", "),
                  <StatusBadge key="status" tone={membership.status === "ACTIVE" ? "success" : membership.status === "SUSPENDED" ? "warning" : "danger"}>{membershipStatusLabel[membership.status]}</StatusBadge>,
                  membership.validUntil ? new Date(membership.validUntil).toLocaleString() : "Sin vencimiento",
                ]}
                actions={(membership) => membership.status !== "REVOKED" ? (
                  <>
                    <Boton className="page-button-secondary" onClick={() => { setEditingMembership(membership); setSelectedRoles(membership.roles); }}>Roles</Boton>
                    {membership.status === "ACTIVE" ? <Boton className="page-button-secondary" onClick={() => askMembershipStatus(membership, "SUSPENDED")}>Suspender</Boton> : <Boton className="page-button-secondary" onClick={() => askMembershipStatus(membership, "ACTIVE")}>Reactivar</Boton>}
                    <Boton className="page-button-danger" onClick={() => askMembershipStatus(membership, "REVOKED")}>Revocar</Boton>
                  </>
                ) : <span className="text-xs text-muted-foreground">Revocada</span>}
              />
              <PaginationControls page={memberships.data.number} totalPages={memberships.data.totalPages} onPageChange={setMembershipPage} disabled={memberships.isFetching} />
            </>
          )}
        </div>
      )}

      {tab === "audit" && (
        <div id="tenant-tab-audit" role="tabpanel" aria-labelledby="tenant-tab-trigger-audit" className="space-y-4">
          {audit.isPending ? <LoadingState message="Cargando auditoría de la organización..." /> : audit.isError ? <ErrorState message={getApiErrorMessage(audit.error, "No se pudo cargar la auditoría.")} onRetry={() => void audit.refetch()} /> : (
            <>
              <Tabla<PlatformAuditEvent>
                headers={["Fecha", "Actor", "Acción", "Resultado", "Correlación"]}
                data={audit.data.content}
                getRowKey={(event) => event.id}
                emptyMessage="Todavía no hay eventos auditables para esta organización."
                customRender={(event) => [new Date(event.occurredAt).toLocaleString(), event.actorUsername ?? "Sistema", event.action, <StatusBadge key="result" tone={event.result === "SUCCESS" ? "success" : event.result === "DENIED" ? "warning" : "danger"}>{event.result}</StatusBadge>, <code key="correlation" className="text-xs">{event.correlationId}</code>]}
              />
              <PaginationControls page={audit.data.number} totalPages={audit.data.totalPages} onPageChange={setAuditPage} disabled={audit.isFetching} />
              <Link className="button-base page-button-secondary" to={`/platform/audit?tenantId=${tenantId}`}>Abrir auditoría completa</Link>
            </>
          )}
        </div>
      )}

      <ConfirmDialog
        open={confirmation !== null}
        title={confirmation?.title ?? "Confirmar acción"}
        description={confirmation?.description ?? ""}
        confirmLabel={confirmation?.confirmLabel ?? "Confirmar"}
        danger={confirmation?.danger}
        busy={busy}
        onOpenChange={(open) => !open && setConfirmation(null)}
        onConfirm={() => void confirm()}
      />
    </div>
  );
};

export default TenantDetailPage;
