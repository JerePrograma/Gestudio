import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../../config/permissions";

const api = vi.hoisted(() => ({ listar: vi.fn(), eliminar: vi.fn() }));
const navigate = vi.hoisted(() => vi.fn());
const hasPermission = vi.hoisted(() => vi.fn(() => true));
const toastSuccess = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());

vi.mock("../../api/subConceptosApi", () => ({
  default: { listarSubConceptos: api.listar, eliminarSubConcepto: api.eliminar },
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

import SubConceptosPagina from "./SubConceptosPagina";

describe("SubConceptosPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    hasPermission.mockReturnValue(true);
    api.listar.mockResolvedValue(Array.from({ length: 6 }, (_, index) => subConcepto(index + 1)));
    api.eliminar.mockResolvedValue(undefined);
  });

  it("muestra carga y amplía la lista en bloques sin superar el total", async () => {
    let resolveList!: (items: ReturnType<typeof subConcepto>[]) => void;
    api.listar.mockReturnValueOnce(new Promise((resolve) => { resolveList = resolve; }));
    renderPage();

    expect(screen.getByText("Cargando...")).toBeVisible();
    resolveList(Array.from({ length: 6 }, (_, index) => subConcepto(index + 1)));

    expect(await screen.findAllByText("Subconcepto 1")).not.toHaveLength(0);
    expect(screen.queryByText("Subconcepto 6")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Mostrar más" }));
    expect(await screen.findAllByText("Subconcepto 6")).not.toHaveLength(0);
    expect(screen.queryByRole("button", { name: "Mostrar más" })).not.toBeInTheDocument();
  });

  it("navega al alta y edición sólo con permiso de configuración", async () => {
    api.listar.mockResolvedValueOnce([subConcepto(4)]);
    const rendered = renderPage();

    fireEvent.click(await screen.findByRole("button", { name: "Registrar nuevo subconcepto" }));
    expect(navigate).toHaveBeenCalledWith("/subconceptos/formulario");
    fireEvent.click(screen.getAllByRole("button", { name: "Editar subconcepto Subconcepto 4" })[0]);
    expect(navigate).toHaveBeenCalledWith("/subconceptos/formulario?id=4");

    rendered.unmount();
    hasPermission.mockReturnValue(false);
    api.listar.mockResolvedValueOnce([subConcepto(4)]);
    renderPage();
    await screen.findAllByText("Subconcepto 4");
    expect(screen.queryByRole("button", { name: "Registrar nuevo subconcepto" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Editar subconcepto/ })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Eliminar subconcepto/ })).not.toBeInTheDocument();
    expect(hasPermission).toHaveBeenCalledWith(PERMISSIONS.APP_ACCESS);
  });

  it("elimina y recarga, o conserva la fila cuando el backend rechaza", async () => {
    api.listar.mockResolvedValueOnce([subConcepto(2)]).mockResolvedValueOnce([]);
    renderPage();

    fireEvent.click((await screen.findAllByRole("button", { name: "Eliminar subconcepto Subconcepto 2" }))[0]);
    await waitFor(() => expect(api.eliminar).toHaveBeenCalledWith(2));
    expect(toastSuccess).toHaveBeenCalledWith("Subconcepto eliminado correctamente.");
    await waitFor(() => expect(api.listar).toHaveBeenCalledTimes(2));
    expect(await screen.findByText("No hay datos disponibles")).toBeVisible();

    api.listar.mockResolvedValueOnce([subConcepto(3)]);
    api.eliminar.mockRejectedValueOnce(new Error("in use"));
    renderPage();
    fireEvent.click((await screen.findAllByRole("button", { name: "Eliminar subconcepto Subconcepto 3" }))[0]);
    await waitFor(() => expect(toastError).toHaveBeenCalledWith("Error al eliminar el subconcepto."));
    expect(screen.getAllByText("Subconcepto 3")).not.toHaveLength(0);
  });

  it("presenta el error de carga y el estado vacío de forma diferenciada", async () => {
    api.listar.mockRejectedValueOnce(new Error("offline"));
    renderPage();
    expect(await screen.findByText("Error al cargar subconceptos.")).toBeVisible();
    expect(toastError).toHaveBeenCalledWith("Error al cargar subconceptos:");

    api.listar.mockResolvedValueOnce([]);
    renderPage();
    expect(await screen.findByText("No hay datos disponibles")).toBeVisible();
  });
});

function renderPage() {
  return render(<MemoryRouter><SubConceptosPagina /></MemoryRouter>);
}

function subConcepto(id: number) {
  return { id, descripcion: `Subconcepto ${id}` };
}
