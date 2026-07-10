import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router-dom";
import { beforeEach, describe, expect, it, vi } from "vitest";
import type { AlumnoResponse, Page } from "../../types/types";

const listar = vi.hoisted(() => vi.fn());
const buscarPorNombre = vi.hoisted(() => vi.fn());
const darBaja = vi.hoisted(() => vi.fn());

vi.mock("../../api/alumnosApi", () => ({
  default: { listar, buscarPorNombre, darBaja },
}));

import AlumnosPagina from "./AlumnosPagina";

describe("AlumnosPagina paginada", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.spyOn(window, "confirm").mockReturnValue(true);

    listar.mockImplementation((page: number) => Promise.resolve(page === 0
      ? pagina([alumno(1)], 123, 3, 0)
      : pagina([], 123, 3, page)));

    buscarPorNombre.mockResolvedValue(pagina([], 0, 0, 0));
    darBaja.mockResolvedValue(undefined);
  });

  it("pide una sola pagina, usa el total backend y reinicia al filtrar", async () => {
    renderPage();

    expect(await screen.findByText("123 registros")).toBeVisible();
    expect(listar).toHaveBeenCalledTimes(1);
    expect(listar).toHaveBeenCalledWith(0, 50);

    fireEvent.click(screen.getByRole("button", { name: "Siguiente" }));
    await waitFor(() => expect(listar).toHaveBeenCalledWith(1, 50));

    fireEvent.change(await screen.findByLabelText("Buscar"), { target: { value: "Ana" } });
    await waitFor(() => expect(buscarPorNombre).toHaveBeenCalledWith("Ana", 0, 50));
    expect(screen.queryByRole("row", { name: /Ana/ })).not.toBeInTheDocument();
  });

  it("no expone el ID interno como columna visible", async () => {
    renderPage();

    expect(await screen.findByText("Ana Prueba")).toBeVisible();

    expect(screen.queryByRole("columnheader", { name: "ID" })).not.toBeInTheDocument();
    expect(screen.getByRole("columnheader", { name: "Alumno" })).toBeVisible();
    expect(screen.getByRole("columnheader", { name: "Documento" })).toBeVisible();
    expect(screen.getByRole("columnheader", { name: "Contacto" })).toBeVisible();
    expect(screen.getByRole("columnheader", { name: "Estado" })).toBeVisible();
  });

  it("invalida solamente el recurso alumnos al dar de baja", async () => {
    const queryClient = renderPage();
    const invalidate = vi.spyOn(queryClient, "invalidateQueries");

    fireEvent.pointerDown((await screen.findAllByRole("button", { name: "Acciones de Ana Prueba" }))[0]);
    fireEvent.click(await screen.findByRole("menuitem", { name: "Dar de baja" }));

    await waitFor(() => expect(darBaja).toHaveBeenCalledWith(1));
    expect(invalidate).toHaveBeenCalledWith({ queryKey: ["alumnos"] });
  });
});

function renderPage() {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });

  render(
    <QueryClientProvider client={queryClient}>
      <MemoryRouter>
        <AlumnosPagina />
      </MemoryRouter>
    </QueryClientProvider>,
  );

  return queryClient;
}

function pagina(content: AlumnoResponse[], totalElements: number, totalPages: number, number: number): Page<AlumnoResponse> {
  return {
    content,
    totalElements,
    totalPages,
    number,
    size: 50,
    first: number === 0,
    last: number + 1 >= totalPages,
  };
}

function alumno(id: number): AlumnoResponse {
  return {
    id,
    nombre: "Ana",
    apellido: "Prueba",
    fechaNacimiento: "2010-01-01",
    fechaIncorporacion: "2026-01-01",
    edad: 16,
    celular1: "2235550000",
    celular2: "",
    email: "",
    documento: "12345678",
    fechaDeBaja: null,
    nombrePadres: "Familia Prueba",
    autorizadoParaSalirSolo: false,
    activo: true,
    otrasNotas: "",
    inscripciones: [],
  };
}