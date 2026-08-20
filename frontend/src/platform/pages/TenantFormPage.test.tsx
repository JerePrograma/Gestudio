import { fireEvent, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { renderPlatformPage } from "../../test/renderPlatformPage";

const api = vi.hoisted(() => ({ createTenant: vi.fn(), searchIdentities: vi.fn() }));
const keys = vi.hoisted(() => ({ next: vi.fn(() => "idem-tenant") }));
const stepUp = vi.hoisted(() => ({
  executeWithStepUp: vi.fn(async (_descriptor: unknown, operation: (headers: Record<string, string>) => Promise<unknown>) =>
    operation({ "Idempotency-Key": "idem-tenant", "X-Step-Up-Token": "proof" })),
}));

vi.mock("../platformApi", () => ({ platformApi: api, newIdempotencyKey: keys.next }));
vi.mock("../stepUpContext", () => ({ useStepUp: () => stepUp }));

import TenantFormPage from "./TenantFormPage";

const result = {
  tenant: { id: "tenant-1", code: "academia-centro", name: "Academia Centro", status: "ACTIVE", version: 1 },
  initialAdmin: { id: "membership-1", tenantId: "tenant-1", usuarioId: 4, nombreUsuario: "tenant-admin", status: "ACTIVE", roles: ["ADMINISTRADOR"], validFrom: "2030-01-01T00:00:00Z" },
  activation: { token: "one-time-tenant", expiresAt: "2030-02-01T00:00:00Z" },
  replayed: false,
};

const fillNewTenant = () => {
  fireEvent.change(screen.getByLabelText("Código"), { target: { value: "  Academia-Centro  " } });
  fireEvent.change(screen.getByLabelText("Nombre"), { target: { value: " Academia Centro " } });
  fireEvent.change(screen.getByLabelText("Nombre de usuario"), { target: { value: " tenant-admin " } });
};

describe("TenantFormPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    keys.next.mockReturnValue("idem-tenant");
    api.searchIdentities.mockResolvedValue([]);
    api.createTenant.mockResolvedValue(result);
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: vi.fn().mockResolvedValue(undefined) },
    });
  });

  it("valida el formulario antes de habilitar la confirmación", async () => {
    renderPlatformPage(<TenantFormPage />, "/platform/tenants/new", "/platform/tenants/new");
    fireEvent.click(screen.getByRole("button", { name: "Revisar y crear" }));
    const codeError = await screen.findByText("Ingresá un código");
    expect(codeError).toBeVisible();
    expect(screen.getByText("Ingresá un nombre")).toBeVisible();
    expect(screen.getByText("Ingresá el nombre de usuario inicial")).toBeVisible();
    const code = screen.getByLabelText("Código");
    await waitFor(() => expect(code).toHaveFocus());
    expect(code).toHaveAttribute("aria-invalid", "true");
    expect(code).toHaveAttribute("aria-describedby", codeError.id);
    expect(screen.getByLabelText("Nombre")).toHaveAttribute("aria-describedby", "tenant-name-error");
    expect(screen.getByLabelText("Nombre de usuario")).toHaveAttribute("aria-describedby", "initial-username-error");

    fireEvent.change(code, { target: { value: "a!" } });
    fireEvent.click(screen.getByRole("button", { name: "Revisar y crear" }));
    expect(await screen.findByText("Usá 3 a 50 letras minúsculas, números o guiones")).toBeVisible();
    expect(api.createTenant).not.toHaveBeenCalled();
  });

  it("enfoca nombre y usuario inicial según el primer dato pendiente", async () => {
    const nameView = renderPlatformPage(<TenantFormPage />, "/platform/tenants/new", "/platform/tenants/new");
    fireEvent.change(screen.getByLabelText("Código"), { target: { value: "academia-centro" } });
    fireEvent.change(screen.getByLabelText("Nombre de usuario"), { target: { value: "tenant-admin" } });
    fireEvent.click(screen.getByRole("button", { name: "Revisar y crear" }));

    const nameError = await screen.findByText("Ingresá un nombre");
    const name = screen.getByLabelText("Nombre");
    await waitFor(() => expect(name).toHaveFocus());
    expect(name).toHaveAttribute("aria-invalid", "true");
    expect(name).toHaveAttribute("aria-describedby", nameError.id);
    nameView.unmount();

    renderPlatformPage(<TenantFormPage />, "/platform/tenants/new", "/platform/tenants/new");
    fireEvent.change(screen.getByLabelText("Código"), { target: { value: "academia-centro" } });
    fireEvent.change(screen.getByLabelText("Nombre"), { target: { value: "Academia Centro" } });
    fireEvent.click(screen.getByRole("button", { name: "Revisar y crear" }));

    const usernameError = await screen.findByText("Ingresá el nombre de usuario inicial");
    const username = screen.getByLabelText("Nombre de usuario");
    await waitFor(() => expect(username).toHaveFocus());
    expect(username).toHaveAttribute("aria-invalid", "true");
    expect(username).toHaveAttribute("aria-describedby", usernameError.id);
    expect(api.createTenant).not.toHaveBeenCalled();
  });

  it("crea tenant + identidad nueva en una operación y entrega activación", async () => {
    const activationUrl = `${window.location.origin}/platform/activate#token=one-time-tenant`;
    renderPlatformPage(<TenantFormPage />, "/platform/tenants/new", "/platform/tenants/new");
    fillNewTenant();
    fireEvent.click(screen.getByRole("button", { name: "Revisar y crear" }));
    expect(await screen.findByRole("dialog", { name: "Crear organización" })).toHaveTextContent("Academia Centro");
    fireEvent.click(screen.getByRole("button", { name: "Crear organización" }));

    expect(await screen.findByText("Organización creada")).toBeVisible();
    expect(screen.getByText(activationUrl)).toBeVisible();
    expect(activationUrl).not.toContain("?token=");
    expect(api.createTenant).toHaveBeenCalledWith({
      code: "academia-centro",
      name: "Academia Centro",
      initialAdmin: { mode: "NEW", nombreUsuario: "tenant-admin" },
    }, expect.objectContaining({ "Idempotency-Key": "idem-tenant" }));
    fireEvent.click(screen.getByRole("button", { name: "Copiar" }));
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(activationUrl);
  });

  it("busca y selecciona una identidad existente antes de crear", async () => {
    api.searchIdentities.mockResolvedValue([{ id: 9, nombreUsuario: "existing-admin", active: true }]);
    api.createTenant.mockResolvedValue({ ...result, activation: undefined });
    renderPlatformPage(<TenantFormPage />, "/platform/tenants/new", "/platform/tenants/new");
    fireEvent.click(screen.getByRole("radio", { name: "Vincular identidad existente" }));
    fireEvent.change(screen.getByLabelText("Código"), { target: { value: "tenant-existing" } });
    fireEvent.change(screen.getByLabelText("Nombre"), { target: { value: "Tenant Existing" } });
    fireEvent.change(screen.getByLabelText("Buscar identidad global"), { target: { value: "existing" } });
    expect(await screen.findByRole("option", { name: /existing-admin/ })).toBeVisible();
    fireEvent.click(screen.getByRole("option", { name: /existing-admin/ }));
    expect(screen.getByRole("option", { name: /existing-admin/ })).toHaveAttribute("aria-selected", "true");
    fireEvent.click(screen.getByRole("button", { name: "Revisar y crear" }));
    fireEvent.click(await screen.findByRole("button", { name: "Crear organización" }));

    await waitFor(() => expect(api.createTenant).toHaveBeenCalledWith(
      expect.objectContaining({ initialAdmin: { mode: "EXISTING", usuarioId: 9 } }),
      expect.anything(),
    ));
    expect(await screen.findByText("Organización creada")).toBeVisible();
    expect(screen.queryByText("Enlace de activación: se muestra una sola vez")).not.toBeInTheDocument();
  });

  it("enfoca la búsqueda cuando falta seleccionar la identidad existente", async () => {
    renderPlatformPage(<TenantFormPage />, "/platform/tenants/new", "/platform/tenants/new");
    fireEvent.click(screen.getByRole("radio", { name: "Vincular identidad existente" }));
    fireEvent.change(screen.getByLabelText("Código"), { target: { value: "tenant-existing" } });
    fireEvent.change(screen.getByLabelText("Nombre"), { target: { value: "Tenant Existing" } });
    fireEvent.click(screen.getByRole("button", { name: "Revisar y crear" }));

    const identityError = await screen.findByText("Seleccioná una identidad existente");
    const search = screen.getByLabelText("Buscar identidad global");
    await waitFor(() => expect(search).toHaveFocus());
    expect(search).toHaveAttribute("aria-invalid", "true");
    expect(search).toHaveAttribute("aria-describedby", identityError.id);
    expect(api.createTenant).not.toHaveBeenCalled();
  });

  it("conserva la idempotency key al reintentar exactamente el mismo payload", async () => {
    api.createTenant.mockRejectedValueOnce(new Error("sin red")).mockResolvedValueOnce(result);
    renderPlatformPage(<TenantFormPage />, "/platform/tenants/new", "/platform/tenants/new");
    fillNewTenant();
    fireEvent.click(screen.getByRole("button", { name: "Revisar y crear" }));
    fireEvent.click(await screen.findByRole("button", { name: "Crear organización" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudo crear la organización.");

    fireEvent.click(screen.getByRole("button", { name: "Revisar y crear" }));
    fireEvent.click(await screen.findByRole("button", { name: "Crear organización" }));
    expect(await screen.findByText("Organización creada")).toBeVisible();
    expect(keys.next).toHaveBeenCalledOnce();
  });

  it("genera otra idempotency key cuando cambia el payload después de un fallo", async () => {
    keys.next.mockReturnValueOnce("idem-first").mockReturnValueOnce("idem-second");
    api.createTenant.mockRejectedValueOnce(new Error("sin red")).mockResolvedValueOnce(result);
    renderPlatformPage(<TenantFormPage />, "/platform/tenants/new", "/platform/tenants/new");
    fillNewTenant();
    fireEvent.click(screen.getByRole("button", { name: "Revisar y crear" }));
    fireEvent.click(await screen.findByRole("button", { name: "Crear organización" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudo crear la organización.");

    fireEvent.change(screen.getByLabelText("Nombre"), { target: { value: "Academia Norte" } });
    fireEvent.click(screen.getByRole("button", { name: "Revisar y crear" }));
    fireEvent.click(await screen.findByRole("button", { name: "Crear organización" }));

    expect(await screen.findByText("Organización creada")).toBeVisible();
    expect(keys.next).toHaveBeenCalledTimes(2);
    expect(api.createTenant).toHaveBeenLastCalledWith(
      expect.objectContaining({ name: "Academia Norte" }),
      expect.anything(),
    );
  });

  it("descarta la confirmación sin ejecutar y navega desde el resultado", async () => {
    renderPlatformPage(<TenantFormPage />, "/platform/tenants/new", "/platform/tenants/new");
    fillNewTenant();
    fireEvent.click(screen.getByRole("button", { name: "Revisar y crear" }));
    fireEvent.click(await screen.findByRole("button", { name: "Cancelar" }));
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(api.createTenant).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: "Revisar y crear" }));
    fireEvent.click(await screen.findByRole("button", { name: "Crear organización" }));
    await screen.findByText("Organización creada");
    fireEvent.click(screen.getByRole("button", { name: "Ver organización" }));
    expect(await screen.findByText("Detalle destino")).toBeVisible();
  });

  it("permite volver al listado desde un alta exitosa", async () => {
    renderPlatformPage(<TenantFormPage />, "/platform/tenants/new", "/platform/tenants/new");
    fillNewTenant();
    fireEvent.click(screen.getByRole("button", { name: "Revisar y crear" }));
    fireEvent.click(await screen.findByRole("button", { name: "Crear organización" }));
    await screen.findByText("Organización creada");
    fireEvent.click(screen.getByRole("button", { name: "Volver al listado" }));
    expect(await screen.findByText("Listado destino")).toBeVisible();
  });
});
