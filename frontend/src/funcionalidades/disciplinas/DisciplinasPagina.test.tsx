import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../../config/permissions";
import { DiaSemana } from "../../types/types";

const api = vi.hoisted(() => ({ listar: vi.fn(), darBaja: vi.fn() }));
const navigate = vi.hoisted(() => vi.fn());
const hasPermission = vi.hoisted(() => vi.fn(() => true));
const toastSuccess = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());
const apiErrorMessage = vi.hoisted(() => vi.fn(() => "Detalle seguro"));

vi.mock("../../api/disciplinasApi", () => ({
  default: { listarDisciplinas: api.listar, darBajaDisciplina: api.darBaja },
}));
vi.mock("../../api/apiError", () => ({ getApiErrorMessage: apiErrorMessage }));
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

import DisciplinasPagina from "./DisciplinasPagina";

describe("DisciplinasPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    hasPermission.mockReturnValue(true);
    api.listar.mockResolvedValue(Array.from({ length: 27 }, (_, index) => disciplina(index + 1)));
    api.darBaja.mockResolvedValue(undefined);
    vi.spyOn(window, "confirm").mockReturnValue(true);
  });

  it("representa carga y pagina la lista obtenida", async () => {
    let resolveList!: (items: ReturnType<typeof disciplina>[]) => void;
    api.listar.mockReturnValueOnce(new Promise((resolve) => { resolveList = resolve; }));
    renderPage();

    expect(screen.getByRole("status")).toHaveTextContent("Cargando disciplinas...");
    resolveList(Array.from({ length: 27 }, (_, index) => disciplina(index + 1)));

    expect(await screen.findByText("27 registros")).toBeVisible();
    expect(screen.queryAllByText("Disciplina 9")).toHaveLength(0);
    fireEvent.click(screen.getByRole("button", { name: "Mostrar más" }));
    expect(screen.getAllByText("Disciplina 9")).not.toHaveLength(0);
    expect(screen.queryByRole("button", { name: "Mostrar más" })).not.toBeInTheDocument();
  });

  it("filtra y ordena la lista obtenida", async () => {
    renderPage();

    expect(await screen.findByText("27 registros")).toBeVisible();

    fireEvent.change(screen.getByLabelText("Buscar"), { target: { value: "Disciplina 2" } });
    expect(screen.getByText("9 registros")).toBeVisible();
    expect(screen.queryByText("Disciplina 1")).not.toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("Orden"), { target: { value: "desc" } });
    const rows = within(screen.getAllByRole("table")[0]).getAllByRole("row");
    expect(rows[1]).toHaveTextContent("Disciplina 27");
  });

  it("respeta permisos y navega a alta, edición y tarifas con los IDs correctos", async () => {
    api.listar.mockResolvedValueOnce([disciplina(7)]);
    const { unmount } = renderPage();

    fireEvent.click(await screen.findByRole("button", { name: "Nueva disciplina" }));
    expect(navigate).toHaveBeenCalledWith("/disciplinas/formulario");

    fireEvent.pointerDown(screen.getAllByRole("button", { name: "Acciones de Disciplina 7" })[0]);
    fireEvent.click(await screen.findByRole("menuitem", { name: "Tarifas" }));
    expect(navigate).toHaveBeenCalledWith("/disciplinas/7/tarifas");

    fireEvent.pointerDown(screen.getAllByRole("button", { name: "Acciones de Disciplina 7" })[0]);
    fireEvent.click(await screen.findByRole("menuitem", { name: "Editar" }));
    expect(navigate).toHaveBeenCalledWith("/disciplinas/formulario?id=7");

    unmount();
    hasPermission.mockReturnValue(false);
    api.listar.mockResolvedValueOnce([disciplina(7)]);
    renderPage();
    await screen.findAllByText("Disciplina 7");
    expect(screen.queryByRole("button", { name: "Nueva disciplina" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Acciones de Disciplina 7" })).not.toBeInTheDocument();
    expect(hasPermission).toHaveBeenCalledWith(PERMISSIONS.APP_ACCESS);
  });

  it("sólo da de baja tras confirmar e invalida la consulta de disciplinas", async () => {
    api.listar.mockResolvedValueOnce([disciplina(3)]);
    const { queryClient } = renderPage();
    const invalidate = vi.spyOn(queryClient, "invalidateQueries");
    vi.mocked(window.confirm).mockReturnValueOnce(false).mockReturnValueOnce(true);

    const openActions = async () => {
      fireEvent.pointerDown((await screen.findAllByRole("button", { name: "Acciones de Disciplina 3" }))[0]);
      return screen.findByRole("menuitem", { name: "Dar de baja" });
    };

    fireEvent.click(await openActions());
    expect(window.confirm).toHaveBeenCalledWith("¿Dar de baja Disciplina 3?");
    expect(api.darBaja).not.toHaveBeenCalled();

    fireEvent.click(await openActions());
    await waitFor(() => expect(api.darBaja).toHaveBeenCalledWith(3));
    expect(invalidate).toHaveBeenCalledWith({ queryKey: ["disciplinas"] });
    expect(toastSuccess).toHaveBeenCalledWith("Disciplina dada de baja.");
  });

  it("presenta el error de baja seguro y conserva la fila", async () => {
    api.listar.mockResolvedValueOnce([disciplina(4)]);
    api.darBaja.mockRejectedValueOnce(new Error("sensitive backend detail"));
    renderPage();

    fireEvent.pointerDown((await screen.findAllByRole("button", { name: "Acciones de Disciplina 4" }))[0]);
    fireEvent.click(await screen.findByRole("menuitem", { name: "Dar de baja" }));

    await waitFor(() => expect(toastError).toHaveBeenCalledWith("Detalle seguro"));
    expect(apiErrorMessage).toHaveBeenCalledWith(
      expect.any(Error),
      "No se pudo dar de baja la disciplina.",
    );
    expect(screen.getAllByText("Disciplina 4")).not.toHaveLength(0);
  });

  it("permite reintentar una carga fallida y representa lista vacía", async () => {
    api.listar.mockRejectedValueOnce(new Error("offline")).mockResolvedValueOnce([]);
    renderPage();

    expect(await screen.findByRole("alert")).toHaveTextContent("No se pudieron cargar las disciplinas.");
    fireEvent.click(screen.getByRole("button", { name: "Reintentar" }));

    expect(await screen.findByText("No hay datos disponibles")).toBeVisible();
    expect(api.listar).toHaveBeenCalledTimes(2);
  });

  it("muestra el estado y la ausencia de horarios, sin baja para una disciplina inactiva", async () => {
    api.listar.mockResolvedValueOnce([{ ...disciplina(8), activo: false, horarios: [] }]);
    renderPage();

    expect(await screen.findAllByText("Sin horarios")).not.toHaveLength(0);
    expect(screen.getAllByText("Baja")).not.toHaveLength(0);
    fireEvent.pointerDown(screen.getAllByRole("button", { name: "Acciones de Disciplina 8" })[0]);
    expect(screen.queryByRole("menuitem", { name: "Dar de baja" })).not.toBeInTheDocument();
  });
});

function renderPage() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false }, mutations: { retry: false } },
  });

  const rendered = render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>
        <DisciplinasPagina />
      </MemoryRouter>
    </QueryClientProvider>,
  );

  return { queryClient, unmount: rendered.unmount };
}

function disciplina(id: number) {
  return {
    id,
    nombre: `Disciplina ${id}`,
    salon: "Sala Norte",
    salonId: 5,
    profesorNombre: "Ana",
    profesorApellido: "Pérez",
    profesorId: 8,
    valorCuota: "15000.00",
    matricula: "9000.00",
    claseSuelta: "3000.00",
    clasePrueba: "1500.00",
    inscritos: 4,
    activo: true,
    horarios: [{
      id: id * 10,
      diaSemana: DiaSemana.LUNES,
      horarioInicio: "09:00",
      duracion: 60,
    }],
  };
}
