import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../../config/permissions";

const api = vi.hoisted(() => ({ listar: vi.fn(), eliminar: vi.fn() }));
const navigate = vi.hoisted(() => vi.fn());
const hasPermission = vi.hoisted(() => vi.fn(() => true));
const toastSuccess = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());

vi.mock("../../api/metodosPagoApi", () => ({
  default: { listarMetodosPago: api.listar, eliminarMetodoPago: api.eliminar },
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

import MetodosPagoPagina from "./MetodosPagoPagina";

describe("MetodosPagoPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    hasPermission.mockReturnValue(true);
    api.listar.mockResolvedValue(Array.from({ length: 26 }, (_, index) => metodo(index + 1)));
    api.eliminar.mockResolvedValue(undefined);
  });

  it("muestra carga, datos y carga incremental", async () => {
    let resolveList!: (items: ReturnType<typeof metodo>[]) => void;
    api.listar.mockReturnValueOnce(new Promise((resolve) => { resolveList = resolve; }));
    renderPage();

    expect(screen.getByRole("status")).toHaveTextContent("Cargando métodos de pago...");
    resolveList(Array.from({ length: 26 }, (_, index) => metodo(index + 1)));

    expect(await screen.findByText("26 registros")).toBeVisible();
    expect(screen.queryByText("Método 26")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Mostrar más" }));
    expect(await screen.findAllByText("Método 26")).not.toHaveLength(0);
    expect(screen.queryByRole("button", { name: "Mostrar más" })).not.toBeInTheDocument();
  });

  it("navega al alta y la edición sólo con permiso de configuración", async () => {
    api.listar.mockResolvedValueOnce([metodo(4)]);
    const rendered = renderPage();

    fireEvent.click(await screen.findByRole("button", { name: "Registrar nuevo método de pago" }));
    expect(navigate).toHaveBeenCalledWith("/metodos-pago/formulario");
    fireEvent.pointerDown(screen.getAllByRole("button", { name: "Acciones de Método 4" })[0]);
    fireEvent.click(await screen.findByRole("menuitem", { name: "Editar" }));
    expect(navigate).toHaveBeenCalledWith("/metodos-pago/formulario?id=4");

    rendered.unmount();
    hasPermission.mockReturnValue(false);
    api.listar.mockResolvedValueOnce([metodo(4)]);
    renderPage();
    await screen.findAllByText("Método 4");
    expect(screen.queryByRole("button", { name: "Registrar nuevo método de pago" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Acciones de Método 4" })).not.toBeInTheDocument();
    expect(hasPermission).toHaveBeenCalledWith(PERMISSIONS.APP_ACCESS);
  });

  it("elimina, informa éxito y vuelve a cargar", async () => {
    api.listar.mockResolvedValueOnce([metodo(2)]).mockResolvedValueOnce([]);
    renderPage();

    fireEvent.pointerDown((await screen.findAllByRole("button", { name: "Acciones de Método 2" }))[0]);
    fireEvent.click(await screen.findByRole("menuitem", { name: "Eliminar" }));

    await waitFor(() => expect(api.eliminar).toHaveBeenCalledWith(2));
    expect(toastSuccess).toHaveBeenCalledWith("Método de pago eliminado correctamente.");
    await waitFor(() => expect(api.listar).toHaveBeenCalledTimes(2));
    expect(await screen.findByText("No hay datos disponibles")).toBeVisible();
  });

  it("conserva la fila cuando la eliminación falla", async () => {
    api.listar.mockResolvedValueOnce([metodo(3)]);
    api.eliminar.mockRejectedValueOnce(new Error("in use"));
    renderPage();

    fireEvent.pointerDown((await screen.findAllByRole("button", { name: "Acciones de Método 3" }))[0]);
    fireEvent.click(await screen.findByRole("menuitem", { name: "Eliminar" }));

    await waitFor(() => expect(toastError).toHaveBeenCalledWith("Error al eliminar el método de pago."));
    expect(api.listar).toHaveBeenCalledTimes(1);
    expect(screen.getAllByText("Método 3")).not.toHaveLength(0);
  });

  it("reintenta una carga fallida y presenta el estado vacío", async () => {
    api.listar.mockRejectedValueOnce(new Error("offline")).mockResolvedValueOnce([]);
    renderPage();

    expect(await screen.findByRole("alert")).toHaveTextContent("Error al cargar métodos de pago.");
    expect(toastError).toHaveBeenCalledWith("Error al cargar métodos de pago:");
    fireEvent.click(screen.getByRole("button", { name: "Reintentar" }));

    expect(await screen.findByText("No hay datos disponibles")).toBeVisible();
    expect(api.listar).toHaveBeenCalledTimes(2);
  });
});

function renderPage() {
  return render(<MemoryRouter><MetodosPagoPagina /></MemoryRouter>);
}

function metodo(id: number) {
  return { id, descripcion: `Método ${id}`, activo: true, recargo: "3.00" };
}
