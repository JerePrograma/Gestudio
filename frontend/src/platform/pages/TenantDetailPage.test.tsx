import { fireEvent, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { renderPlatformPage } from "../../test/renderPlatformPage";

const api = vi.hoisted(() => ({
  getTenant: vi.fn(),
  listMemberships: vi.fn(),
  listRoles: vi.fn(),
  listAudit: vi.fn(),
  updateTenant: vi.fn(),
  changeTenantStatus: vi.fn(),
  createMembership: vi.fn(),
  updateMembershipRoles: vi.fn(),
  changeMembershipStatus: vi.fn(),
}));
const keys = vi.hoisted(() => ({ next: vi.fn(() => "idem-detail") }));
const stepUp = vi.hoisted(() => ({
  executeWithStepUp: vi.fn(async (_descriptor: unknown, operation: (headers: Record<string, string>) => Promise<unknown>) =>
    operation({ "Idempotency-Key": "idem-detail", "X-Step-Up-Token": "proof" })),
}));

vi.mock("../platformApi", () => ({ platformApi: api, newIdempotencyKey: keys.next }));
vi.mock("../stepUpContext", () => ({ useStepUp: () => stepUp }));

import TenantDetailPage from "./TenantDetailPage";

const activeTenant = {
  id: "tenant-1",
  code: "academia-centro",
  name: "Academia Centro",
  status: "ACTIVE",
  version: 4,
  membershipCount: 3,
};
const memberships = {
  content: [
    { id: "membership-active", tenantId: "tenant-1", usuarioId: 1, nombreUsuario: "active-user", status: "ACTIVE", roles: ["ADMINISTRADOR"], validFrom: "2030-01-01T00:00:00Z", version: 2 },
    { id: "membership-suspended", tenantId: "tenant-1", usuarioId: 2, nombreUsuario: "suspended-user", status: "SUSPENDED", roles: ["LECTURA"], validFrom: "2030-01-01T00:00:00Z", validUntil: "2031-01-01T00:00:00Z", version: 3 },
    { id: "membership-revoked", tenantId: "tenant-1", usuarioId: 3, nombreUsuario: "revoked-user", status: "REVOKED", roles: [], validFrom: "2030-01-01T00:00:00Z", version: 1 },
  ],
  totalElements: 3,
  totalPages: 2,
  number: 0,
  size: 20,
};
const roles = [
  { code: "ADMINISTRADOR", name: "Administrador", active: true },
  { code: "LECTURA", name: "Lectura", active: true },
  { code: "RETIRADO", name: "Retirado", active: false },
];
const auditPage = {
  content: [
    { id: "audit-1", occurredAt: "2030-01-01T00:00:00Z", actorUsername: "global-admin", action: "TENANT_UPDATE", result: "SUCCESS", correlationId: "corr-1" },
    { id: "audit-2", occurredAt: "2030-01-02T00:00:00Z", action: "TENANT_STATUS", result: "DENIED", correlationId: "corr-2" },
    { id: "audit-3", occurredAt: "2030-01-03T00:00:00Z", actorUsername: "other-admin", action: "TENANT_STATUS", result: "FAILED", correlationId: "corr-3" },
  ],
  totalElements: 3,
  totalPages: 2,
  number: 0,
  size: 20,
};

const renderDetail = () => renderPlatformPage(
  <TenantDetailPage />,
  "/platform/tenants/tenant-1",
  "/platform/tenants/:tenantId",
);

describe("TenantDetailPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.getTenant.mockResolvedValue(activeTenant);
    api.listMemberships.mockResolvedValue(memberships);
    api.listRoles.mockResolvedValue(roles);
    api.listAudit.mockResolvedValue(auditPage);
    api.updateTenant.mockResolvedValue(undefined);
    api.changeTenantStatus.mockResolvedValue(undefined);
    api.createMembership.mockResolvedValue({
      membership: memberships.content[0],
      activation: { token: "membership-token", expiresAt: "2030-03-01T00:00:00Z" },
      replayed: false,
    });
    api.updateMembershipRoles.mockResolvedValue(undefined);
    api.changeMembershipStatus.mockResolvedValue(undefined);
  });

  it("actualiza el nombre y suspende sin borrar la organización", async () => {
    renderDetail();
    expect(await screen.findByText("Academia Centro")).toBeVisible();
    const name = screen.getByLabelText("Nombre");
    expect(screen.getByRole("button", { name: "Guardar nombre" })).toBeDisabled();
    fireEvent.change(name, { target: { value: " Academia Norte " } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar nombre" }));
    await waitFor(() => expect(api.updateTenant).toHaveBeenCalledWith(
      "tenant-1",
      { name: "Academia Norte", expectedVersion: 4 },
      expect.anything(),
    ));

    fireEvent.click(screen.getByRole("button", { name: "Suspender organización" }));
    expect(screen.getByRole("dialog", { name: "Suspender organización" })).toHaveTextContent("no borra datos");
    fireEvent.click(screen.getByRole("button", { name: "Suspender" }));
    await waitFor(() => expect(api.changeTenantStatus).toHaveBeenCalledWith(
      "tenant-1",
      expect.objectContaining({ status: "SUSPENDED", expectedVersion: 4 }),
      expect.anything(),
    ));
  });

  it("recorre las pestañas con foco roving y teclas de navegación", async () => {
    renderDetail();
    await screen.findByText("Academia Centro");
    const general = screen.getByRole("tab", { name: "General" });
    const membershipsTab = screen.getByRole("tab", { name: "Membresías" });
    const auditTab = screen.getByRole("tab", { name: "Auditoría" });

    expect(general).toHaveAttribute("tabindex", "0");
    expect(membershipsTab).toHaveAttribute("tabindex", "-1");
    expect(screen.getByRole("tabpanel")).toHaveAttribute("aria-labelledby", general.id);

    general.focus();
    fireEvent.keyDown(general, { key: "ArrowRight" });
    expect(membershipsTab).toHaveFocus();
    expect(membershipsTab).toHaveAttribute("aria-selected", "true");
    expect(membershipsTab).toHaveAttribute("tabindex", "0");

    fireEvent.keyDown(membershipsTab, { key: "End" });
    expect(auditTab).toHaveFocus();
    expect(auditTab).toHaveAttribute("aria-selected", "true");

    fireEvent.keyDown(auditTab, { key: "Home" });
    expect(general).toHaveFocus();
    expect(general).toHaveAttribute("aria-selected", "true");

    fireEvent.keyDown(general, { key: "ArrowLeft" });
    expect(auditTab).toHaveFocus();
  });

  it.each([
    ["SUSPENDED", "Suspendida", "Reactivar organización", "Reactivar", "ACTIVE"],
    ["SUSPENDED", "Suspendida", "Archivar organización", "Archivar", "ARCHIVED"],
  ])("ofrece la transición %s -> %s", async (status, label, action, confirm, targetStatus) => {
    api.getTenant.mockResolvedValue({ ...activeTenant, status });
    renderDetail();
    expect((await screen.findAllByText(label)).length).toBeGreaterThan(0);
    fireEvent.click(screen.getByRole("button", { name: action }));
    fireEvent.click(screen.getByRole("button", { name: confirm }));
    await waitFor(() => expect(api.changeTenantStatus).toHaveBeenCalledWith(
      "tenant-1",
      expect.objectContaining({ status: targetStatus }),
      expect.anything(),
    ));
  });

  it("no ofrece mutaciones destructivas a una organización archivada", async () => {
    api.getTenant.mockResolvedValue({ ...activeTenant, status: "ARCHIVED" });
    renderDetail();
    expect(await screen.findByText("La organización está archivada. No se ofrecen acciones destructivas.")).toBeVisible();
    expect(screen.queryByRole("button", { name: /organización/ })).not.toBeInTheDocument();
  });

  it("informa un fallo de actualización sin propagar detalles internos", async () => {
    api.updateTenant.mockRejectedValueOnce(new Error("detalle interno"));
    renderDetail();
    await screen.findByText("Academia Centro");
    fireEvent.change(screen.getByLabelText("Nombre"), { target: { value: "Academia Fallida" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar nombre" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudo completar la operación.");
    expect(screen.queryByText("detalle interno")).not.toBeInTheDocument();
  });

  it("crea memberships existentes y nuevas con roles tenant", async () => {
    renderDetail();
    await screen.findByText("Academia Centro");
    fireEvent.click(screen.getByRole("tab", { name: "Membresías" }));
    expect((await screen.findAllByText("active-user"))[0]).toBeVisible();
    expect(screen.queryByText("Retirado")).not.toBeInTheDocument();

    const addButton = screen.getByRole("button", { name: "Agregar membership" });
    fireEvent.submit(addButton.closest("form")!);
    const membershipError = await screen.findByRole("alert");
    const identityInput = screen.getByLabelText("ID de identidad");
    expect(membershipError).toHaveTextContent("Completá la identidad.");
    expect(identityInput).toHaveFocus();
    expect(identityInput).toHaveAttribute("aria-invalid", "true");
    expect(identityInput).toHaveAttribute("aria-describedby", membershipError.id);

    fireEvent.change(identityInput, { target: { value: "12" } });
    expect(identityInput).toHaveAttribute("aria-invalid", "false");
    fireEvent.click(screen.getByRole("checkbox", { name: /Administrador/ }));
    fireEvent.click(addButton);
    const rolesError = await screen.findByRole("alert");
    expect(rolesError).toHaveTextContent("Seleccioná al menos un rol.");
    expect(screen.getByRole("checkbox", { name: /Administrador/ })).toHaveFocus();
    expect(screen.getByRole("group", { name: "Roles tenant" })).toHaveAttribute("aria-describedby", rolesError.id);
    fireEvent.click(screen.getByRole("checkbox", { name: /Administrador/ }));
    fireEvent.change(screen.getByLabelText("Válida hasta (opcional)"), { target: { value: "2031-02-01T10:30" } });
    fireEvent.click(addButton);
    expect(
      await screen.findByText(
        "http://localhost:3000/platform/activate#token=membership-token",
      ),
    ).toBeVisible();
    expect(api.createMembership).toHaveBeenCalledWith(
      "tenant-1",
      expect.objectContaining({
        identity: { mode: "EXISTING", usuarioId: 12 },
        roles: ["ADMINISTRADOR"],
        validUntil: expect.stringContaining("2031-02-01"),
      }),
      expect.anything(),
    );
    await waitFor(() => expect(addButton).toBeEnabled());

    fireEvent.change(screen.getByLabelText("Identidad"), { target: { value: "NEW" } });
    fireEvent.change(screen.getByLabelText("Nombre de usuario"), { target: { value: " new-user " } });
    fireEvent.click(screen.getByRole("button", { name: "Agregar membership" }));
    await waitFor(() => expect(api.createMembership).toHaveBeenLastCalledWith(
      "tenant-1",
      expect.objectContaining({ identity: { mode: "NEW", nombreUsuario: "new-user" }, validUntil: null }),
      expect.anything(),
    ));
  });

  it("edita roles y ejecuta todas las transiciones de membership", async () => {
    renderDetail();
    await screen.findByText("Academia Centro");
    fireEvent.click(screen.getByRole("tab", { name: "Membresías" }));
    await screen.findAllByText("active-user");

    fireEvent.click(screen.getAllByRole("button", { name: "Roles" })[0]);
    expect(screen.getByText("Editar roles de active-user")).toBeVisible();
    const lecturas = screen.getAllByRole("checkbox", { name: /Lectura/ });
    const lectura = lecturas[lecturas.length - 1];
    expect(lectura).toBeDefined();
    fireEvent.click(lectura);
    fireEvent.click(screen.getByRole("button", { name: "Guardar roles" }));
    await waitFor(() => expect(api.updateMembershipRoles).toHaveBeenCalledWith(
      "tenant-1",
      "membership-active",
      expect.objectContaining({ roles: expect.arrayContaining(["ADMINISTRADOR", "LECTURA"]), expectedVersion: 2 }),
      expect.anything(),
    ));

    fireEvent.click(screen.getAllByRole("button", { name: "Suspender" })[0]);
    fireEvent.click(screen.getByRole("button", { name: "Suspender" }));
    await waitFor(() => expect(api.changeMembershipStatus).toHaveBeenCalledWith(
      "tenant-1", "membership-active", expect.objectContaining({ status: "SUSPENDED" }), expect.anything(),
    ));

    fireEvent.click(screen.getAllByRole("button", { name: "Reactivar" })[0]);
    fireEvent.click(screen.getByRole("button", { name: "Reactivar" }));
    await waitFor(() => expect(api.changeMembershipStatus).toHaveBeenCalledWith(
      "tenant-1", "membership-suspended", expect.objectContaining({ status: "ACTIVE" }), expect.anything(),
    ));

    fireEvent.click(screen.getAllByRole("button", { name: "Revocar" })[0]);
    fireEvent.click(screen.getByRole("button", { name: "Revocar" }));
    await waitFor(() => expect(api.changeMembershipStatus).toHaveBeenCalledWith(
      "tenant-1", "membership-active", expect.objectContaining({ status: "REVOKED" }), expect.anything(),
    ));
    expect(screen.getAllByText("Revocada").length).toBeGreaterThan(0);
  });

  it("cancela edición, filtra y pagina memberships", async () => {
    renderDetail();
    await screen.findByText("Academia Centro");
    fireEvent.click(screen.getByRole("tab", { name: "Membresías" }));
    await screen.findAllByText("active-user");
    fireEvent.click(screen.getAllByRole("button", { name: "Roles" })[0]);
    fireEvent.click(screen.getByRole("button", { name: "Cancelar" }));
    expect(screen.queryByText("Editar roles de active-user")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Siguiente" }));
    await waitFor(() => expect(api.listMemberships).toHaveBeenCalledWith(
      "tenant-1",
      expect.objectContaining({ page: 1 }),
    ));
    await screen.findAllByText("active-user");
    fireEvent.change(screen.getByPlaceholderText("Buscar por usuario"), { target: { value: "active" } });
    await screen.findAllByText("active-user");
    fireEvent.change(screen.getByLabelText("Estado"), { target: { value: "SUSPENDED" } });
    await waitFor(() => expect(api.listMemberships).toHaveBeenCalledWith(
      "tenant-1",
      expect.objectContaining({ page: 0, status: "SUSPENDED" }),
    ));
  });

  it("muestra errores recuperables de memberships y de su alta", async () => {
    api.listMemberships.mockRejectedValueOnce(new Error("sin red")).mockResolvedValueOnce(memberships);
    renderDetail();
    await screen.findByText("Academia Centro");
    fireEvent.click(screen.getByRole("tab", { name: "Membresías" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudieron cargar las memberships.");
    fireEvent.click(screen.getByRole("button", { name: "Reintentar" }));
    await screen.findAllByText("active-user");

    api.createMembership.mockRejectedValueOnce(new Error("falló"));
    fireEvent.change(screen.getByLabelText("ID de identidad"), { target: { value: "44" } });
    const addButton = screen.getByRole("button", { name: "Agregar membership" });
    fireEvent.click(addButton);
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudo completar la operación.");
    await waitFor(() => expect(addButton).toBeEnabled());
  });

  it("presenta auditoría tenant, pagina y enlaza al visor completo", async () => {
    renderDetail();
    await screen.findByText("Academia Centro");
    fireEvent.click(screen.getByRole("tab", { name: "Auditoría" }));
    expect((await screen.findAllByText("global-admin"))[0]).toBeVisible();
    expect(screen.getAllByText("Sistema").length).toBeGreaterThan(0);
    expect(screen.getAllByText("SUCCESS").length).toBeGreaterThan(0);
    expect(screen.getAllByText("DENIED").length).toBeGreaterThan(0);
    expect(screen.getAllByText("FAILED").length).toBeGreaterThan(0);
    expect(screen.getByRole("link", { name: "Abrir auditoría completa" })).toHaveAttribute(
      "href",
      "/platform/audit?tenantId=tenant-1",
    );
    fireEvent.click(screen.getByRole("button", { name: "Siguiente" }));
    await waitFor(() => expect(api.listAudit).toHaveBeenCalledWith(expect.objectContaining({ page: 1 })));
  });

  it("permite reintentar la carga principal y la auditoría", async () => {
    api.getTenant.mockRejectedValueOnce(new Error("sin red")).mockResolvedValueOnce(activeTenant);
    const failed = renderDetail();
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudo cargar la organización.");
    fireEvent.click(screen.getByRole("button", { name: "Reintentar" }));
    expect(await screen.findByText("Academia Centro")).toBeVisible();
    failed.unmount();

    api.listAudit.mockRejectedValueOnce(new Error("sin red")).mockResolvedValueOnce(auditPage);
    renderDetail();
    await screen.findByText("Academia Centro");
    fireEvent.click(screen.getByRole("tab", { name: "Auditoría" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudo cargar la auditoría.");
    fireEvent.click(screen.getByRole("button", { name: "Reintentar" }));
    expect((await screen.findAllByText("global-admin"))[0]).toBeVisible();
  });
});
