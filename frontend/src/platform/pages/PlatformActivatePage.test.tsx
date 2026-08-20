import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const activateIdentity = vi.hoisted(() => vi.fn());
vi.mock("../platformApi", () => ({ platformApi: { activateIdentity } }));

import PlatformActivatePage from "./PlatformActivatePage";

const ActivationRoute = () => {
  const location = useLocation();
  return <><output data-testid="activation-location">{location.search}{location.hash}</output><PlatformActivatePage /></>;
};

const renderActivation = (url = "/platform/activate#token=one-time-token") => render(
  <MemoryRouter initialEntries={[url]}>
    <Routes><Route path="/platform/activate" element={<ActivationRoute />} /></Routes>
  </MemoryRouter>,
);

describe("PlatformActivatePage", () => {
  beforeEach(() => {
    activateIdentity.mockReset();
  });

  it("envía enrollment TOTP sin persistir el token y muestra recovery codes una vez", async () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText },
    });
    activateIdentity.mockResolvedValue({ recoveryCodes: ["CODE-A", "CODE-B"] });
    renderActivation();

    await waitFor(() => {
      expect(screen.getByTestId("activation-location")).toHaveTextContent(/^$/);
    });
    fireEvent.change(screen.getByLabelText("Secreto Base32"), { target: { value: "abcd efgh ijkl mnop qrst uvwx yz23 4567" } });
    fireEvent.change(screen.getByLabelText("Código TOTP"), { target: { value: "123456" } });
    fireEvent.click(screen.getByRole("button", { name: "Completar activación" }));

    await waitFor(() => expect(activateIdentity).toHaveBeenCalledWith({
      token: "one-time-token",
      totpSecret: "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567",
      totpCode: "123456",
    }));
    expect(await screen.findByText("CODE-A")).toBeVisible();
    expect(screen.getByText("CODE-B")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Copiar códigos" }));
    expect(writeText).toHaveBeenCalledWith("CODE-A\nCODE-B");
    expect(localStorage.length).toBe(0);
  });

  it("activa una identidad tenant con contraseña y sin campos TOTP", async () => {
    activateIdentity.mockResolvedValue({ recoveryCodes: [] });
    renderActivation();
    fireEvent.click(screen.getByRole("radio", { name: "Activar identidad tenant" }));
    fireEvent.change(screen.getByLabelText(/^Contraseña nueva/), { target: { value: "tenant-password-strong" } });
    fireEvent.change(screen.getByLabelText("Confirmar contraseña"), { target: { value: "tenant-password-strong" } });
    fireEvent.click(screen.getByRole("button", { name: "Completar activación" }));

    await waitFor(() => expect(activateIdentity).toHaveBeenCalledWith({
      token: "one-time-token",
      password: "tenant-password-strong",
    }));
    expect(await screen.findByText("Identidad activada")).toBeVisible();
  });

  it("rechaza el submit programático cuando falta el token", async () => {
    renderActivation("/platform/activate");

    const submit = screen.getByRole("button", { name: "Completar activación" });
    expect(submit).toBeDisabled();
    fireEvent.submit(submit.closest("form")!);

    expect((await screen.findAllByRole("alert")).map((alert) => alert.textContent))
      .toContain("El enlace no contiene un token de activación.");
    expect(activateIdentity).not.toHaveBeenCalled();
  });

  it("no acepta tokens por query y limpia toda query no soportada antes de mostrar la página", async () => {
    renderActivation("/platform/activate?token=query-token&next=https%3A%2F%2Fevil.example");

    await waitFor(() => {
      expect(screen.getByTestId("activation-location")).toHaveTextContent(/^$/);
    });
    expect(screen.getByRole("button", { name: "Completar activación" })).toBeDisabled();
    expect(screen.getByRole("alert")).toHaveTextContent(
      "El enlace no contiene un token de activación.",
    );
    expect(activateIdentity).not.toHaveBeenCalled();
  });

  it("usa exclusivamente el token del fragmento y limpia query y fragmento", async () => {
    activateIdentity.mockResolvedValue({ recoveryCodes: [] });
    renderActivation("/platform/activate?token=query-token#token=fragment-token");

    await waitFor(() => {
      expect(screen.getByTestId("activation-location")).toHaveTextContent(/^$/);
    });
    fireEvent.click(screen.getByRole("radio", { name: "Activar identidad tenant" }));
    fireEvent.change(screen.getByLabelText(/^Contraseña nueva/), { target: { value: "tenant-password-strong" } });
    fireEvent.change(screen.getByLabelText("Confirmar contraseña"), { target: { value: "tenant-password-strong" } });
    fireEvent.click(screen.getByRole("button", { name: "Completar activación" }));

    await waitFor(() => expect(activateIdentity).toHaveBeenCalledWith({
      token: "fragment-token",
      password: "tenant-password-strong",
    }));
  });

  it("valida confirmación, contraseña tenant y enrollment MFA antes de llamar la API", async () => {
    const mismatch = renderActivation();
    fireEvent.change(screen.getByLabelText(/^Contraseña nueva/), { target: { value: "password-one" } });
    fireEvent.change(screen.getByLabelText("Confirmar contraseña"), { target: { value: "password-two" } });
    fireEvent.submit(screen.getByRole("button", { name: "Completar activación" }).closest("form")!);
    const mismatchError = await screen.findByRole("alert");
    const confirmation = screen.getByLabelText("Confirmar contraseña");
    expect(mismatchError).toHaveTextContent("Las contraseñas no coinciden.");
    expect(confirmation).toHaveFocus();
    expect(confirmation).toHaveAttribute("aria-describedby", mismatchError.id);
    mismatch.unmount();

    const identity = renderActivation();
    fireEvent.click(screen.getByRole("radio", { name: "Activar identidad tenant" }));
    fireEvent.submit(screen.getByRole("button", { name: "Completar activación" }).closest("form")!);
    const identityError = await screen.findByRole("alert");
    const password = screen.getByLabelText("Contraseña nueva");
    expect(identityError).toHaveTextContent(
      "Ingresá y confirmá una contraseña nueva.",
    );
    expect(password).toHaveFocus();
    expect(password).toHaveAttribute("aria-invalid", "true");
    identity.unmount();

    renderActivation();
    fireEvent.click(screen.getByRole("radio", { name: "Activar identidad tenant" }));
    fireEvent.click(screen.getByRole("radio", { name: "Configurar MFA de plataforma" }));
    fireEvent.submit(screen.getByRole("button", { name: "Completar activación" }).closest("form")!);
    const secretError = await screen.findByRole("alert");
    const secret = screen.getByLabelText("Secreto Base32");
    expect(secretError).toHaveTextContent(
      "Ingresá el secreto Base32 y el código TOTP actual de 6 dígitos.",
    );
    expect(secret).toHaveFocus();
    expect(secret).toHaveAttribute("aria-invalid", "true");

    fireEvent.change(secret, { target: { value: "ABCDEF" } });
    fireEvent.change(screen.getByLabelText("Código TOTP"), { target: { value: "123" } });
    fireEvent.submit(screen.getByRole("button", { name: "Completar activación" }).closest("form")!);
    const mfaError = await screen.findByRole("alert");
    const totp = screen.getByLabelText("Código TOTP");
    expect(mfaError).toHaveTextContent(
      "Ingresá el secreto Base32 y el código TOTP actual de 6 dígitos.",
    );
    expect(totp).toHaveFocus();
    expect(totp).toHaveAttribute("aria-describedby", mfaError.id);
    expect(activateIdentity).not.toHaveBeenCalled();
  });

  it("orienta una activación tenant inválida hacia el modo MFA sin filtrar el token", async () => {
    activateIdentity.mockRejectedValue({
      isAxiosError: true,
      response: {
        status: 400,
        data: {
          timestamp: "2030-01-01T00:00:00Z",
          status: 400,
          code: "ACTIVATION_MODE_INVALID",
          message: "El enlace requiere MFA",
          fieldErrors: [],
        },
      },
    });
    renderActivation();
    fireEvent.click(screen.getByRole("radio", { name: "Activar identidad tenant" }));
    fireEvent.change(screen.getByLabelText(/^Contraseña nueva/), { target: { value: "tenant-password-strong" } });
    fireEvent.change(screen.getByLabelText("Confirmar contraseña"), { target: { value: "tenant-password-strong" } });
    fireEvent.click(screen.getByRole("button", { name: "Completar activación" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "El enlace requiere MFA Si este enlace es para acceso de plataforma, seleccioná “Configurar MFA”.",
    );
    await waitFor(() => {
      expect(screen.getByTestId("activation-location")).toHaveTextContent(/^$/);
    });
  });

  it("usa un error seguro cuando falla el enrollment MFA", async () => {
    activateIdentity.mockRejectedValue(new Error("detalle interno"));
    renderActivation();
    fireEvent.change(screen.getByLabelText("Secreto Base32"), { target: { value: "ABCDEFGHIJKLMNOPQRSTUVWX234567" } });
    fireEvent.change(screen.getByLabelText("Código TOTP"), { target: { value: "123456" } });
    fireEvent.click(screen.getByRole("button", { name: "Completar activación" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "No se pudo completar la activación. El enlace puede haber vencido o ya fue usado.",
    );
    expect(screen.queryByText("detalle interno")).not.toBeInTheDocument();
  });
});
