import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../../config/permissions";

const mocks = vi.hoisted(() => ({
  eliminar: vi.fn(),
  hasPermission: vi.fn(),
  listar: vi.fn(),
  navigate: vi.fn(),
  toastError: vi.fn(),
  toastSuccess: vi.fn(),
}));

vi.mock("../../api/stocksApi", () => ({
  default: { eliminarStock: mocks.eliminar, listarStocks: mocks.listar },
}));
vi.mock("../../hooks/context/useAuth", () => ({
  useAuth: () => ({ hasPermission: mocks.hasPermission }),
}));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => mocks.navigate,
}));
vi.mock("react-toastify", () => ({
  toast: { error: mocks.toastError, success: mocks.toastSuccess },
}));

import StocksPagina from "./StocksPagina";

describe("StocksPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.eliminar.mockResolvedValue(undefined);
    mocks.hasPermission.mockReturnValue(true);
    mocks.listar.mockImplementation((page: number) => Promise.resolve(pagina(page)));
    vi.spyOn(window, "confirm").mockReturnValue(true);
  });

  it("presenta datos, estado, navegación y paginación del backend", async () => {
    renderPage();

    expect((await screen.findAllByText("Botella"))[0]).toBeVisible();
    expect(screen.getAllByText("$ 1.500,00")[0]).toBeVisible();
    expect(screen.getAllByText("Activo")[0]).toBeVisible();
    expect(screen.getAllByText("Baja")[0]).toBeVisible();
    expect(mocks.listar).toHaveBeenCalledWith(0, 50);

    fireEvent.click(screen.getByRole("button", { name: "Nuevo producto" }));
    expect(mocks.navigate).toHaveBeenCalledWith("/stocks/formulario");

    fireEvent.click(screen.getByRole("button", { name: "Siguiente" }));
    await waitFor(() => expect(mocks.listar).toHaveBeenCalledWith(1, 50));
  });

  it("edita y da de baja sólo después de confirmación", async () => {
    const queryClient = renderPage();
    const invalidate = vi.spyOn(queryClient, "invalidateQueries");

    await openActions("Botella");
    fireEvent.click(screen.getByRole("menuitem", { name: "Editar" }));
    expect(mocks.navigate).toHaveBeenCalledWith("/stocks/formulario?id=1");

    vi.mocked(window.confirm).mockReturnValueOnce(false);
    await openActions("Botella");
    fireEvent.click(screen.getByRole("menuitem", { name: "Dar de baja" }));
    expect(mocks.eliminar).not.toHaveBeenCalled();

    await openActions("Botella");
    fireEvent.click(screen.getByRole("menuitem", { name: "Dar de baja" }));
    await waitFor(() => expect(mocks.eliminar).toHaveBeenCalledWith(1));
    expect(invalidate).toHaveBeenCalledWith({ queryKey: ["stocks"] });
    expect(mocks.toastSuccess).toHaveBeenCalledWith("Producto dado de baja.");

    await openActions("Producto inactivo");
    expect(screen.getByRole("menuitem", { name: "Editar" })).toBeVisible();
    expect(screen.queryByRole("menuitem", { name: "Dar de baja" })).not.toBeInTheDocument();
  });

  it("no ofrece mutaciones sin permiso y no permite dar de baja un registro inactivo", async () => {
    mocks.hasPermission.mockImplementation((permission) => permission === PERMISSIONS.APP_ACCESS);
    renderPage();

    expect((await screen.findAllByText("Botella"))[0]).toBeVisible();
    expect(screen.queryByRole("button", { name: "Nuevo producto" })).not.toBeInTheDocument();
    expect(mocks.hasPermission).toHaveBeenCalledWith(PERMISSIONS.STOCK_ADMIN);

    expect(screen.queryByRole("button", { name: "Acciones de Botella" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Acciones de Producto inactivo" })).not.toBeInTheDocument();
  });

  it("muestra el error de listado, permite reintentar e informa errores de baja", async () => {
    mocks.listar.mockRejectedValueOnce(new Error("load")).mockResolvedValueOnce(pagina(0));
    mocks.eliminar.mockRejectedValueOnce(new Error("delete"));
    renderPage();

    fireEvent.click(await screen.findByRole("button", { name: "Reintentar" }));
    expect((await screen.findAllByText("Botella"))[0]).toBeVisible();

    await openActions("Botella");
    fireEvent.click(screen.getByRole("menuitem", { name: "Dar de baja" }));
    await waitFor(() => expect(mocks.toastError).toHaveBeenCalledWith("No se pudo dar de baja el producto."));
  });
});

async function openActions(name: string) {
  fireEvent.pointerDown((await screen.findAllByRole("button", { name: `Acciones de ${name}` }))[0]);
}

function renderPage() {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>
        <StocksPagina />
      </MemoryRouter>
    </QueryClientProvider>,
  );
  return queryClient;
}

function pagina(number: number) {
  return {
    content: number === 0 ? [
      { id: 1, nombre: "Botella", precio: "1500.00", stock: 4, requiereControlDeStock: true, codigoBarras: "7799999", activo: true },
      { id: 2, nombre: "Producto inactivo", precio: "500.00", stock: 0, requiereControlDeStock: false, codigoBarras: "", activo: false },
    ] : [],
    totalElements: 52,
    totalPages: 2,
    number,
    size: 50,
    first: number === 0,
    last: number === 1,
  };
}
