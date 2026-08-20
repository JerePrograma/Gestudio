import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import type { Key, ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS, type PermissionCode } from "../../config/permissions";

const api = vi.hoisted(() => ({ listar: vi.fn(), eliminar: vi.fn() }));
const navigate = vi.hoisted(() => vi.fn());
const toastSuccess = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());
const hasPermission = vi.hoisted(() =>
  vi.fn<(permission: PermissionCode) => boolean>(() => true),
);

vi.mock("../../api/profesoresApi", () => ({
  default: { listarProfesoresActivos: api.listar, eliminarProfesor: api.eliminar },
}));
vi.mock("../../hooks/context/useAuth", () => ({ useAuth: () => ({ hasPermission }) }));
vi.mock("react-toastify", () => ({ toast: { success: toastSuccess, error: toastError } }));
vi.mock("../../componentes/comunes/Tabla", () => ({
  default: ({ data, getRowKey, customRender, actions }: {
    data: ReturnType<typeof profesor>[];
    getRowKey: (row: ReturnType<typeof profesor>) => Key;
    customRender?: (row: ReturnType<typeof profesor>) => ReactNode[];
    actions?: (row: ReturnType<typeof profesor>) => ReactNode;
  }) => <table><thead><tr><th>Profesor</th></tr></thead><tbody>{data.map((row) => <tr key={getRowKey(row)}>
    <td>{customRender?.(row)}</td>
    <td>{actions?.(row)}</td>
  </tr>)}</tbody></table>,
}));
vi.mock("../../componentes/comunes/RowActions", () => ({
  default: ({ label, actions }: {
    label: string;
    actions: Array<{ label: string; onSelect: () => void; requiredPermission?: PermissionCode }>;
  }) => <div>{actions
    .filter((action) => !action.requiredPermission || (
      hasPermission(PERMISSIONS.APP_ACCESS) && hasPermission(action.requiredPermission)
    ))
    .map((action) => <button type="button" key={action.label} onClick={action.onSelect}>
      {label}: {action.label}
    </button>)}</div>,
}));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import ProfesoresPagina from "./ProfesoresPagina";

describe("ProfesoresPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    hasPermission.mockReturnValue(true);
    api.listar.mockResolvedValue([
      profesor(1, "Zoe", "Zulu", true),
      profesor(2, "Ana", "Alfa", false),
      ...Array.from({ length: 24 }, (_, index) => profesor(index + 3, `Docente ${index}`, "Prueba", true)),
    ]);
    api.eliminar.mockResolvedValue(undefined);
    vi.spyOn(window, "confirm").mockReturnValue(true);
  });

  it("cubre carga, filtro, orden y ampliación manual del listado", async () => {
    let resolve!: (value: ReturnType<typeof profesor>[]) => void;
    api.listar.mockReturnValueOnce(new Promise((done) => { resolve = done; }));
    renderPage();
    expect(screen.getByText("Cargando profesores...")).toBeVisible();
    resolve([
      profesor(1, "Zoe", "Zulu", true),
      profesor(2, "Ana", "Alfa", false),
      ...Array.from({ length: 24 }, (_, index) => profesor(index + 3, `Docente ${index}`, "Prueba", true)),
    ]);

    const table = await screen.findByRole("table");
    expect(within(table).getAllByRole("row")[1]).toHaveTextContent("Ana Alfa");
    fireEvent.change(screen.getByLabelText("Orden"), { target: { value: "desc" } });
    expect(within(table).getAllByRole("row")[1]).toHaveTextContent("Zoe Zulu");

    fireEvent.change(screen.getByLabelText("Buscar profesor"), { target: { value: "Ana" } });
    expect(await screen.findAllByText("Ana Alfa")).not.toHaveLength(0);
    expect(screen.queryByText("Zoe Zulu")).not.toBeInTheDocument();

    fireEvent.change(screen.getByLabelText("Buscar profesor"), { target: { value: "" } });
    fireEvent.click(screen.getByRole("button", { name: "Mostrar más" }));
    expect(await screen.findAllByText("Docente 23 Prueba")).not.toHaveLength(0);
  });

  it("navega a alta/edición y elimina sólo tras confirmación", async () => {
    renderPage();

    fireEvent.click(await screen.findByRole("button", { name: "Registrar nuevo profesor" }));
    expect(navigate).toHaveBeenCalledWith("/profesores/formulario");

    fireEvent.click(await screen.findByRole("button", { name: "Acciones de Ana Alfa: Editar" }));
    expect(navigate).toHaveBeenCalledWith("/profesores/formulario?id=2");

    fireEvent.click(await screen.findByRole("button", { name: "Acciones de Ana Alfa: Eliminar" }));
    await waitFor(() => expect(api.eliminar).toHaveBeenCalledWith(2));
    expect(window.confirm).toHaveBeenCalledWith("¿Eliminar a Ana Alfa?");
    expect(toastSuccess).toHaveBeenCalledWith("Profesor eliminado correctamente.");
    expect(api.listar).toHaveBeenCalledTimes(2);
  });

  it("respeta cancelación, denegación de permiso y error de eliminación", async () => {
    vi.mocked(window.confirm).mockReturnValueOnce(false);
    const cancelled = renderPage();

    fireEvent.click(await screen.findByRole("button", { name: "Acciones de Ana Alfa: Eliminar" }));
    expect(api.eliminar).not.toHaveBeenCalled();

    cancelled.unmount();
    hasPermission.mockReturnValue(false);
    const denied = renderPage();
    await screen.findAllByText("Ana Alfa");
    expect(screen.queryByRole("button", { name: "Registrar nuevo profesor" })).not.toBeInTheDocument();

    denied.unmount();
    hasPermission.mockReturnValue(true);
    api.eliminar.mockRejectedValueOnce(new Error("constraint"));
    renderPage();
    fireEvent.click(await screen.findByRole("button", { name: "Acciones de Ana Alfa: Eliminar" }));
    await waitFor(() => expect(toastError).toHaveBeenCalledWith("Error al eliminar el profesor."));
  });

  it("permite reintentar una carga fallida", async () => {
    api.listar.mockRejectedValueOnce(new Error("network"));
    renderPage();

    expect(await screen.findByRole("alert")).toHaveTextContent("Error al cargar profesores.");
    fireEvent.click(screen.getByRole("button", { name: "Reintentar" }));
    expect(await screen.findAllByText("Ana Alfa")).not.toHaveLength(0);
    expect(api.listar).toHaveBeenCalledTimes(2);
  });
});

function renderPage() {
  return render(<MemoryRouter><ProfesoresPagina /></MemoryRouter>);
}

function profesor(id: number, nombre: string, apellido: string, activo: boolean) {
  return { id, nombre, apellido, activo };
}
