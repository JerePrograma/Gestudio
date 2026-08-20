import { fireEvent, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { renderPlatformPage } from "../../test/renderPlatformPage";

const api = vi.hoisted(() => ({ listAudit: vi.fn() }));
vi.mock("../platformApi", () => ({ platformApi: api }));
vi.mock("../../hooks/useDebounce", () => ({
  default: (value: unknown) => value,
}));

import PlatformAuditPage from "./PlatformAuditPage";

const page = {
  content: [
    { id: "1", occurredAt: "2030-01-01T12:00:00Z", actorUsername: "global-admin", action: "TENANT_CREATE", result: "SUCCESS", targetType: "TENANT", targetId: "tenant-1", correlationId: "corr-1" },
    { id: "2", occurredAt: "2030-01-02T12:00:00Z", actorId: 7, action: "TENANT_STATUS", result: "DENIED", targetType: "TENANT", correlationId: "corr-2" },
    { id: "3", occurredAt: "2030-01-03T12:00:00Z", action: "LOGIN", result: "FAILED", correlationId: "corr-3" },
  ],
  totalElements: 3,
  totalPages: 2,
  number: 0,
  size: 25,
};

describe("PlatformAuditPage", () => {
  beforeEach(() => {
    api.listAudit.mockReset();
    api.listAudit.mockResolvedValue(page);
  });

  it("presenta actores, resultados y objetivos sin inventar datos", async () => {
    renderPlatformPage(<PlatformAuditPage />, "/platform/audit?tenantId=tenant-1", "/platform/audit");
    expect(await screen.findAllByText("global-admin")).not.toHaveLength(0);
    expect(screen.getAllByText("ID 7").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Sistema").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Exitoso").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Denegado").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Fallido").length).toBeGreaterThan(0);
    await waitFor(() => expect(api.listAudit).toHaveBeenCalledWith(expect.objectContaining({ tenantId: "tenant-1" })));
  });

  it("envía filtros normalizados y pagina", async () => {
    renderPlatformPage(<PlatformAuditPage />, "/platform/audit", "/platform/audit");
    await screen.findByText("Auditoría de plataforma");
    fireEvent.click(screen.getByRole("button", { name: "Siguiente" }));
    await waitFor(() => expect(api.listAudit).toHaveBeenCalledWith(expect.objectContaining({ page: 1 })));
    await screen.findByText("Auditoría de plataforma");

    const changeFilter = async (label: string, value: string) => {
      fireEvent.change(screen.getByLabelText(label), { target: { value } });
      await screen.findByText("Auditoría de plataforma");
    };
    await changeFilter("Actor", " admin ");
    await changeFilter("Acción", "TENANT_UPDATE");
    await changeFilter("Resultado", "DENIED");
    await changeFilter("Tenant ID", " tenant-x ");
    await changeFilter("Desde", "2030-01-01T09:00");
    await changeFilter("Hasta", "2030-01-02T10:00");
    await changeFilter("Correlation ID", " corr-x ");

    await waitFor(() => expect(api.listAudit).toHaveBeenLastCalledWith({
      page: 0,
      size: 25,
      actor: "admin",
      action: "TENANT_UPDATE",
      result: "DENIED",
      tenantId: "tenant-x",
      from: new Date("2030-01-01T09:00").toISOString(),
      to: new Date("2030-01-02T10:00").toISOString(),
      correlationId: "corr-x",
    }));
  });

  it("permite reintentar una consulta fallida", async () => {
    api.listAudit.mockRejectedValueOnce(new Error("sin red")).mockResolvedValueOnce(page);
    renderPlatformPage(<PlatformAuditPage />, "/platform/audit", "/platform/audit");
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudo consultar la auditoría.");
    fireEvent.click(screen.getByRole("button", { name: "Reintentar" }));
    expect(await screen.findByText("Auditoría de plataforma")).toBeVisible();
  });
});
