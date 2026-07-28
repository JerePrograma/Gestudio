import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { describe, expect, it, vi } from "vitest";

const login = vi.hoisted(() => vi.fn());

vi.mock("../hooks/context/useAuth", () => ({
  useAuth: () => ({ login }),
}));

vi.mock("../rutas/routes", () => ({
  prefetch: { dashboard: vi.fn() },
}));

import Login from "./Login";

describe("Login", () => {
  it("valida campos y envía las credenciales", async () => {
    login.mockResolvedValue(undefined);
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

    await waitFor(() => expect(login).toHaveBeenCalledWith("admin", "secret"));
  });
});
