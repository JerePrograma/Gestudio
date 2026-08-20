import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { DiaSemana } from "../../types/types";

const api = vi.hoisted(() => ({
  registrar: vi.fn(),
  obtener: vi.fn(),
  actualizar: vi.fn(),
  listarSalones: vi.fn(),
  listarProfesores: vi.fn(),
}));
const navigate = vi.hoisted(() => vi.fn());
const toastSuccess = vi.hoisted(() => vi.fn());
const toastError = vi.hoisted(() => vi.fn());

vi.mock("../../api/disciplinasApi", () => ({
  default: {
    registrarDisciplina: api.registrar,
    obtenerDisciplinaPorId: api.obtener,
    actualizarDisciplina: api.actualizar,
  },
}));
vi.mock("../../api/salonesApi", () => ({
  default: { listarSalones: api.listarSalones },
}));
vi.mock("../../api/profesoresApi", () => ({
  default: { listarProfesoresActivos: api.listarProfesores },
}));
vi.mock("react-toastify", () => ({
  toast: { success: toastSuccess, error: toastError },
}));
vi.mock("react-router", async (importOriginal) => ({
  ...(await importOriginal<typeof import("react-router")>()),
  useNavigate: () => navigate,
}));

import DisciplinasFormulario from "./DisciplinasFormulario";

describe("DisciplinasFormulario", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    api.listarSalones.mockResolvedValue({ content: [salon()] });
    api.listarProfesores.mockResolvedValue([profesor()]);
    api.registrar.mockResolvedValue(disciplina(73));
    api.obtener.mockResolvedValue(disciplina(12));
    api.actualizar.mockResolvedValue(disciplina(12));
  });

  it("crea una disciplina con referencias válidas y el horario ingresado", async () => {
    renderForm();

    expect(screen.getByRole("button", { name: "Guardar" })).toBeDisabled();
    expect(await screen.findByRole("option", { name: "Sala Norte" })).toBeVisible();
    expect(screen.getByRole("option", { name: "Pérez, Ana" })).toBeVisible();
    expect(api.listarSalones).toHaveBeenCalledWith(0, 200);
    expect(api.listarProfesores).toHaveBeenCalledWith(true);

    fireEvent.change(screen.getByLabelText("Nombre"), { target: { value: "Tango inicial" } });
    fireEvent.change(screen.getByLabelText("Salón"), { target: { value: "5" } });
    fireEvent.change(screen.getByLabelText("Profesor"), { target: { value: "8" } });
    fireEvent.click(screen.getByRole("button", { name: "Agregar horario" }));

    const horario = screen.getByDisplayValue("18:00").closest("div")!;
    fireEvent.change(within(horario).getByRole("combobox"), { target: { value: DiaSemana.MARTES } });
    fireEvent.change(within(horario).getByDisplayValue("18:00"), { target: { value: "19:30" } });
    fireEvent.change(within(horario).getByDisplayValue("60"), { target: { value: "90" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    await waitFor(() => expect(api.registrar).toHaveBeenCalledWith({
      nombre: "Tango inicial",
      salonId: 5,
      profesorId: 8,
      valorCuota: "0",
      matricula: "0",
      claseSuelta: "0",
      clasePrueba: "0",
      activo: true,
      horarios: [{
        diaSemana: DiaSemana.MARTES,
        horarioInicio: "19:30",
        duracion: 90,
      }],
    }));
    expect(toastSuccess).toHaveBeenCalledWith(
      "Disciplina creada. Cargá ahora su tarifa inicial con vigencia.",
    );
    expect(navigate).toHaveBeenCalledWith("/disciplinas/73/tarifas");
  });

  it("precarga, modifica y guarda una disciplina existente sin reescribir importes históricos", async () => {
    renderForm("/disciplinas/formulario?id=12");

    expect(await screen.findByRole("heading", { name: "Editar disciplina" })).toBeVisible();
    expect(await screen.findByDisplayValue("Danza clásica")).toBeVisible();
    expect(screen.getByLabelText("Activa")).toBeChecked();
    expect(screen.getByDisplayValue("09:00")).toBeVisible();

    fireEvent.change(screen.getByLabelText("Nombre"), { target: { value: "Danza clásica II" } });
    fireEvent.click(screen.getByLabelText("Activa"));
    fireEvent.click(screen.getByRole("button", { name: "Quitar" }));
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    await waitFor(() => expect(api.actualizar).toHaveBeenCalledWith(12, {
      nombre: "Danza clásica II",
      salonId: 5,
      profesorId: 8,
      valorCuota: "15000.00",
      matricula: "9000.00",
      claseSuelta: "3000.00",
      clasePrueba: "1500.00",
      activo: false,
      horarios: [],
    }));
    expect(api.registrar).not.toHaveBeenCalled();
    expect(toastSuccess).toHaveBeenCalledWith("Disciplina guardada correctamente.");
    expect(navigate).toHaveBeenCalledWith("/disciplinas");
  });

  it("informa fallos de carga y de guardado sin dejar el formulario bloqueado", async () => {
    api.listarSalones.mockRejectedValueOnce(new Error("references unavailable"));
    api.obtener.mockRejectedValueOnce(new Error("not found"));
    const failedLoad = renderForm("/disciplinas/formulario?id=99");

    await waitFor(() => {
      expect(toastError).toHaveBeenCalledWith("No se pudieron cargar salones y profesores.");
      expect(toastError).toHaveBeenCalledWith("No se pudo cargar la disciplina.");
    });

    expect(screen.getByRole("button", { name: "Guardar" })).toBeDisabled();
    expect(navigate).not.toHaveBeenCalled();

    failedLoad.unmount();
    api.actualizar.mockRejectedValueOnce(new Error("conflict"));
    renderForm("/disciplinas/formulario?id=12");

    await screen.findByDisplayValue("Danza clásica");

    fireEvent.change(screen.getByLabelText("Nombre"), { target: { value: "Contemporáneo" } });
    fireEvent.click(screen.getByRole("button", { name: "Guardar" }));

    await waitFor(() => expect(toastError).toHaveBeenCalledWith("No se pudo guardar la disciplina."));
    expect(screen.getByRole("button", { name: "Guardar" })).toBeEnabled();
    expect(navigate).not.toHaveBeenCalled();
  });

  it("cancela el alta sin llamar a la API", () => {
    renderForm();

    fireEvent.click(screen.getByRole("button", { name: "Cancelar" }));

    expect(navigate).toHaveBeenCalledWith("/disciplinas");
    expect(api.registrar).not.toHaveBeenCalled();
  });
});

function renderForm(initialEntry = "/disciplinas/formulario") {
  return render(
    <MemoryRouter initialEntries={[initialEntry]}>
      <DisciplinasFormulario />
    </MemoryRouter>,
  );
}

function salon() {
  return { id: 5, nombre: "Sala Norte", descripcion: "Primer piso" };
}

function profesor() {
  return { id: 8, nombre: "Ana", apellido: "Pérez", activo: true };
}

function disciplina(id: number) {
  return {
    id,
    nombre: "Danza clásica",
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
      id: 31,
      diaSemana: DiaSemana.LUNES,
      horarioInicio: "09:00",
      duracion: 60,
    }],
  };
}
