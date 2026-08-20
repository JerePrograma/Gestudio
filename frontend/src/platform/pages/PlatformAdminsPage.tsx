import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Copy, KeyRound, PlusCircle, ShieldOff, UserCog, X } from "lucide-react";
import { useRef, useState } from "react";
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
import { useAuth } from "../../hooks/context/useAuth";
import useDebounce from "../../hooks/useDebounce";
import { platformActivationUrl } from "../activationLink";
import ConfirmDialog from "../ConfirmDialog";
import { newIdempotencyKey, platformApi } from "../platformApi";
import type { ActivationDelivery, PlatformAdmin, PlatformAdminStatus } from "../platformTypes";
import { useStepUp } from "../stepUpContext";

type Confirmation =
  | { type: "REVOKE"; admin: PlatformAdmin }
  | { type: "RESET_MFA"; admin: PlatformAdmin }
  | null;

const PlatformAdminsPage = () => {
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<PlatformAdminStatus | "">("");
  const [page, setPage] = useState(0);
  const [newAdminId, setNewAdminId] = useState("");
  const [adminIdError, setAdminIdError] = useState("");
  const [confirmation, setConfirmation] = useState<Confirmation>(null);
  const [activation, setActivation] = useState<ActivationDelivery | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const adminIdRef = useRef<HTMLInputElement>(null);
  const debouncedQuery = useDebounce(query, 300);
  const queryClient = useQueryClient();
  const { platformUser } = useAuth();
  const { executeWithStepUp } = useStepUp();
  const admins = useQuery({
    queryKey: ["PLATFORM", "admins", page, debouncedQuery.trim(), status],
    queryFn: () => platformApi.listAdmins({ page, size: 25, q: debouncedQuery.trim(), status }),
  });

  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ["PLATFORM", "admins"] });
  };

  const grant = async () => {
    const usuarioId = Number(newAdminId);
    if (!Number.isSafeInteger(usuarioId) || usuarioId <= 0) {
      setAdminIdError("Ingresá un ID de identidad válido.");
      adminIdRef.current?.focus();
      return;
    }
    const idempotencyKey = newIdempotencyKey();
    setBusy(true);
    setAdminIdError("");
    setError("");
    try {
      await executeWithStepUp(
        { action: "PLATFORM_ADMIN_GRANT", targetType: "PLATFORM_ADMIN", targetId: String(usuarioId), idempotencyKey },
        async (headers) => {
          const granted = await platformApi.grantAdmin({ usuarioId }, headers);
          setActivation(granted.activation ?? null);
        },
      );
      setNewAdminId("");
      await refresh();
    } catch (grantError) {
      setError(getApiErrorMessage(grantError, "No se pudo otorgar el acceso de plataforma."));
    } finally {
      setBusy(false);
    }
  };

  const confirmAction = async () => {
    if (!confirmation) return;
    const { admin } = confirmation;
    const idempotencyKey = newIdempotencyKey();
    setBusy(true);
    setError("");
    try {
      if (confirmation.type === "REVOKE") {
        await executeWithStepUp(
          { action: "PLATFORM_ADMIN_STATUS", targetType: "PLATFORM_ADMIN", targetId: String(admin.usuarioId), idempotencyKey },
          async (headers) => {
            await platformApi.changeAdminStatus(admin.usuarioId, {
              status: "REVOKED",
              expectedVersion: admin.version,
              reason: "Revocación desde el control plane",
            }, headers);
          },
        );
      } else {
        await executeWithStepUp(
          { action: "PLATFORM_MFA_RESET", targetType: "PLATFORM_ADMIN", targetId: String(admin.usuarioId), idempotencyKey },
          async (headers) => {
            setActivation(await platformApi.resetAdminMfa(admin.usuarioId, headers));
          },
        );
      }
      setConfirmation(null);
      await refresh();
    } catch (actionError) {
      setError(getApiErrorMessage(actionError, "No se pudo completar la acción sobre el administrador."));
      setConfirmation(null);
    } finally {
      setBusy(false);
    }
  };

  if (admins.isPending) return <LoadingState message="Cargando administradores de plataforma..." />;
  if (admins.isError) return <ErrorState message={getApiErrorMessage(admins.error, "No se pudieron cargar los administradores.")} onRetry={() => void admins.refetch()} />;

  return (
    <div className="page-container">
      <PageHeader eyebrow="Seguridad" title="Administradores de plataforma" description="Accesos globales respaldados por platform_admins y protegidos con MFA." count={admins.data.totalElements} />

      <SectionCard title="Otorgar acceso" description="La identidad debe existir. Esta acción no crea una membership tenant.">
        <div className="form-row items-end">
          <label className="field-group" htmlFor="platform-admin-id">ID de identidad global
            <input
              ref={adminIdRef}
              id="platform-admin-id"
              className="form-input"
              type="number"
              min="1"
              value={newAdminId}
              onChange={(event) => {
                setNewAdminId(event.target.value);
                setAdminIdError("");
              }}
              aria-invalid={Boolean(adminIdError)}
              aria-describedby={adminIdError ? "platform-admin-id-error" : undefined}
            />
            {adminIdError && <span id="platform-admin-id-error" className="form-error" role="alert">{adminIdError}</span>}
          </label>
          <Boton type="button" onClick={() => void grant()} disabled={busy || !newAdminId}>
            <PlusCircle className="size-4" aria-hidden="true" /> Otorgar acceso
          </Boton>
        </div>
      </SectionCard>

      {error && <div className="rounded-lg border border-destructive/20 bg-destructive/10 p-3 text-sm font-medium text-destructive" role="alert">{error}</div>}

      {activation && (
        <section className="rounded-[var(--radius-lg)] border border-[hsl(var(--warning)/0.3)] bg-[hsl(var(--warning-soft))] p-4" aria-labelledby="admin-activation-title">
          <div className="flex items-start gap-3">
            <div className="min-w-0 flex-1">
              <h2 id="admin-activation-title" className="text-base font-semibold text-[hsl(var(--warning))]">Activación de plataforma: se muestra una sola vez</h2>
              <p className="mt-1 text-sm text-muted-foreground">Entregá este enlace por un canal externo seguro. Permitirá configurar la contraseña cuando corresponda y el factor TOTP antes de activar el acceso.</p>
              <div className="mt-3 flex flex-col gap-2 sm:flex-row">
                <code className="min-w-0 flex-1 break-all rounded-lg bg-card p-3 text-xs">{platformActivationUrl(activation.token)}</code>
                <Boton className="page-button-secondary" onClick={() => void navigator.clipboard.writeText(platformActivationUrl(activation.token))}><Copy className="size-4" /> Copiar</Boton>
              </div>
              <p className="mt-2 text-xs text-muted-foreground">Vence: {new Date(activation.expiresAt).toLocaleString()}</p>
            </div>
            <button type="button" className="icon-button" aria-label="Descartar token de activación" onClick={() => setActivation(null)}><X className="size-4" /></button>
          </div>
        </section>
      )}

      <FilterBar label="Filtrar administradores">
        <SearchInput id="admin-search" placeholder="Buscar por usuario" value={query} onChange={(event) => { setQuery(event.target.value); setPage(0); }} />
        <label className="field-group sm:min-w-48" htmlFor="admin-status">Estado
          <select id="admin-status" className="form-select" value={status} onChange={(event) => { setStatus(event.target.value as PlatformAdminStatus | ""); setPage(0); }}>
            <option value="">Todos</option><option value="ACTIVE">Activos</option><option value="REVOKED">Revocados</option>
          </select>
        </label>
      </FilterBar>

      <Tabla<PlatformAdmin>
        headers={["Administrador", "Estado", "MFA", "Alta", "Acciones"]}
        data={admins.data.content}
        getRowKey={(admin) => admin.usuarioId}
        emptyMessage="No hay administradores que coincidan con los filtros."
        customRender={(admin) => [
          <span key="user" className="flex items-center gap-2 font-semibold"><UserCog className="size-4 text-primary" />{admin.nombreUsuario}</span>,
          <StatusBadge key="status" tone={admin.status === "ACTIVE" ? "success" : "danger"}>{admin.status === "ACTIVE" ? "Activo" : "Revocado"}</StatusBadge>,
          <StatusBadge key="mfa" tone={admin.mfaEnabled ? "success" : "warning"}>{admin.mfaEnabled ? "Configurado" : "Pendiente"}</StatusBadge>,
          admin.createdAt ? new Date(admin.createdAt).toLocaleDateString() : "—",
        ]}
        actions={(admin) => admin.status === "ACTIVE" ? (
          <>
            {admin.usuarioId === platformUser?.id
              ? <span className="text-xs text-muted-foreground">MFA propio: recuperación asistida</span>
              : (
                <Boton className="page-button-secondary" onClick={() => setConfirmation({ type: "RESET_MFA", admin })} aria-label={`Reiniciar MFA de ${admin.nombreUsuario}`}>
                  <KeyRound className="size-4" /> MFA
                </Boton>
              )}
            <Boton className="page-button-danger" onClick={() => setConfirmation({ type: "REVOKE", admin })} aria-label={`Revocar a ${admin.nombreUsuario}`}>
              <ShieldOff className="size-4" /> Revocar
            </Boton>
          </>
        ) : <span className="text-xs text-muted-foreground">Sin acciones</span>}
      />

      <PaginationControls page={admins.data.number} totalPages={admins.data.totalPages} onPageChange={setPage} disabled={admins.isFetching} />

      <ConfirmDialog
        open={confirmation !== null}
        title={confirmation?.type === "REVOKE" ? "Revocar acceso de plataforma" : "Reiniciar segundo factor"}
        description={confirmation?.type === "REVOKE"
          ? `Se invalidarán las sesiones de ${confirmation.admin.nombreUsuario}. El último administrador recuperable no puede revocarse.`
          : `Se revocará el MFA actual de ${confirmation?.admin.nombreUsuario}; deberá aprovisionarse nuevamente mediante el flujo autorizado.`}
        confirmLabel={confirmation?.type === "REVOKE" ? "Revocar acceso" : "Reiniciar MFA"}
        danger
        busy={busy}
        onOpenChange={(open) => !open && setConfirmation(null)}
        onConfirm={() => void confirmAction()}
      />
    </div>
  );
};

export default PlatformAdminsPage;
