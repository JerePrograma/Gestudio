import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../../config/permissions";
import type { InscripcionResponse, Page } from "../../types/types";

const listar = vi.hoisted(() => vi.fn());
const navigate = vi.hoisted(() => vi.fn());
const hasPermission = vi.hoisted(() => vi.fn(() => true));

vi.mock("../../api/inscripcionesApi", () => ({ default: { listar } }));
vi.mock("../../hooks/context/useAuth", () => ({ useAuth: () => ({ hasPermission }) }));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import InscripcionesPagina from "./InscripcionesPagina";

describe("InscripcionesPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    hasPermission.mockReturnValue(true);
    listar.mockImplementation((page: number, _size: number, search: string) => Promise.resolve(
      pagina(search ? [] : [inscripcion(11), inscripcion(12, false)], page),
    ));
  });

  it("representa carga, datos económicos y estados sin recalcular importes", async () => {
    let resolve!: (value: Page<InscripcionResponse>) => void;
    listar.mockReturnValueOnce(new Promise((done) => { resolve = done; }));
    renderPage();
    expect(screen.getByText("Cargando inscripciones...")).toBeVisible();
    resolve(pagina([inscripcion(11), inscripcion(12, false)], 0));

    expect(await screen.findByText("2 registros")).toBeVisible();
    expect(screen.getAllByText("ACTIVA").length).toBeGreaterThan(0);
    expect(screen.getAllByText("BAJA").length).toBeGreaterThan(0);
    expect(screen.getAllByText("$ 1.234,50").length).toBeGreaterThan(0);
    expect(screen.getAllByText("—").length).toBeGreaterThan(0);
  });

  it("filtra reiniciando página y pagina con el contrato backend", async () => {
    renderPage();
    await screen.findByText("2 registros");

    fireEvent.click(screen.getByRole("button", { name: "Siguiente" }));
    await waitFor(() => expect(listar).toHaveBeenCalledWith(1, 50, ""));

    fireEvent.change(screen.getByLabelText("Buscar inscripción"), { target: { value: "  Ana  " } });
    await waitFor(() => expect(listar).toHaveBeenCalledWith(0, 50, "Ana"));
    expect(await screen.findByText("No hay datos disponibles")).toBeVisible();
  });

  it("navega a alta, condiciones y edición según permisos", async () => {
    renderPage();
    fireEvent.click(await screen.findByRole("button", { name: "Nueva inscripción" }));
    expect(navigate).toHaveBeenCalledWith("/inscripciones/formulario");

    await openActions("Acciones de inscripción de Ana Prueba");
    fireEvent.click(await screen.findByRole("menuitem", { name: "Condiciones" }));
    expect(navigate).toHaveBeenCalledWith("/inscripciones/11/condiciones-economicas");

    await openActions("Acciones de inscripción de Ana Prueba");
    fireEvent.click(await screen.findByRole("menuitem", { name: "Editar" }));
    expect(navigate).toHaveBeenCalledWith("/inscripciones/formulario?id=11");
    expect(hasPermission).toHaveBeenCalledWith(PERMISSIONS.CONDICIONES_ECONOMICAS_ADMIN);
    expect(hasPermission).toHaveBeenCalledWith(PERMISSIONS.INSCRIPCIONES_ADMIN);
  });

  it("oculta mutaciones sin permiso y permite reintentar un error", async () => {
    hasPermission.mockReturnValue(false);
    const denied = renderPage();
    await screen.findAllByText("Ana Prueba");
    expect(screen.queryByRole("button", { name: "Nueva inscripción" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Acciones de inscripción/ })).not.toBeInTheDocument();
    denied.unmount();

    hasPermission.mockReturnValue(true);
    listar.mockRejectedValueOnce(new Error("network"));
    renderPage();
    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudieron cargar las inscripciones.");
    fireEvent.click(screen.getByRole("button", { name: "Reintentar" }));
    expect(await screen.findByText("2 registros")).toBeVisible();
  });
});

async function openActions(label: string) {
  fireEvent.pointerDown((await screen.findAllByRole("button", { name: label }))[0]);
}

function renderPage() {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false, gcTime: 0 } } });
  return render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter><InscripcionesPagina /></MemoryRouter>
    </QueryClientProvider>,
  );
}

function pagina(content: InscripcionResponse[], number: number): Page<InscripcionResponse> {
  return { content, totalElements: content.length, totalPages: 2, size: 50, number, first: number === 0, last: number === 1 };
}

function inscripcion(id: number, activa = true): InscripcionResponse {
  return {
    id,
    alumnoId: 7,
    alumno: id === 11 ? "Ana Prueba" : "Bea Prueba",
    disciplinaId: 3,
    disciplina: "Danza",
    fechaInscripcion: "2026-08-01",
    estado: activa ? "ACTIVA" : "BAJA",
    costoParticular: activa ? "1234.50" : undefined,
  };
}
