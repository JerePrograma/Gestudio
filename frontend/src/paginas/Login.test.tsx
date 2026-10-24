import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

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

  afterEach(() => vi.unstubAllEnvs());

  const enablePublicDemo = () => {
    vi.stubEnv("VITE_PUBLIC_DEMO_ENABLED", "true");
    vi.stubEnv("VITE_PUBLIC_DEMO_USERNAME", "alpha.demo.presentacion");
    vi.stubEnv("VITE_PUBLIC_DEMO_PASSWORD", "synthetic-read-only-fixture");
  };

  it.each([
    [undefined, "viewer", "synthetic"],
    ["false", "viewer", "synthetic"],
    ["TRUE", "viewer", "synthetic"],
    ["true", "", "synthetic"],
    ["true", "viewer", ""],
  ])("oculta la demo sin habilitación explícita y credenciales completas (%s, %s)", (enabled, username, password) => {
    vi.stubEnv("VITE_PUBLIC_DEMO_ENABLED", enabled);
    vi.stubEnv("VITE_PUBLIC_DEMO_USERNAME", username);
    vi.stubEnv("VITE_PUBLIC_DEMO_PASSWORD", password);
    render(<MemoryRouter><Login /></MemoryRouter>);

    expect(screen.queryByRole("button", { name: "Entrar a la demo" })).not.toBeInTheDocument();
    expect(screen.getByRole("button", { name: "Ingresar" })).toBeVisible();
  });

  it("accede a la cuenta pública con el login habitual sin completar ni persistir contraseñas", async () => {
    enablePublicDemo();
    let finishLogin: (value: null) => void = () => undefined;
    login.mockImplementation(() => new Promise((resolve) => { finishLogin = resolve; }));
    render(<MemoryRouter><Login /></MemoryRouter>);

    fireEvent.click(screen.getByRole("button", { name: "Entrar a la demo" }));

    await waitFor(() => expect(login).toHaveBeenCalledWith(
      "alpha.demo.presentacion", "synthetic-read-only-fixture", undefined,
    ));
    expect(screen.getByRole("button", { name: "Ingresando a la demo…" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Ingresar" })).toBeDisabled();
    expect(screen.getByLabelText("Nombre de Usuario:")).toHaveValue("");
    expect(screen.getByLabelText("Contraseña:")).toHaveValue("");
    expect(localStorage.getItem("contrasena")).toBeNull();

    finishLogin(null);
    await waitFor(() => expect(screen.getByRole("button", { name: "Entrar a la demo" })).toBeEnabled());
  });

  it("permite reintentar la demo si falla el acceso sin mostrar detalles internos", async () => {
    enablePublicDemo();
    login.mockRejectedValueOnce(new Error("private backend diagnostic"));
    render(<MemoryRouter><Login /></MemoryRouter>);

    fireEvent.click(screen.getByRole("button", { name: "Entrar a la demo" }));
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudo iniciar sesión");
    expect(screen.queryByText("private backend diagnostic")).not.toBeInTheDocument();
    await waitFor(() => expect(screen.getByRole("button", { name: "Entrar a la demo" })).toBeEnabled());

    login.mockResolvedValueOnce(null);
    fireEvent.click(screen.getByRole("button", { name: "Entrar a la demo" }));
    await waitFor(() => expect(login).toHaveBeenCalledTimes(2));
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
