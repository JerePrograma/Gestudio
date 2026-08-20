import { fireEvent, screen, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { renderPlatformPage } from "../../test/renderPlatformPage";

const api = vi.hoisted(() => ({ listTenants: vi.fn() }));
vi.mock("../platformApi", () => ({ platformApi: api }));

import TenantsPage from "./TenantsPage";

const page = {
  content: [
    { id: "active", code: "activa", name: "Academia Activa", status: "ACTIVE", membershipCount: 3 },
    { id: "suspended", code: "suspendida", name: "Academia Suspendida", status: "SUSPENDED", membershipCount: 0 },
    { id: "archived", code: "archivada", name: "Academia Archivada", status: "ARCHIVED" },
  ],
  totalElements: 3,
  totalPages: 2,
  number: 0,
  size: 25,
};

describe("TenantsPage", () => {
  beforeEach(() => {
    api.listTenants.mockReset();
    api.listTenants.mockResolvedValue(page);
  });

  it("lista todos los estados y navega a alta y detalle", async () => {
    renderPlatformPage(<TenantsPage />, "/platform/tenants", "/platform/tenants");
    expect((await screen.findAllByText("Academia Activa"))[0]).toBeVisible();
    expect(screen.getAllByText("Suspendida").length).toBeGreaterThan(0);
    expect(screen.getAllByText("Archivada").length).toBeGreaterThan(0);
    expect(screen.getAllByText("—").length).toBeGreaterThan(0);

    fireEvent.click(screen.getByRole("button", { name: "Nueva organización" }));
    expect(await screen.findByText("Alta destino")).toBeVisible();
  });

  it("filtra, pagina y abre el tenant elegido", async () => {
    renderPlatformPage(<TenantsPage />, "/platform/tenants", "/platform/tenants");
    await screen.findAllByText("Academia Activa");
    fireEvent.click(screen.getByRole("button", { name: "Siguiente" }));
    await waitFor(() => expect(api.listTenants).toHaveBeenCalledWith(expect.objectContaining({ page: 1 })));
    await screen.findAllByText("Academia Activa");
    fireEvent.change(screen.getByLabelText("Buscar por nombre o código"), { target: { value: "centro" } });
    await screen.findAllByText("Academia Activa");
    fireEvent.change(screen.getByLabelText("Estado"), { target: { value: "SUSPENDED" } });
    await waitFor(() => expect(api.listTenants).toHaveBeenCalledWith(expect.objectContaining({ page: 0, status: "SUSPENDED" })));
    await screen.findAllByText("Academia Activa");

    fireEvent.click(screen.getAllByRole("button", { name: "Ver Academia Activa" })[0]);
    expect(await screen.findByText("Detalle destino")).toBeVisible();
  });

  it("expone carga, error seguro y reintento", async () => {
    let resolve!: (value: typeof page) => void;
    api.listTenants.mockReturnValueOnce(new Promise((done) => { resolve = done; }));
    const pending = renderPlatformPage(<TenantsPage />, "/platform/tenants", "/platform/tenants");
    expect(screen.getByText("Cargando organizaciones...")).toBeVisible();
    resolve(page);
    await screen.findAllByText("Academia Activa");
    pending.unmount();

    api.listTenants.mockRejectedValueOnce(new Error("sin red")).mockResolvedValueOnce(page);
    renderPlatformPage(<TenantsPage />, "/platform/tenants", "/platform/tenants");
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudieron cargar las organizaciones.");
    fireEvent.click(screen.getByRole("button", { name: "Reintentar" }));
    expect((await screen.findAllByText("Academia Activa"))[0]).toBeVisible();
  });
});
