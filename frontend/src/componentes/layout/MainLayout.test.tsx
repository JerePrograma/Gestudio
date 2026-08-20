import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { SidebarProvider } from "../../hooks/context/SideBarContext";

const auth = vi.hoisted(() => ({
  hasPermission: vi.fn(() => true),
  logout: vi.fn(),
  switchTenant: vi.fn(),
  user: {
    nombreUsuario: "operador",
    roles: ["ADMIN"],
    tenantActivo: { id: "tenant-a", nombre: "Academia A", codigo: "a", estado: "ACTIVE" },
    tenantsDisponibles: [
      { id: "tenant-a", nombre: "Academia A", codigo: "a", estado: "ACTIVE" },
    ],
  },
}));
const theme = vi.hoisted(() => ({ resolvedTheme: "light", setTheme: vi.fn() }));

vi.mock("../../hooks/context/useAuth", () => ({ useAuth: () => auth }));
vi.mock("next-themes", () => ({
  ThemeProvider: ({ children }: { children: React.ReactNode }) => children,
  useTheme: () => theme,
}));
vi.mock("../NotificacionesModal", () => ({ default: () => null }));

import MainLayout from "./MainLayout";

describe("MainLayout", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    auth.logout.mockResolvedValue(undefined);
    auth.switchTenant.mockResolvedValue(undefined);
  });

  it("ofrece un destino enfocable para saltar al contenido", () => {
    renderLayout();

    expect(screen.getByRole("link", { name: "Saltar al contenido" })).toHaveAttribute("href", "#main-content");
    const main = screen.getByRole("main");
    expect(main).toHaveAttribute("tabindex", "-1");
    expect(main).toHaveClass("md:pl-[calc(var(--sidebar-width)+var(--container-padding))]");

    fireEvent.click(screen.getByRole("button", { name: "Colapsar menú" }));

    expect(main).toHaveClass("md:pl-[calc(var(--sidebar-width-collapsed)+var(--container-padding))]");
  });

  it("encierra el foco del menú móvil, cierra con Escape y lo devuelve al disparador", async () => {
    renderLayout();
    const trigger = screen.getByRole("button", { name: "Abrir menú" });
    const outsideButton = screen.getByRole("button", { name: "Usar tema oscuro" });
    expect(trigger).toHaveAttribute("aria-controls", "tenant-mobile-navigation");
    expect(trigger).toHaveAttribute("aria-expanded", "false");
    trigger.focus();
    fireEvent.click(trigger);

    expect(trigger).toHaveAttribute("aria-expanded", "true");
    expect(screen.getByRole("dialog", { name: "Menú principal" })).toBeVisible();
    const closeButton = screen.getByRole("button", { name: "Cerrar menú" });
    await waitFor(() => expect(closeButton).toHaveFocus());

    outsideButton.focus();
    expect(closeButton).toHaveFocus();

    fireEvent.keyDown(document, { key: "Escape" });
    await waitFor(() => expect(screen.queryByRole("dialog", { name: "Menú principal" })).not.toBeInTheDocument());
    expect(trigger).toHaveFocus();
  });
});

function renderLayout() {
  render(
    <MemoryRouter initialEntries={["/"]}>
      <SidebarProvider>
        <Routes>
          <Route element={<MainLayout />}>
            <Route path="/" element={<p>Contenido principal</p>} />
          </Route>
        </Routes>
      </SidebarProvider>
    </MemoryRouter>,
  );
}
