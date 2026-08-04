import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const login = vi.hoisted(() => vi.fn());

vi.mock("../hooks/context/useAuth", () => ({
  useAuth: () => ({ login }),
}));

vi.mock("../rutas/routes", () => ({
  prefetch: { dashboard: vi.fn() },
}));

import Login from "./Login";

describe("Login", () => {
  beforeEach(() => {
    login.mockReset();
  });

  it("valida campos y envía las credenciales", async () => {
    login.mockResolvedValue(null);
    render(
      <MemoryRouter initialEntries={["/login"]}>
        <Login />
      </MemoryRouter>
    );

    fireEvent.click(screen.getByRole("button", { name: "Ingresar" }));
    expect(await screen.findByText("Nombre de Usuario es requerido")).toBeVisible();
    expect(screen.getByText("Contraseña es requerida")).toBeVisible();

    fireEvent.change(screen.getByLabelText("Nombre de Usuario:"), {
      target: { value: "admin" },
    });
    fireEvent.change(screen.getByLabelText("Contraseña:"), {
      target: { value: "secret" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Ingresar" }));

    await waitFor(() => expect(login).toHaveBeenCalledWith("admin", "secret", undefined));
  });

  it("selecciona una membership múltiple sin persistir credenciales ni tenant", async () => {
    login
      .mockResolvedValueOnce({
        selectionRequired: true,
        tenants: [
          {
            id: "00000000-0000-0000-0000-0000000000a1",
            codigo: "ACADEMIA_A",
            nombre: "Academia A",
            estado: "ACTIVE",
          },
          {
            id: "00000000-0000-0000-0000-0000000000b2",
            codigo: "ACADEMIA_B",
            nombre: "Academia B",
            estado: "ACTIVE",
          },
        ],
      })
      .mockResolvedValueOnce(null);
    localStorage.setItem("unrelated", "keep-me");

    render(
      <MemoryRouter initialEntries={["/login"]}>
        <Login />
      </MemoryRouter>,
    );

    fireEvent.change(screen.getByLabelText("Nombre de Usuario:"), {
      target: { value: "multi" },
    });
    fireEvent.change(screen.getByLabelText("Contraseña:"), {
      target: { value: "not-persisted" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Ingresar" }));

    const select = await screen.findByRole("combobox", { name: "Organización:" });
    fireEvent.change(select, {
      target: { value: "00000000-0000-0000-0000-0000000000b2" },
    });
    fireEvent.click(screen.getByRole("button", { name: "Ingresar a la organización" }));

    await waitFor(() => expect(login).toHaveBeenLastCalledWith(
      "multi",
      "not-persisted",
      "00000000-0000-0000-0000-0000000000b2",
    ));
    expect(localStorage.getItem("contrasena")).toBeNull();
    expect(localStorage.getItem("tenantId")).toBeNull();
    expect(localStorage.getItem("unrelated")).toBe("keep-me");
  });
});
