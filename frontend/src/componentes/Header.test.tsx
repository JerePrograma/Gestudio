import * as Dialog from "@radix-ui/react-dialog";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  closeModal: vi.fn(),
  isExpanded: true,
  modalOpen: false,
  resolvedTheme: "dark",
  setMobileSidebarOpen: vi.fn(),
  setTheme: vi.fn(),
  switchTenant: vi.fn(),
  toastError: vi.fn(),
  user: {
    nombreUsuario: " operador ",
    roles: ["CAJA"],
    tenantActivo: { id: "tenant-a", nombre: "Academia A", codigo: "a", estado: "ACTIVE" },
    tenantsDisponibles: [
      { id: "tenant-a", nombre: "Academia A", codigo: "a", estado: "ACTIVE" },
      { id: "tenant-b", nombre: "Academia B", codigo: "b", estado: "ACTIVE" },
      { id: "tenant-c", nombre: "Suspendida", codigo: "c", estado: "SUSPENDED" },
    ],
  },
}));

vi.mock("next-themes", () => ({
  useTheme: () => ({ resolvedTheme: mocks.resolvedTheme, setTheme: mocks.setTheme }),
}));
vi.mock("../hooks/context/useSidebar", () => ({
  useSidebar: () => ({ isExpanded: mocks.isExpanded, mobileSidebarOpen: false }),
}));
vi.mock("../hooks/context/useAuth", () => ({
  useAuth: () => ({ user: mocks.user, switchTenant: mocks.switchTenant }),
}));
vi.mock("./NotificacionesModal", () => ({
  default: ({ isOpen, onClose }: { isOpen: boolean; onClose: () => void }) => isOpen
    ? <div role="dialog"><button onClick={onClose}>Cerrar avisos</button></div>
    : null,
}));
vi.mock("react-toastify", () => ({ toast: { error: mocks.toastError } }));

import Header from "./Header";

describe("Header", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.isExpanded = true;
    mocks.resolvedTheme = "dark";
    mocks.switchTenant.mockResolvedValue(undefined);
  });

  it("deriva el título, usuario y organizaciones activas desde la sesión", () => {
    renderHeader("/alumnos/formulario?id=3");

    expect(screen.getByText("Alumnos")).toBeVisible();
    expect(screen.getByText("operador")).toBeVisible();
    expect(screen.getByText("CAJA")).toBeVisible();
    expect(screen.getByLabelText("Organización activa")).toHaveValue("tenant-a");
    expect(screen.queryByRole("option", { name: "Suspendida" })).not.toBeInTheDocument();
  });

  it("abre el menú móvil, alterna el tema y controla el modal", () => {
    renderHeader("/");

    fireEvent.click(screen.getByRole("button", { name: "Abrir menú" }));
    expect(mocks.setMobileSidebarOpen).toHaveBeenCalledWith(true);
    fireEvent.click(screen.getByRole("button", { name: "Usar tema claro" }));
    expect(mocks.setTheme).toHaveBeenCalledWith("light");

    fireEvent.click(screen.getByRole("button", { name: "Notificaciones" }));
    expect(screen.getByRole("dialog")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Cerrar avisos" }));
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
  });

  it("cambia de organización y comunica un rechazo", async () => {
    mocks.switchTenant.mockRejectedValueOnce(new Error("revoked"));
    renderHeader("/ruta-no-registrada");

    expect(screen.getByText("Panel administrativo")).toBeVisible();
    fireEvent.change(screen.getByLabelText("Organización activa"), { target: { value: "tenant-b" } });

    await waitFor(() => expect(mocks.switchTenant).toHaveBeenCalledWith("tenant-b"));
    await waitFor(() => expect(mocks.toastError).toHaveBeenCalledWith(
      "No se pudo cambiar de organización. Volvé a iniciar sesión si tu acceso fue revocado.",
    ));
  });
});

function renderHeader(entry: string) {
  render(
    <Dialog.Root onOpenChange={mocks.setMobileSidebarOpen}>
      <MemoryRouter initialEntries={[entry]}><Header /></MemoryRouter>
    </Dialog.Root>,
  );
}
