import { AxiosError, type InternalAxiosRequestConfig } from "axios";
import { describe, expect, it } from "vitest";
import {
  errorCategory,
  getApiError,
  getApiErrorMessage,
  getFieldErrors,
  type ApiErrorPayload,
} from "./apiError";

const failure = (status: number, code: string) => {
  const data: ApiErrorPayload = {
    timestamp: "2026-07-01T00:00:00Z",
    status,
    code,
    message: "error",
    fieldErrors: [],
  };
  return new AxiosError(
    "request failed",
    undefined,
    {} as InternalAxiosRequestConfig,
    undefined,
    { status, statusText: "error", headers: {}, config: {} as InternalAxiosRequestConfig, data },
  );
};

describe("apiError", () => {
  it("preserva código y distingue las categorías HTTP del contrato", () => {
    expect(getApiError(failure(409, "IDEMPOTENCY_CONFLICT"))?.code).toBe("IDEMPOTENCY_CONFLICT");
    expect([400, 409, 401, 403, 404, 500].map((status) => errorCategory(failure(status, "X"))))
      .toEqual(["validation", "conflict", "unauthorized", "forbidden", "not-found", "internal"]);
    expect(errorCategory(new Error("offline"))).toBe("unknown");
  });

  it("expone mensajes y errores de campo sin asumir una respuesta válida", () => {
    const error = failure(400, "VALIDATION_ERROR");
    error.response!.data.fieldErrors = [
      { field: "monto", message: "Importe inválido" },
      { field: "alumnoId", message: "Alumno requerido" },
    ];

    expect(getFieldErrors(error)).toEqual({
      monto: "Importe inválido",
      alumnoId: "Alumno requerido",
    });
    expect(getApiErrorMessage(error, "fallback")).toBe("error");
    expect(getApiErrorMessage(new Error("offline"), "fallback")).toBe("fallback");
    expect(getApiError(new AxiosError("bad shape", undefined, undefined, undefined, {
      status: 500,
      statusText: "error",
      headers: {},
      config: {} as InternalAxiosRequestConfig,
      data: { status: 500, code: "X" },
    }))).toBeNull();
  });
});
