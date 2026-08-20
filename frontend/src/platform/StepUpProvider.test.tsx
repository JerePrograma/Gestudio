import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { useState } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { StepUpHeaders } from "./platformTypes";

const api = vi.hoisted(() => ({
  createStepUpChallenge: vi.fn(),
  verifyStepUpChallenge: vi.fn(),
}));

vi.mock("./platformApi", () => ({ platformApi: api }));

import { StepUpProvider } from "./StepUpProvider";
import { useStepUp } from "./stepUpContext";

const descriptor = {
  action: "TENANT_STATUS",
  targetType: "TENANT",
  targetId: "00000000-0000-0000-0000-0000000000a1",
  idempotencyKey: "00000000-0000-4000-8000-000000000001",
};

const Probe = ({ operation }: { operation: (headers: StepUpHeaders) => Promise<void> }) => {
  const { executeWithStepUp } = useStepUp();
  return (
    <button type="button" onClick={() => void executeWithStepUp(descriptor, operation).catch(() => undefined)}>
      Ejecutar
    </button>
  );
};

const ResultProbe = ({ operation }: {
  operation: (headers: StepUpHeaders) => Promise<{ activation: { token: string } }>;
}) => {
  const { executeWithStepUp } = useStepUp();
  const [token, setToken] = useState("");
  return (
    <>
      <button
        type="button"
        onClick={() => void executeWithStepUp(descriptor, operation)
          .then((result) => setToken(result.activation.token))}
      >
        Ejecutar con resultado
      </button>
      {token && <output>{token}</output>}
    </>
  );
};

const OutcomeProbe = ({ operation }: { operation: (headers: StepUpHeaders) => Promise<string> }) => {
  const { executeWithStepUp } = useStepUp();
  const [outcome, setOutcome] = useState("Sin resultado");
  const execute = () => {
    void executeWithStepUp(descriptor, operation)
      .then((result) => setOutcome(result))
      .catch((error: unknown) => setOutcome(error instanceof Error ? error.message : "Error desconocido"));
  };

  return (
    <>
      <button type="button" onClick={execute}>Ejecutar operación</button>
      <output>{outcome}</output>
    </>
  );
};

