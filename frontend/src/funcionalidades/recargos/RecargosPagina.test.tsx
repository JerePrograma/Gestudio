import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../../config/permissions";

const listar = vi.hoisted(() => vi.fn());
const navigate = vi.hoisted(() => vi.fn());
const hasPermission = vi.hoisted(() => vi.fn(() => true));
const toastError = vi.hoisted(() => vi.fn());

vi.mock("../../api/recargosApi", () => ({
  default: { listarRecargos: listar },
}));
vi.mock("../../hooks/context/useAuth", () => ({
  useAuth: () => ({ hasPermission }),
}));
vi.mock("react-toastify", () => ({ toast: { error: toastError } }));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import RecargosPagina from "./RecargosPagina";

describe("RecargosPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    hasPermission.mockReturnValue(true);
    listar.mockResolvedValue([recargo(1)]);
  });

  it("muestra la carga y luego los datos obtenidos", async () => {
    let resolveList!: (items: ReturnType<typeof recargo>[]) => void;
    listar.mockReturnValueOnce(new Promise((resolve) => { resolveList = resolve; }));
    renderPage();

    expect(screen.getByText("Cargando...")).toBeVisible();
    resolveList([recargo(1)]);
    expect((await screen.findAllByText("Recargo 1")).length).toBeGreaterThan(0);
  });

  it("navega al alta y edición sólo con permiso de configuración", async () => {
    const rendered = renderPage();

    fireEvent.click(await screen.findByRole("button", { name: "Nuevo Recargo" }));
    expect(navigate).toHaveBeenCalledWith("/recargos/formulario");
    fireEvent.click(screen.getAllByRole("button", { name: "Editar" })[0]);
    expect(navigate).toHaveBeenCalledWith("/recargos/formulario?id=1");
    expect(screen.getAllByRole("button", { name: "Eliminar" })[0]).toBeEnabled();

    rendered.unmount();
    hasPermission.mockReturnValue(false);
    listar.mockResolvedValueOnce([recargo(1)]);
    renderPage();
    await screen.findAllByText("Recargo 1");
    expect(screen.queryByRole("button", { name: "Nuevo Recargo" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Editar" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Eliminar" })).not.toBeInTheDocument();
    expect(hasPermission).toHaveBeenCalledWith(PERMISSIONS.APP_ACCESS);
  });

  it("informa el fallo de carga y representa una lista vacía", async () => {
    listar.mockRejectedValueOnce(new Error("offline"));
    renderPage();

    expect(await screen.findByText("No hay datos disponibles")).toBeVisible();
    expect(toastError).toHaveBeenCalledWith("Error al cargar los recargos:");
  });
});

function renderPage() {
  return render(<MemoryRouter><RecargosPagina /></MemoryRouter>);
}

function recargo(id: number) {
  return {
    id,
    descripcion: `Recargo ${id}`,
    porcentaje: "5.00",
    valorFijo: "1000.00",
    diaDelMesAplicacion: 15,
  };
}
