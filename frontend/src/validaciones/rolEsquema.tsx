import * as Yup from "yup";

export const rolEsquema = Yup.object().shape({
  codigo: Yup.string()
    .matches(/^[A-Za-z][A-Za-z0-9_ -]{1,49}$/, "Código inválido")
    .required("El código es obligatorio"),
  nombre: Yup.string().min(3, "El nombre debe tener al menos 3 caracteres").required("El nombre es obligatorio"),
  descripcionFuncional: Yup.string().max(255, "Máximo 255 caracteres"),
});
