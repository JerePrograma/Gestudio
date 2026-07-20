import * as yup from "yup";

export const inscripcionEsquema = yup.object({
  alumnoId: yup.number().min(1, "Debe seleccionar un alumno").required("El alumno es obligatorio"),
  disciplinaId: yup.number().min(1, "Debe seleccionar una disciplina").required("La disciplina es obligatoria"),
  fechaInscripcion: yup.string().required("La fecha de inscripción es obligatoria"),
});
