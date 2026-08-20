import { fireEvent, render, screen, waitFor } from "@testing-library/react";
import { Field, Form, Formik, type FormikConfig } from "formik";
import { describe, expect, it, vi } from "vitest";
import * as Yup from "yup";
import { DiaSemana } from "../../types/types";
import HorariosFieldArray from "./HorariosFieldArray";

interface HorarioFormValues {
  horarios: { diaSemana: DiaSemana; horarioInicio: string; duracion: number }[];
}

type HorarioSubmit = FormikConfig<HorarioFormValues>["onSubmit"];

const schema = Yup.object({
  horarios: Yup.array().of(Yup.object({
    diaSemana: Yup.string().required("Seleccione el día"),
    horarioInicio: Yup.string().required("Ingrese el inicio"),
    duracion: Yup.number().positive("La duración debe ser positiva"),
  })),
});

describe("HorariosFieldArray", () => {
  it("agrega, edita y entrega un horario completo al formulario", async () => {
    const submit = vi.fn<HorarioSubmit>();
    renderHorarioForm([], submit);

    expect(screen.getByText("No se han agregado horarios.")).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Agregar Horario" }));

    fireEvent.change(screen.getByRole("combobox"), { target: { value: DiaSemana.JUEVES } });
    fireEvent.change(inputFollowing("Horario de Inicio"), { target: { value: "20:15" } });
    fireEvent.change(inputFollowing("Duracion (horas)"), { target: { value: "2" } });
    fireEvent.click(screen.getByRole("button", { name: "Enviar" }));

    await waitFor(() => expect(submit).toHaveBeenCalledWith({
      horarios: [{
        diaSemana: DiaSemana.JUEVES,
        horarioInicio: "20:15",
        duracion: 2,
      }],
    }, expect.anything()));
  });

  it("muestra errores del arreglo y permite quitar la fila", async () => {
    const submit = vi.fn<HorarioSubmit>();
    renderHorarioForm([], submit);

    fireEvent.click(screen.getByRole("button", { name: "Agregar Horario" }));
    fireEvent.change(inputFollowing("Duracion (horas)"), { target: { value: "0" } });
    fireEvent.click(screen.getByRole("button", { name: "Enviar" }));

    expect(await screen.findByText("Seleccione el día")).toBeVisible();
    expect(screen.getByText("Ingrese el inicio")).toBeVisible();
    expect(screen.getByText("La duración debe ser positiva")).toBeVisible();
    expect(submit).not.toHaveBeenCalled();

    fireEvent.click(screen.getByRole("button", { name: "Eliminar" }));
    expect(screen.getByText("No se han agregado horarios.")).toBeVisible();
  });

  it("representa y elimina horarios iniciales", () => {
    renderHorarioForm([{
      diaSemana: DiaSemana.SABADO,
      horarioInicio: "10:00",
      duracion: 1.5,
    }], vi.fn<HorarioSubmit>());

    expect(screen.getByRole("combobox")).toHaveValue(DiaSemana.SABADO);
    expect(inputFollowing("Horario de Inicio")).toHaveValue("10:00");
    fireEvent.click(screen.getByRole("button", { name: "Eliminar" }));
    expect(screen.getByText("No se han agregado horarios.")).toBeVisible();
  });
});

function renderHorarioForm(
  horarios: HorarioFormValues["horarios"],
  submit: HorarioSubmit,
) {
  return render(
    <Formik initialValues={{ horarios }} validationSchema={schema} onSubmit={submit}>
      <Form>
        <HorariosFieldArray name="horarios" diasSemana={Object.values(DiaSemana)} />
        <Field type="submit" value="Enviar" />
      </Form>
    </Formik>,
  );
}

function inputFollowing(label: string) {
  const input = screen.getByText(label).parentElement?.querySelector("input");
  if (!input) throw new Error(`No se encontró el campo ${label}`);
  return input;
}
