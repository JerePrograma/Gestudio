import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const auth = vi.hoisted(() => ({
  platformUser: { nombreUsuario: "global-admin" } as null | { nombreUsuario: string },
  logout: vi.fn(),
}));
const theme = vi.hoisted(() => ({ resolvedTheme: "light", setTheme: vi.fn() }));

vi.mock("../hooks/context/useAuth", () => ({ useAuth: () => auth }));
vi.mock("next-themes", () => ({
  ThemeProvider: ({ children }: { children: React.ReactNode }) => children,
  useTheme: () => theme,
}));
vi.mock("./StepUpProvider", () => ({
  StepUpProvider: ({ children }: { children: React.ReactNode }) => children,
}));

import PlatformLayout from "./PlatformLayout";

const renderLayout = (path: string) => render(
  <MemoryRouter initialEntries={[path]}>
    <Routes>
      <Route element={<PlatformLayout />}>
        <Route path="*" element={<p>Contenido de control</p>} />
      </Route>
    </Routes>
  </MemoryRouter>,
);

describe("PlatformLayout", () => {
  beforeEach(() => {
    auth.platformUser = { nombreUsuario: "global-admin" };
    auth.logout.mockReset();
    auth.logout.mockResolvedValue(undefined);
    theme.resolvedTheme = "light";
    theme.setTheme.mockReset();
  });

  it.each([
    ["/platform/tenants/new", "Nueva organización"],
    ["/platform/tenants/tenant-1", "Detalle de organización"],
    ["/platform/admins", "Administradores"],
    ["/platform/unknown", "Control plane"],
  ])("muestra el título contextual para %s", (path, title) => {
    renderLayout(path);
    expect(screen.getAllByText(title).length).toBeGreaterThan(0);
    expect(screen.getByText("global-admin")).toBeVisible();
    expect(screen.getByText("Contenido de control")).toBeVisible();
    expect(screen.getByRole("link", { name: "Saltar al contenido" })).toHaveAttribute("href", "#platform-main");
    expect(screen.getByRole("main")).toHaveAttribute("tabindex", "-1");
  });

  it("abre, navega y cierra el menú móvil", () => {
    renderLayout("/platform/tenants");
    const trigger = screen.getByRole("button", { name: "Abrir menú" });
    fireEvent.click(trigger);
    expect(trigger).toHaveAttribute("aria-expanded", "true");
    expect(screen.getByRole("dialog", { name: "Control plane" })).toBeVisible();

    fireEvent.click(screen.getByRole("link", { name: "Auditoría" }));
    expect(screen.queryByRole("button", { name: "Cerrar menú" })).not.toBeInTheDocument();
  });

  it("encierra el foco, cierra con Escape y devuelve el foco al disparador", async () => {
    renderLayout("/platform/tenants");
    const trigger = screen.getByRole("button", { name: "Abrir menú" });
    const outsideButton = screen.getByRole("button", { name: "Usar tema oscuro" });
    trigger.focus();
    fireEvent.click(trigger);

    const closeButton = screen.getByRole("button", { name: "Cerrar menú" });
    await waitFor(() => expect(closeButton).toHaveFocus());

    outsideButton.focus();
    expect(closeButton).toHaveFocus();

    fireEvent.keyDown(document, { key: "Escape" });
    await waitFor(() => expect(screen.queryByRole("dialog", { name: "Control plane" })).not.toBeInTheDocument());
    expect(trigger).toHaveFocus();
  });

  it("alterna ambos temas y tolera el rechazo seguro del logout", async () => {
    const light = renderLayout("/platform/tenants");
    fireEvent.click(screen.getByRole("button", { name: "Usar tema oscuro" }));
    expect(theme.setTheme).toHaveBeenCalledWith("dark");
    auth.logout.mockRejectedValueOnce(new Error("red"));
    fireEvent.click(screen.getAllByRole("button", { name: "Cerrar sesión" })[0]);
    await waitFor(() => expect(auth.logout).toHaveBeenCalledOnce());
    light.unmount();

    theme.resolvedTheme = "dark";
    auth.platformUser = null;
    renderLayout("/platform/audit");
    fireEvent.click(screen.getByRole("button", { name: "Usar tema claro" }));
    expect(theme.setTheme).toHaveBeenCalledWith("light");
  });
});
