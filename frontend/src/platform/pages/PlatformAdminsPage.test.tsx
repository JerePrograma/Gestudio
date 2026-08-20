import { fireEvent, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { renderPlatformPage } from "../../test/renderPlatformPage";
import { platformActivationUrl } from "../activationLink";

const api = vi.hoisted(() => ({
  listAdmins: vi.fn(),
  grantAdmin: vi.fn(),
  changeAdminStatus: vi.fn(),
  resetAdminMfa: vi.fn(),
}));
const stepUp = vi.hoisted(() => ({
  executeWithStepUp: vi.fn(async (_descriptor, operation) => operation({
    "Idempotency-Key": "idem-1",
    "X-Step-Up-Token": "proof-1",
  })),
}));

vi.mock("../platformApi", () => ({
  platformApi: api,
  newIdempotencyKey: () => "idem-1",
}));
vi.mock("../stepUpContext", () => ({ useStepUp: () => stepUp }));
vi.mock("../../hooks/context/useAuth", () => ({
  useAuth: () => ({ platformUser: { id: 1, nombreUsuario: "active-admin" } }),
}));

import PlatformAdminsPage from "./PlatformAdminsPage";

const page = {
  content: [
    { usuarioId: 1, nombreUsuario: "active-admin", status: "ACTIVE", mfaEnabled: true, createdAt: "2030-01-01T00:00:00Z", version: 3 },
    { usuarioId: 2, nombreUsuario: "pending-admin", status: "ACTIVE", mfaEnabled: false, version: 1 },
    { usuarioId: 3, nombreUsuario: "revoked-admin", status: "REVOKED", mfaEnabled: false, version: 2 },
  ],
  totalElements: 3,
  totalPages: 2,
  number: 0,
  size: 25,
};

describe("PlatformAdminsPage", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.listAdmins.mockResolvedValue(page);
    api.grantAdmin.mockResolvedValue({
      admin: page.content[1],
      activation: { token: "one-time-admin", expiresAt: "2030-02-01T00:00:00Z" },
    });
    api.changeAdminStatus.mockResolvedValue(undefined);
    api.resetAdminMfa.mockResolvedValue({ token: "reset-token", expiresAt: "2030-02-01T00:00:00Z" });
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText: vi.fn().mockResolvedValue(undefined) },
    });
  });

  it("renderiza estados, MFA y ausencia de acciones para revocados", async () => {
    renderPlatformPage(<PlatformAdminsPage />);
    expect(await screen.findByText("Administradores de plataforma")).toBeVisible();
    expect(screen.getAllByText("Configurado").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Pendiente").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Sin acciones").length).toBeGreaterThan(0);
    expect(
      screen.getAllByText("MFA propio: recuperación asistida"),
    ).toHaveLength(2);
    expect(screen.queryByRole("button", { name: "Reiniciar MFA de active-admin" })).not.toBeInTheDocument();
    expect(screen.getAllByText("—").length).toBeGreaterThan(0);
  });

  it("valida el ID y otorga acceso mostrando el secreto una sola vez", async () => {
    renderPlatformPage(<PlatformAdminsPage />);
    await screen.findByText("Administradores de plataforma");
    const input = screen.getByLabelText("ID de identidad global");
    fireEvent.change(input, { target: { value: "0" } });
    fireEvent.click(screen.getByRole("button", { name: "Otorgar acceso" }));
    const fieldError = await screen.findByRole("alert");
    expect(fieldError).toHaveTextContent("Ingresá un ID de identidad válido.");
    expect(input).toHaveFocus();
    expect(input).toHaveAttribute("aria-invalid", "true");
    expect(input).toHaveAttribute("aria-describedby", fieldError.id);
    expect(api.grantAdmin).not.toHaveBeenCalled();

    fireEvent.change(input, { target: { value: "42" } });
    expect(input).toHaveAttribute("aria-invalid", "false");
    expect(input).not.toHaveAttribute("aria-describedby");
    fireEvent.click(screen.getByRole("button", { name: "Otorgar acceso" }));
    const activationUrl = platformActivationUrl("one-time-admin");
    expect(await screen.findByText(activationUrl)).toBeVisible();
    expect(api.grantAdmin).toHaveBeenCalledWith({ usuarioId: 42 }, expect.objectContaining({ "Idempotency-Key": "idem-1" }));
    fireEvent.click(screen.getByRole("button", { name: "Copiar" }));
    expect(navigator.clipboard.writeText).toHaveBeenCalledWith(activationUrl);
    fireEvent.click(screen.getByRole("button", { name: "Descartar token de activación" }));
    expect(screen.queryByText(activationUrl)).not.toBeInTheDocument();
  });

  it("revoca acceso y reinicia MFA mediante confirmación step-up", async () => {
    renderPlatformPage(<PlatformAdminsPage />);
    await screen.findAllByText("active-admin");
    fireEvent.click(screen.getAllByRole("button", { name: "Revocar a active-admin" })[0]);
    expect(screen.getByRole("dialog", { name: "Revocar acceso de plataforma" })).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Revocar acceso" }));
    await waitFor(() => expect(api.changeAdminStatus).toHaveBeenCalledWith(
      1,
      expect.objectContaining({ status: "REVOKED", expectedVersion: 3 }),
      expect.anything(),
    ));
    await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());

    fireEvent.click(screen.getAllByRole("button", { name: "Reiniciar MFA de pending-admin" })[0]);
    expect(screen.getByRole("dialog", { name: "Reiniciar segundo factor" })).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Reiniciar MFA" }));
    expect(await screen.findByText(platformActivationUrl("reset-token"))).toBeVisible();
    expect(api.resetAdminMfa).toHaveBeenCalledWith(2, expect.anything());
  });

  it("informa fallos de alta y de una acción confirmada", async () => {
    api.grantAdmin.mockRejectedValueOnce(new Error("interno"));
    renderPlatformPage(<PlatformAdminsPage />);
    await screen.findAllByText("active-admin");
    fireEvent.change(screen.getByLabelText("ID de identidad global"), { target: { value: "5" } });
    fireEvent.click(screen.getByRole("button", { name: "Otorgar acceso" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudo otorgar el acceso de plataforma.");

    api.changeAdminStatus.mockRejectedValueOnce(new Error("interno"));
    fireEvent.click(screen.getAllByRole("button", { name: "Revocar a active-admin" })[0]);
    fireEvent.click(screen.getByRole("button", { name: "Revocar acceso" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudo completar la acción sobre el administrador.");
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  it("filtra, pagina y permite reintentar la carga", async () => {
    renderPlatformPage(<PlatformAdminsPage />);
    await screen.findAllByText("active-admin");
    fireEvent.click(screen.getByRole("button", { name: "Siguiente" }));
    await waitFor(() => expect(api.listAdmins).toHaveBeenCalledWith(expect.objectContaining({ page: 1 })));
    await screen.findAllByText("active-admin");
    fireEvent.change(screen.getByPlaceholderText("Buscar por usuario"), { target: { value: "active" } });
    await screen.findAllByText("active-admin");
    fireEvent.change(screen.getByLabelText("Estado"), { target: { value: "REVOKED" } });
    await waitFor(() => expect(api.listAdmins).toHaveBeenCalledWith(expect.objectContaining({ page: 0, status: "REVOKED" })));
  });

  it("muestra un estado recuperable cuando la consulta falla", async () => {
    api.listAdmins.mockRejectedValueOnce(new Error("sin red")).mockResolvedValueOnce(page);
    renderPlatformPage(<PlatformAdminsPage />);
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudieron cargar los administradores.");
    fireEvent.click(screen.getByRole("button", { name: "Reintentar" }));
    expect((await screen.findAllByText("active-admin"))[0]).toBeVisible();
  });
});
