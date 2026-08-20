import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import type { Key, ReactNode } from "react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../../config/permissions";

const get = vi.hoisted(() => vi.fn());
const navigate = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());
const hasPermission = vi.hoisted(() => vi.fn(() => true));

vi.mock("../../api/axiosConfig", () => ({ default: { get } }));
vi.mock("../../hooks/context/useAuth", () => ({
  useAuth: () => ({ hasPermission }),
}));
vi.mock("react-toastify", () => ({ toast: { error: toastError } }));
vi.mock("../../componentes/comunes/Tabla", () => ({
  default: ({ data, getRowKey, customRender, actions }: {
    data: ReturnType<typeof bonificacion>[];
    getRowKey: (row: ReturnType<typeof bonificacion>) => Key;
    customRender?: (row: ReturnType<typeof bonificacion>) => ReactNode[];
    actions?: (row: ReturnType<typeof bonificacion>) => ReactNode;
  }) => <div role="table">{data.map((row) => <div role="row" key={getRowKey(row)}>
    {(customRender?.(row) ?? []).map((cell, index) => <span key={index}>{cell}</span>)}
    {actions?.(row)}
  </div>)}</div>,
}));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import BonificacionesPagina from "./BonificacionesPagina";

describe("BonificacionesPagina", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    hasPermission.mockReturnValue(true);
    get.mockResolvedValue({ data: Array.from({ length: 26 }, (_, index) => bonificacion(index + 1)) });
  });

  it("muestra carga, datos y carga manual sin ofrecer más elementos de los existentes", async () => {
    let resolve!: (value: { data: ReturnType<typeof bonificacion>[] }) => void;
    get.mockReturnValueOnce(new Promise((done) => { resolve = done; }));
    renderPage();

    expect(screen.getByText("Cargando...")).toBeVisible();
    resolve({ data: Array.from({ length: 26 }, (_, index) => bonificacion(index + 1)) });

    expect(await screen.findAllByText("Beca 1")).not.toHaveLength(0);
    expect(screen.queryByText("Beca 26")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Mostrar más" }));
    expect(await screen.findAllByText("Beca 26")).not.toHaveLength(0);
    expect(screen.queryByRole("button", { name: "Mostrar más" })).not.toBeInTheDocument();
  });

  it("expone navegación de alta y edición sólo con permiso de configuración", async () => {
    const allowed = renderPage();

    fireEvent.click(await screen.findByRole("button", { name: "Registrar nueva bonificacion" }));
    expect(navigate).toHaveBeenCalledWith("/bonificaciones/formulario");

    fireEvent.click((await screen.findAllByRole("button", { name: "Editar bonificacion Beca 1" }))[0]);
    expect(navigate).toHaveBeenCalledWith("/bonificaciones/formulario?id=1");
    expect(hasPermission).toHaveBeenCalledWith(PERMISSIONS.APP_ACCESS);
    expect(hasPermission).toHaveBeenCalledWith(PERMISSIONS.CONFIG_ADMIN);

    allowed.unmount();
    hasPermission.mockReturnValue(false);
    renderPage();
    await screen.findAllByText("Beca 1");
    expect(screen.queryByRole("button", { name: "Registrar nueva bonificacion" })).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: /Editar bonificacion/ })).not.toBeInTheDocument();
  });

  it("presenta error seguro cuando falla la carga", async () => {
    get.mockRejectedValueOnce(new Error("network"));
    renderPage();

    expect(await screen.findByText("Error al cargar bonificaciones.")).toBeVisible();
    expect(toastError).toHaveBeenCalledWith("Error al cargar bonificaciones:");
  });
});

function renderPage() {
  return render(<MemoryRouter><BonificacionesPagina /></MemoryRouter>);
}

function bonificacion(id: number) {
  return {
    id,
    descripcion: `Beca ${id}`,
    porcentajeDescuento: 10,
    observaciones: "",
    valorFijo: "0.00",
    activo: id % 2 === 1,
  };
}