describe("StepUpProvider", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.createStepUpChallenge.mockResolvedValue({ challengeId: "challenge-1", expiresAt: "2030-01-01T00:05:00Z" });
    api.verifyStepUpChallenge.mockResolvedValue({ stepUpToken: "proof-1", expiresAt: "2030-01-01T00:02:00Z" });
  });

  it("reutiliza la misma idempotency key y repite la mutación exactamente una vez", async () => {
    const operation = vi.fn()
      .mockRejectedValueOnce({ isAxiosError: true, response: { status: 428 } })
      .mockResolvedValueOnce(undefined);

    render(<StepUpProvider><Probe operation={operation} /></StepUpProvider>);
    fireEvent.click(screen.getByRole("button", { name: "Ejecutar" }));

    expect(await screen.findByRole("dialog", { name: "Confirmá esta acción sensible" })).toBeVisible();
    expect(api.createStepUpChallenge).toHaveBeenCalledWith(descriptor);
    expect(operation).toHaveBeenNthCalledWith(1, { "Idempotency-Key": descriptor.idempotencyKey });

    fireEvent.change(screen.getByLabelText("Código TOTP"), { target: { value: "123456" } });
    fireEvent.click(screen.getByRole("button", { name: "Verificar y continuar" }));

    await waitFor(() => expect(operation).toHaveBeenCalledTimes(2));
    expect(api.verifyStepUpChallenge).toHaveBeenCalledWith("challenge-1", "123456");
    expect(operation).toHaveBeenNthCalledWith(2, {
      "Idempotency-Key": descriptor.idempotencyKey,
      "X-Step-Up-Token": "proof-1",
    });
    await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());
  }, 15_000);

  it("devuelve al llamador el resultado sensible de la mutación reintentada", async () => {
    const operation = vi.fn()
      .mockRejectedValueOnce({ isAxiosError: true, response: { status: 428 } })
      .mockResolvedValueOnce({ activation: { token: "one-time-membership-token" } });

    render(<StepUpProvider><ResultProbe operation={operation} /></StepUpProvider>);
    fireEvent.click(screen.getByRole("button", { name: "Ejecutar con resultado" }));
    await screen.findByRole("dialog", { name: "Confirmá esta acción sensible" });

    fireEvent.change(screen.getByLabelText("Código TOTP"), { target: { value: "123456" } });
    fireEvent.click(screen.getByRole("button", { name: "Verificar y continuar" }));

    expect(await screen.findByText("one-time-membership-token")).toBeVisible();
    expect(operation).toHaveBeenCalledTimes(2);
  }, 15_000);

  it("devuelve directamente el resultado cuando la operación no requiere step-up", async () => {
    const operation = vi.fn().mockResolvedValue("Operación completa");

    render(<StepUpProvider><OutcomeProbe operation={operation} /></StepUpProvider>);
    fireEvent.click(screen.getByText("Ejecutar operación"));

    expect(await screen.findByText("Operación completa")).toBeVisible();
    expect(operation).toHaveBeenCalledWith({ "Idempotency-Key": descriptor.idempotencyKey });
    expect(api.createStepUpChallenge).not.toHaveBeenCalled();
  });

  it("propaga un fallo que no solicita step-up y no abre el diálogo", async () => {
    const operation = vi.fn().mockRejectedValue(new Error("Fallo de negocio"));

    render(<StepUpProvider><OutcomeProbe operation={operation} /></StepUpProvider>);
    fireEvent.click(screen.getByRole("button", { name: "Ejecutar operación" }));

    expect(await screen.findByText("Fallo de negocio")).toBeVisible();
    expect(screen.queryByRole("dialog")).not.toBeInTheDocument();
    expect(api.createStepUpChallenge).not.toHaveBeenCalled();
  });

  it("impide superponer dos verificaciones y permite cancelar la pendiente", async () => {
    const operation = vi.fn().mockRejectedValue({
      isAxiosError: true,
      response: { status: 428 },
    });

    render(<StepUpProvider><OutcomeProbe operation={operation} /></StepUpProvider>);
    fireEvent.click(screen.getByRole("button", { name: "Ejecutar operación" }));
    await screen.findByRole("dialog", { name: "Confirmá esta acción sensible" });

    fireEvent.click(screen.getByText("Ejecutar operación"));
    expect(await screen.findByText("Ya hay una verificación reforzada en curso")).toBeVisible();

    fireEvent.click(screen.getAllByRole("button", { name: "Cancelar" })[0]);
    await waitFor(() => expect(screen.queryByRole("dialog")).not.toBeInTheDocument());
    expect(operation).toHaveBeenCalledTimes(1);
  });

  it("valida el código aun ante un submit programático", async () => {
    const operation = vi.fn().mockRejectedValue({
      isAxiosError: true,
      response: { status: 428 },
    });

    render(<StepUpProvider><Probe operation={operation} /></StepUpProvider>);
    fireEvent.click(screen.getByRole("button", { name: "Ejecutar" }));
    await screen.findByRole("dialog", { name: "Confirmá esta acción sensible" });

    const submit = screen.getByRole("button", { name: "Verificar y continuar" });
    fireEvent.submit(submit.closest("form")!);

    const codeError = await screen.findByRole("alert");
    const codeInput = screen.getByLabelText("Código TOTP");
    expect(codeError).toHaveTextContent("Ingresá el código TOTP de 6 dígitos.");
    expect(codeInput).toHaveFocus();
    expect(codeInput).toHaveAttribute("aria-invalid", "true");
    expect(codeInput).toHaveAttribute("aria-describedby", codeError.id);
    expect(api.verifyStepUpChallenge).not.toHaveBeenCalled();
  });

  it("muestra el error seguro del servidor y limpia un proof rechazado", async () => {
    const operation = vi.fn().mockRejectedValueOnce({
      isAxiosError: true,
      response: { status: 428 },
    });
    api.verifyStepUpChallenge.mockRejectedValue({
      isAxiosError: true,
      response: {
        status: 403,
        data: {
          timestamp: "2030-01-01T00:00:00Z",
          status: 403,
          code: "STEP_UP_REJECTED",
          message: "El comprobante fue rechazado",
          fieldErrors: [],
        },
      },
    });

    render(<StepUpProvider><Probe operation={operation} /></StepUpProvider>);
    fireEvent.click(screen.getByRole("button", { name: "Ejecutar" }));
    await screen.findByRole("dialog", { name: "Confirmá esta acción sensible" });
    const input = screen.getByLabelText("Código TOTP");
    fireEvent.change(input, { target: { value: "12a34567" } });
    expect(input).toHaveValue("123456");
    fireEvent.click(screen.getByRole("button", { name: "Verificar y continuar" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("El comprobante fue rechazado");
    expect(input).toHaveValue("");
  });

  it("conserva el código ante un fallo transitorio para permitir reintento", async () => {
    const operation = vi.fn().mockRejectedValueOnce({
      isAxiosError: true,
      response: { status: 428 },
    });
    api.verifyStepUpChallenge.mockRejectedValue(new Error("red no disponible"));

    render(<StepUpProvider><Probe operation={operation} /></StepUpProvider>);
    fireEvent.click(screen.getByRole("button", { name: "Ejecutar" }));
    await screen.findByRole("dialog", { name: "Confirmá esta acción sensible" });
    const input = screen.getByLabelText("Código TOTP");
    fireEvent.change(input, { target: { value: "654321" } });
    fireEvent.click(screen.getByRole("button", { name: "Verificar y continuar" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "No se pudo verificar el código o completar la operación.",
    );
    expect(input).toHaveValue("654321");
  });

  it("limpia también el código cuando el servidor informa conflicto", async () => {
    const operation = vi.fn().mockRejectedValueOnce({
      isAxiosError: true,
      response: { status: 428 },
    });
    api.verifyStepUpChallenge.mockRejectedValue({
      isAxiosError: true,
      response: { status: 409 },
    });

    render(<StepUpProvider><Probe operation={operation} /></StepUpProvider>);
    fireEvent.click(screen.getByRole("button", { name: "Ejecutar" }));
    await screen.findByRole("dialog", { name: "Confirmá esta acción sensible" });
    const input = screen.getByLabelText("Código TOTP");
    fireEvent.change(input, { target: { value: "123456" } });
    fireEvent.click(screen.getByRole("button", { name: "Verificar y continuar" }));

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "No se pudo verificar el código o completar la operación.",
    );
    expect(input).toHaveValue("");
  });
});
