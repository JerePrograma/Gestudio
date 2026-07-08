import * as Yup from "yup";

export const usuarioEsquema = Yup.object().shape({
  nombreUsuario: Yup.string()
    .min(3, "El nombre de usuario debe tener al menos 3 caracteres")
    .required("El nombre de usuario es obligatorio"),
  contrasena: Yup.string()
    .min(12, "La contraseña debe tener al menos 12 caracteres")
    .required("La contraseña es obligatoria"),
  roles: Yup.array().of(Yup.string().required()).min(1, "Seleccione al menos un rol"),
});
