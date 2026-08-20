import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../../config/permissions";

const api = vi.hoisted(() => ({ listar: vi.fn(), eliminar: vi.fn() }));
const navigate = vi.hoisted(() => vi.fn());
const hasPermission = vi.hoisted(() => vi.fn(() => true));
const toastSuccess = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());

vi.mock("../../api/conceptosApi", () => ({
  default: { listarConceptos: api.listar, eliminarConcepto: api.eliminar },
}));
vi.mock("../../hooks/context/useAuth", () => ({
  useAuth: () => ({ hasPermission }),
}));
vi.mock("react-toastify", () => ({
  toast: { success: toastSuccess, error: toastError },
}));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import ConceptosPagina from "./ConceptosPagina";

describe("ConceptosPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    hasPermission.mockReturnValue(true);
    api.listar.mockResolvedValue(Array.from({ length: 26 }, (_, index) => concepto(index + 1)));
    api.eliminar.mockResolvedValue(undefined);
  });

  it("muestra carga, datos monetarios y la carga incremental completa", async () => {
    let resolveList!: (items: ReturnType<typeof concepto>[]) => void;
    api.listar.mockReturnValueOnce(new Promise((resolve) => { resolveList = resolve; }));
    renderPage();

    expect(screen.getByRole("status")).toHaveTextContent("Cargando conceptos...");
    resolveList(Array.from({ length: 26 }, (_, index) => concepto(index + 1)));

    expect(await screen.findByText("26 registros")).toBeVisible();
    expect(screen.getAllByText("$ 1.234,50")).not.toHaveLength(0);
    expect(screen.queryByText("Concepto 26")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Mostrar más" }));
    expect(await screen.findAllByText("Concepto 26")).not.toHaveLength(0);
    expect(screen.queryByRole("button", { name: "Mostrar más" })).not.toBeInTheDocument();
  });

  it("navega al alta y la edición sólo con permiso de configuración", async () => {
    api.listar.mockResolvedValueOnce([concepto(7)]);
    const rendered = renderPage();

    fireEvent.click(await screen.findByRole("button", { name: "Registrar nuevo concepto" }));
    expect(navigate).toHaveBeenCalledWith("/conceptos/formulario-concepto");
    fireEvent.pointerDown(screen.getAllByRole("button", { name: "Acciones de Concepto 7" })[0]);
    fireEvent.click(await screen.findByRole("menuitem", { name: "Editar" }));
    expect(navigate).toHaveBeenCalledWith("/conceptos/formulario-concepto?id=7");

    rendered.unmount();
    hasPermission.mockReturnValue(false);
    api.listar.mockResolvedValueOnce([concepto(7)]);
    renderPage();
    await screen.findAllByText("Concepto 7");
    expect(screen.queryByRole("button", { name: "Registrar nuevo concepto" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Acciones de Concepto 7" })).not.toBeInTheDocument();
    expect(hasPermission).toHaveBeenCalledWith(PERMISSIONS.APP_ACCESS);
  });

  it("elimina, informa éxito y vuelve a cargar la lista", async () => {
    api.listar.mockResolvedValueOnce([concepto(2)]).mockResolvedValueOnce([]);
    renderPage();

    fireEvent.pointerDown((await screen.findAllByRole("button", { name: "Acciones de Concepto 2" }))[0]);
    fireEvent.click(await screen.findByRole("menuitem", { name: "Eliminar" }));

    await waitFor(() => expect(api.eliminar).toHaveBeenCalledWith(2));
    expect(toastSuccess).toHaveBeenCalledWith("Concepto eliminado correctamente.");
    await waitFor(() => expect(api.listar).toHaveBeenCalledTimes(2));
    expect(await screen.findByText("No hay datos disponibles")).toBeVisible();
  });

  it("mantiene la lista si la eliminación es rechazada", async () => {
    api.listar.mockResolvedValueOnce([concepto(3)]);
    api.eliminar.mockRejectedValueOnce(new Error("in use"));
    renderPage();

    fireEvent.pointerDown((await screen.findAllByRole("button", { name: "Acciones de Concepto 3" }))[0]);
    fireEvent.click(await screen.findByRole("menuitem", { name: "Eliminar" }));

    await waitFor(() => expect(toastError).toHaveBeenCalledWith("Error al eliminar el concepto."));
    expect(api.listar).toHaveBeenCalledTimes(1);
    expect(screen.getAllByText("Concepto 3")).not.toHaveLength(0);
  });

  it("reintenta una carga fallida y representa la respuesta vacía", async () => {
    api.listar.mockRejectedValueOnce(new Error("offline")).mockResolvedValueOnce([]);
    renderPage();

    expect(await screen.findByRole("alert")).toHaveTextContent("Error al cargar conceptos.");
    expect(toastError).toHaveBeenCalledWith("Error al cargar conceptos:");
    fireEvent.click(screen.getByRole("button", { name: "Reintentar" }));

    expect(await screen.findByText("No hay datos disponibles")).toBeVisible();
    expect(api.listar).toHaveBeenCalledTimes(2);
  });
});

function renderPage() {
  return render(<MemoryRouter><ConceptosPagina /></MemoryRouter>);
}

function concepto(id: number) {
  return {
    version: 1,
    id,
    descripcion: `Concepto ${id}`,
    precio: "1234.50",
    subConcepto: { id: 4, descripcion: "Cuotas" },
    activo: true,
  };
}
