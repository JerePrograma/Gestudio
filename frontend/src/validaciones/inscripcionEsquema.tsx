import * as yup from "yup";
import { isMoney } from "../utils/money";

export const inscripcionEsquema = yup.object({
  alumnoId: yup.number().min(1, "Debe seleccionar un alumno").required("El alumno es obligatorio"),
  disciplinaId: yup.number().min(1, "Debe seleccionar una disciplina").required("La disciplina es obligatoria"),
  bonificacionId: yup.number().nullable(),
  fechaInscripcion: yup.string().required("La fecha de inscripción es obligatoria"),
  costoParticular: yup.string().test("money", "El costo debe tener hasta dos decimales", (value) => !value || isMoney(value)),
});
