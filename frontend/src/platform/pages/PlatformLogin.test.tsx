import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const auth = vi.hoisted(() => ({
  isAuth: false,
  scope: null as null | "TENANT" | "PLATFORM",
  platformLogin: vi.fn(),
}));

vi.mock("../../hooks/context/useAuth", () => ({ useAuth: () => auth }));

import PlatformLogin from "./PlatformLogin";

const renderLogin = () => render(
  <MemoryRouter initialEntries={["/platform/login"]}>
    <Routes>
      <Route path="/platform/login" element={<PlatformLogin />} />
      <Route path="/platform/tenants" element={<p>Organizaciones</p>} />
    </Routes>
  </MemoryRouter>,
);

describe("PlatformLogin", () => {
  beforeEach(() => {
    auth.isAuth = false;
    auth.scope = null;
    auth.platformLogin.mockReset();
    auth.platformLogin.mockResolvedValue(undefined);
  });

  it("envía contraseña y TOTP juntos y navega sólo después del éxito", async () => {
    renderLogin();
    fireEvent.change(screen.getByLabelText("Nombre de usuario"), { target: { value: "global-admin" } });
    fireEvent.change(screen.getByLabelText("Contraseña"), { target: { value: "correct-horse" } });
    fireEvent.change(screen.getByLabelText("Código TOTP"), { target: { value: "123456" } });
    fireEvent.click(screen.getByRole("button", { name: "Acceder al control plane" }));

    await waitFor(() => expect(auth.platformLogin).toHaveBeenCalledWith(
      "global-admin",
      "correct-horse",
      "TOTP",
      "123456",
    ));
    expect(await screen.findByText("Organizaciones")).toBeVisible();
  });

  it("permite recovery explícito y no acepta un TOTP incompleto", async () => {
    const view = renderLogin();
    fireEvent.change(screen.getByLabelText("Nombre de usuario"), { target: { value: "global-admin" } });
    fireEvent.change(screen.getByLabelText("Contraseña"), { target: { value: "correct-horse" } });
    fireEvent.change(screen.getByLabelText("Código TOTP"), { target: { value: "123" } });
    fireEvent.click(screen.getByRole("button", { name: "Acceder al control plane" }));
    const codeError = await screen.findByText("Ingresá los 6 dígitos");
    const codeInput = screen.getByLabelText("Código TOTP");
    expect(codeError).toBeVisible();
    await waitFor(() => expect(codeInput).toHaveFocus());
    expect(codeInput).toHaveAttribute("aria-invalid", "true");
    expect(codeInput).toHaveAttribute("aria-describedby", codeError.id);
    expect(auth.platformLogin).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("radio", { name: "Recuperación" }));
    fireEvent.change(screen.getByLabelText("Código de recuperación"), { target: { value: "RECOVERY-1234" } });
    fireEvent.click(screen.getByRole("button", { name: "Acceder al control plane" }));
    await waitFor(() => expect(auth.platformLogin).toHaveBeenCalledWith(
      "global-admin",
      "correct-horse",
      "RECOVERY",
      "RECOVERY-1234",
    ));
    view.unmount();
  });

  it("enfoca contraseña y usuario según el primer dato inválido", async () => {
    const passwordView = renderLogin();
    fireEvent.change(screen.getByLabelText("Nombre de usuario"), { target: { value: "global-admin" } });
    fireEvent.change(screen.getByLabelText("Código TOTP"), { target: { value: "123456" } });
    fireEvent.click(screen.getByRole("button", { name: "Acceder al control plane" }));

    const passwordError = await screen.findByText("Ingresá tu contraseña");
    const password = screen.getByLabelText("Contraseña");
    await waitFor(() => expect(password).toHaveFocus());
    expect(password).toHaveAttribute("aria-invalid", "true");
    expect(password).toHaveAttribute("aria-describedby", passwordError.id);
    passwordView.unmount();

    renderLogin();
    fireEvent.change(screen.getByLabelText("Contraseña"), { target: { value: "correct-horse" } });
    fireEvent.change(screen.getByLabelText("Código TOTP"), { target: { value: "123456" } });
    fireEvent.click(screen.getByRole("button", { name: "Acceder al control plane" }));

    const usernameError = await screen.findByText("Ingresá tu usuario");
    const username = screen.getByLabelText("Nombre de usuario");
    await waitFor(() => expect(username).toHaveFocus());
    expect(username).toHaveAttribute("aria-invalid", "true");
    expect(username).toHaveAttribute("aria-describedby", usernameError.id);
    expect(auth.platformLogin).not.toHaveBeenCalled();
  });

  it("muestra un rechazo seguro, recorta credenciales y conserva el formulario", async () => {
    auth.platformLogin.mockRejectedValue(new Error("credenciales rechazadas"));
    renderLogin();

    fireEvent.change(screen.getByLabelText("Nombre de usuario"), { target: { value: "  global-admin  " } });
    fireEvent.change(screen.getByLabelText("Contraseña"), { target: { value: "correct-horse" } });
    fireEvent.click(screen.getByRole("radio", { name: "Recuperación" }));
    fireEvent.change(screen.getByLabelText("Código de recuperación"), { target: { value: "  RECOVERY-1234  " } });
    fireEvent.click(screen.getByRole("button", { name: "Acceder al control plane" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "No se pudo validar el acceso de plataforma",
    );
    expect(auth.platformLogin).toHaveBeenCalledWith(
      "global-admin",
      "correct-horse",
      "RECOVERY",
      "RECOVERY-1234",
    );
    expect(screen.queryByText("Organizaciones")).not.toBeInTheDocument();
  });

  it("no redirige una sesión tenant y adapta el campo al método de recuperación", () => {
    auth.isAuth = true;
    auth.scope = "TENANT";
    renderLogin();

    const totp = screen.getByLabelText("Código TOTP");
    expect(totp).toHaveAttribute("inputmode", "numeric");
    expect(totp).toHaveAttribute("maxlength", "6");
    expect(totp).toHaveAttribute("placeholder", "000000");

    fireEvent.click(screen.getByRole("radio", { name: "Recuperación" }));
    const recovery = screen.getByLabelText("Código de recuperación");
    expect(recovery).toHaveAttribute("inputmode", "text");
    expect(recovery).toHaveAttribute("maxlength", "80");
    expect(recovery).toHaveAttribute("placeholder", "Código de un solo uso");
    expect(screen.queryByText("Organizaciones")).not.toBeInTheDocument();
  });

  it("redirige inmediatamente una sesión PLATFORM ya autenticada", async () => {
    auth.isAuth = true;
    auth.scope = "PLATFORM";
    renderLogin();

    expect(await screen.findByText("Organizaciones")).toBeVisible();
    expect(auth.platformLogin).not.toHaveBeenCalled();
  });
});
