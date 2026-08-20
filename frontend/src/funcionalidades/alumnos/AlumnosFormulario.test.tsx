import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  actualizar: vi.fn(),
  navigate: vi.fn(),
  obtenerPorId: vi.fn(),
  registrar: vi.fn(),
  toastError: vi.fn(),
  toastSuccess: vi.fn(),
}));

vi.mock("../../api/alumnosApi", () => ({
  default: {
    actualizar: mocks.actualizar,
    obtenerPorId: mocks.obtenerPorId,
    registrar: mocks.registrar,
  },
}));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => mocks.navigate,
}));
vi.mock("react-toastify", () => ({
  toast: { error: mocks.toastError, success: mocks.toastSuccess },
}));

import AlumnosFormulario from "./AlumnosFormulario";

describe("AlumnosFormulario", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.actualizar.mockResolvedValue(undefined);
    mocks.obtenerPorId.mockResolvedValue(alumnoExistente());
    mocks.registrar.mockResolvedValue(undefined);
  });

  it("registra la ficha completa y conserva autorizaciones explícitas", async () => {
    renderForm();

    fireEvent.change(screen.getByLabelText("Nombre"), { target: { value: "Ana" } });
    fireEvent.change(screen.getByLabelText("Apellido"), { target: { value: "Pérez" } });
    fireEvent.change(screen.getByLabelText("Fecha de nacimiento"), { target: { value: "2012-04-03" } });
    fireEvent.change(screen.getByLabelText("Fecha de incorporación"), { target: { value: "2026-03-10" } });
    fireEvent.change(screen.getByLabelText("Documento"), { target: { value: "45111222" } });
    fireEvent.change(screen.getByLabelText("Email"), { target: { value: "ana@example.test" } });
    fireEvent.change(screen.getByLabelText("Celular principal"), { target: { value: "2235550101" } });
    fireEvent.change(screen.getByLabelText("Celular alternativo"), { target: { value: "2235550102" } });
    fireEvent.change(screen.getByLabelText("Padres o responsables"), { target: { value: "Familia Pérez" } });
    fireEvent.click(screen.getByRole("checkbox", { name: /Autorizado para salir solo/ }));
    fireEvent.change(screen.getByLabelText("Otras notas"), { target: { value: "Retira su tía." } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar alumno" }));

    await waitFor(() => expect(mocks.registrar).toHaveBeenCalledWith({
      nombre: "Ana",
      apellido: "Pérez",
      fechaNacimiento: "2012-04-03",
      fechaIncorporacion: "2026-03-10",
      celular1: "2235550101",
      celular2: "2235550102",
      email: "ana@example.test",
      documento: "45111222",
      fechaDeBaja: null,
      nombrePadres: "Familia Pérez",
      autorizadoParaSalirSolo: true,
      activo: true,
      otrasNotas: "Retira su tía.",
    }));
    expect(mocks.toastSuccess).toHaveBeenCalledWith("Alumno guardado correctamente.");
    expect(mocks.navigate).toHaveBeenCalledWith("/alumnos");
  });

  it("carga y actualiza un alumno sin perder los campos opcionales", async () => {
    renderForm("/alumnos/formulario?id=7");

    expect(await screen.findByDisplayValue("Lucía")).toBeVisible();
    expect(screen.getByDisplayValue("Observación existente")).toBeVisible();
    expect(screen.getByRole("checkbox", { name: /Alumno activo/ })).toBeChecked();

    fireEvent.change(screen.getByLabelText("Celular principal"), { target: { value: "2235550199" } });
    fireEvent.click(screen.getByRole("checkbox", { name: /Alumno activo/ }));
    fireEvent.click(screen.getByRole("button", { name: "Guardar alumno" }));

    await waitFor(() => expect(mocks.actualizar).toHaveBeenCalledWith(7, expect.objectContaining({
      id: 7,
      nombre: "Lucía",
      celular1: "2235550199",
      activo: false,
      autorizadoParaSalirSolo: true,
      otrasNotas: "Observación existente",
    })));
  });

  it("informa fallos de carga y de guardado sin abandonar el formulario", async () => {
    mocks.obtenerPorId.mockRejectedValueOnce(new Error("load"));
    mocks.actualizar.mockRejectedValueOnce(new Error("save"));
    renderForm("/alumnos/formulario?id=7");

    await waitFor(() => expect(mocks.toastError).toHaveBeenCalledWith("No se pudo cargar el alumno."));
    fireEvent.change(screen.getByLabelText("Nombre"), { target: { value: "Ana" } });
    fireEvent.change(screen.getByLabelText("Apellido"), { target: { value: "Pérez" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar alumno" }));

    await waitFor(() => expect(mocks.toastError).toHaveBeenCalledWith("No se pudo guardar el alumno."));
    expect(screen.getByRole("button", { name: "Guardar alumno" })).toBeEnabled();
    expect(mocks.navigate).not.toHaveBeenCalled();
  });

  it("cancela sin persistir cambios", () => {
    renderForm();

    fireEvent.click(screen.getByRole("button", { name: "Cancelar" }));

    expect(mocks.navigate).toHaveBeenCalledWith("/alumnos");
    expect(mocks.registrar).not.toHaveBeenCalled();
  });
});

function renderForm(entry = "/alumnos/formulario") {
  render(
    <MemoryRouter initialEntries={[entry]}>
      <AlumnosFormulario />
    </MemoryRouter>,
  );
}

function alumnoExistente() {
  return {
    id: 7,
    nombre: "Lucía",
    apellido: "Gómez",
    fechaNacimiento: "2011-06-02",
    fechaIncorporacion: "2024-03-01",
    celular1: "2235550100",
    celular2: null,
    email: "lucia@example.test",
    documento: "44999888",
    fechaDeBaja: null,
    nombrePadres: "Familia Gómez",
    autorizadoParaSalirSolo: true,
    activo: true,
    otrasNotas: "Observación existente",
    edad: 15,
    inscripciones: [],
  };
}
