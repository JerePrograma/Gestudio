import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../../config/permissions";
import type { Page, SalonResponse } from "../../types/types";

const listar = vi.hoisted(() => vi.fn());
const navigate = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());
const hasPermission = vi.hoisted(() => vi.fn(() => true));

vi.mock("../../api/salonesApi", () => ({ default: { listarSalones: listar } }));
vi.mock("../../hooks/context/useAuth", () => ({ useAuth: () => ({ hasPermission }) }));
vi.mock("react-toastify", () => ({ toast: { error: toastError } }));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import SalonesPagina from "./SalonesPagina";

describe("SalonesPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    hasPermission.mockReturnValue(true);
    listar.mockImplementation((page: number) => Promise.resolve(pagina(
      page === 0 ? [{ id: 1, nombre: "Sala Norte", descripcion: "Piso de madera" }] : [{ id: 2, nombre: "Sala Sur", descripcion: "" }],
      page,
    )));
  });

  it("muestra carga, datos y pagina hacia adelante y atrás con límites", async () => {
    let resolve!: (value: Page<SalonResponse>) => void;
    listar.mockReturnValueOnce(new Promise((done) => { resolve = done; }));
    renderPage();
    expect(screen.getByText("Cargando...")).toBeVisible();
    resolve(pagina([{ id: 1, nombre: "Sala Norte", descripcion: "Piso de madera" }], 0));

    expect(await screen.findAllByText("Sala Norte")).not.toHaveLength(0);
    expect(screen.getByRole("button", { name: "Anterior" })).toBeDisabled();
    fireEvent.click(screen.getByRole("button", { name: "Siguiente" }));
    await waitFor(() => expect(listar).toHaveBeenCalledWith(1));
    expect(await screen.findAllByText("Sala Sur")).not.toHaveLength(0);
    expect(screen.getByText(/Página 2 de 2/)).toBeVisible();

    fireEvent.click(screen.getByRole("button", { name: "Anterior" }));
    await waitFor(() => expect(listar).toHaveBeenLastCalledWith(0));
  });

  it("navega a alta y edición con el permiso real", async () => {
    renderPage();
    fireEvent.click(await screen.findByRole("button", { name: "Ficha de Salones" }));
    expect(navigate).toHaveBeenCalledWith("/salones/formulario");
    fireEvent.click((await screen.findAllByRole("button", { name: "Editar salón Sala Norte" }))[0]);
    expect(navigate).toHaveBeenCalledWith("/salones/formulario?id=1");
    expect(hasPermission).toHaveBeenCalledWith(PERMISSIONS.APP_ACCESS);
    expect(hasPermission).toHaveBeenCalledWith(PERMISSIONS.CONFIG_ADMIN);
  });

  it("oculta mutaciones sin permiso", async () => {
    hasPermission.mockReturnValue(false);
    renderPage();
    await screen.findAllByText("Sala Norte");
    expect(screen.queryByRole("button", { name: "Ficha de Salones" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Editar salón/ })).not.toBeInTheDocument();
  });

  it("presenta un error seguro al fallar la consulta", async () => {
    listar.mockRejectedValueOnce(new Error("network"));
    renderPage();
    expect(await screen.findByText("Error al cargar salones.")).toBeVisible();
    expect(toastError).toHaveBeenCalledWith("Error al cargar salones:");
  });
});

function renderPage() {
  return render(<MemoryRouter><SalonesPagina /></MemoryRouter>);
}

function pagina(content: SalonResponse[], number: number): Page<SalonResponse> {
  return {
    content,
    totalPages: 2,
    totalElements: 2,
    size: 10,
    number,
    first: number === 0,
    last: number === 1,
  };
}
