import { useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { ErrorMessage, Field, Form, Formik } from "formik";
import * as Yup from "yup";
import { toast } from "react-toastify";
import usuariosApi from "../../api/usuariosApi";
import Boton from "../../componentes/comunes/Boton";
import type { RolAsignableResponse } from "../../types/types";
import { usuarioEsquema } from "../../validaciones/usuarioEsquema";

interface UsuarioFormValues {
  nombreUsuario: string;
  contrasena: string;
  roles: string[];
  activo: boolean;
}

const initialValues: UsuarioFormValues = {
  nombreUsuario: "",
  contrasena: "",
  roles: [],
  activo: true,
};

const UsuariosFormulario = () => {
  const [roles, setRoles] = useState<RolAsignableResponse[]>([]);
  const [rolesConservados, setRolesConservados] = useState<string[]>([]);
  const [edicionBloqueada, setEdicionBloqueada] = useState(false);
  const [values, setValues] = useState(initialValues);
  const [loading, setLoading] = useState(true);
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const userId = searchParams.get("id");
  const isEdit = userId !== null;

  useEffect(() => {
    Promise.all([
      usuariosApi.listarRolesAsignables(),
      userId ? usuariosApi.obtenerUsuarioPorId(Number(userId)) : Promise.resolve(null),
    ])
      .then(([rolesDisponibles, usuario]) => {
        setRoles(rolesDisponibles);
        if (usuario) {
          const codigosAsignables = new Set(rolesDisponibles.map((rol) => rol.codigo));
          const noAsignables = usuario.roles.filter((codigo) => !codigosAsignables.has(codigo));

          setRolesConservados(noAsignables);
          setEdicionBloqueada(noAsignables.some((codigo) => codigo !== "PROFESOR"));
          setValues({
            nombreUsuario: usuario.nombreUsuario,
            contrasena: "",
            roles: usuario.roles,
            activo: usuario.activo,
          });
        }
      })
      .catch(() => toast.error("No se pudieron cargar los datos del usuario."))
      .finally(() => setLoading(false));
  }, [userId]);

  const validationSchema = isEdit
    ? usuarioEsquema.shape({ contrasena: Yup.string().min(12, "La contraseña debe tener al menos 12 caracteres") })
    : usuarioEsquema;

  const guardar = async (form: UsuarioFormValues) => {
    try {
      if (isEdit) await usuariosApi.actualizarUsuario(Number(userId), form);
      else await usuariosApi.registrarUsuario(form);
      toast.success(isEdit ? "Usuario actualizado." : "Usuario creado.");
      navigate("/usuarios");
    } catch {
      toast.error("No se pudo guardar el usuario.");
    }
  };

  if (loading) return <div className="text-center py-4">Cargando datos...</div>;

  if (edicionBloqueada) return (
    <div className="page-container">
      <h1 className="page-title">Editar usuario</h1>
      <div role="alert" className="page-card p-4">
        No tenés autorización para modificar los roles actuales de este usuario.
      </div>
      <Boton type="button" onClick={() => navigate("/usuarios")} className="page-button-secondary">
        Volver
      </Boton>
    </div>
  );

  return (
    <div className="page-container">
      <h1 className="page-title">{isEdit ? "Editar usuario" : "Nuevo usuario"}</h1>
      <Formik enableReinitialize initialValues={values} validationSchema={validationSchema} onSubmit={guardar}>
        {({ isSubmitting }) => (
          <Form className="formulario max-w-4xl mx-auto">
            <div className="form-grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label htmlFor="nombreUsuario" className="auth-label">Nombre de usuario</label>
                <Field name="nombreUsuario" id="nombreUsuario" className="form-input" />
                <ErrorMessage name="nombreUsuario" component="div" className="auth-error" />
              </div>
              <div>
                <label htmlFor="contrasena" className="auth-label">
                  {isEdit ? "Nueva contraseña (opcional)" : "Contraseña"}
                </label>
                <Field type="password" name="contrasena" id="contrasena" className="form-input" />
                <ErrorMessage name="contrasena" component="div" className="auth-error" />
              </div>
              <fieldset className="col-span-full page-card p-4">
                <legend className="font-semibold">Roles</legend>
                <div className="grid gap-2 sm:grid-cols-2 md:grid-cols-3">
                  {roles.map((rol) => (
                    <label key={rol.codigo} className="flex items-center gap-2">
                      <Field type="checkbox" name="roles" value={rol.codigo} />
                      <span>{rol.nombre} <small>({rol.codigo})</small></span>
                    </label>
                  ))}
                  {rolesConservados.map((codigo) => (
                    <label key={codigo} className="flex items-center gap-2 text-slate-500">
                      <input type="checkbox" checked disabled readOnly />
                      <span>{codigo} <small>(conservado, no asignable)</small></span>
                    </label>
                  ))}
                </div>
                <ErrorMessage name="roles" component="div" className="auth-error" />
              </fieldset>
              {isEdit && (
                <label className="col-span-full flex items-center gap-2">
                  <Field type="checkbox" name="activo" /> Usuario activo
                </label>
              )}
            </div>
            <div className="form-acciones">
              <Boton type="submit" disabled={isSubmitting} className="page-button">Guardar</Boton>
              <Boton type="button" onClick={() => navigate("/usuarios")} className="page-button-secondary">Cancelar</Boton>
            </div>
          </Form>
        )}
      </Formik>
    </div>
  );
};

export default UsuariosFormulario;
