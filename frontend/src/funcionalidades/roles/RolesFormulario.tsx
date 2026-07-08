import { useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { ErrorMessage, Field, Form, Formik } from "formik";
import { toast } from "react-toastify";
import permisosApi from "../../api/permisosApi";
import rolesApi from "../../api/rolesApi";
import Boton from "../../componentes/comunes/Boton";
import type { PermisoResponse } from "../../types/types";
import { rolEsquema } from "../../validaciones/rolEsquema";
import PermisosChecklist from "./PermisosChecklist";

interface Values {
  codigo: string;
  nombre: string;
  descripcionFuncional: string;
  activo: boolean;
  permisos: string[];
}

const emptyValues: Values = {
  codigo: "",
  nombre: "",
  descripcionFuncional: "",
  activo: true,
  permisos: [],
};

const RolesFormulario = () => {
  const [values, setValues] = useState(emptyValues);
  const [permisos, setPermisos] = useState<PermisoResponse[]>([]);
  const [editable, setEditable] = useState(true);
  const [loading, setLoading] = useState(true);
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const id = searchParams.get("id");

  useEffect(() => {
    Promise.all([
      permisosApi.listar(),
      id ? rolesApi.obtener(Number(id)) : Promise.resolve(null),
    ])
      .then(([disponibles, rol]) => {
        setPermisos(disponibles.filter((permiso) => permiso.activo));
        if (rol) {
          setValues({
            codigo: rol.codigo,
            nombre: rol.nombre,
            descripcionFuncional: rol.descripcionFuncional ?? "",
            activo: rol.activo,
            permisos: rol.permisos.map((permiso) => permiso.codigo),
          });
          setEditable(rol.editable && !rol.sistema);
        }
      })
      .catch(() => toast.error("No se pudo cargar el rol."))
      .finally(() => setLoading(false));
  }, [id]);

  const guardar = async (form: Values) => {
    try {
      const rol = id
        ? await rolesApi.modificar(Number(id), {
            nombre: form.nombre,
            descripcionFuncional: form.descripcionFuncional || undefined,
            activo: form.activo,
          })
        : await rolesApi.crear({
            codigo: form.codigo,
            nombre: form.nombre,
            descripcionFuncional: form.descripcionFuncional || undefined,
          });
      await rolesApi.asignarPermisos(rol.id, form.permisos);
      toast.success("Rol guardado.");
      navigate("/roles");
    } catch {
      toast.error("No se pudo guardar el rol.");
    }
  };

  if (loading) return <div className="text-center py-4">Cargando...</div>;

  return (
    <div className="page-container">
      <h1 className="page-title">{id ? "Editar rol" : "Nuevo rol"}</h1>
      {!editable && <p className="auth-error">Los roles de sistema son de solo lectura.</p>}
      <Formik enableReinitialize initialValues={values} validationSchema={rolEsquema} onSubmit={guardar}>
        {({ isSubmitting, values: form, setFieldValue }) => (
          <Form className="formulario max-w-5xl mx-auto">
            <div className="form-grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div>
                <label htmlFor="codigo" className="auth-label">Código</label>
                <Field name="codigo" id="codigo" className="form-input" disabled={Boolean(id) || !editable} />
                <ErrorMessage name="codigo" component="div" className="auth-error" />
              </div>
              <div>
                <label htmlFor="nombre" className="auth-label">Nombre</label>
                <Field name="nombre" id="nombre" className="form-input" disabled={!editable} />
                <ErrorMessage name="nombre" component="div" className="auth-error" />
              </div>
              <div className="col-span-full">
                <label htmlFor="descripcionFuncional" className="auth-label">Descripción funcional</label>
                <Field as="textarea" name="descripcionFuncional" id="descripcionFuncional" className="form-input" disabled={!editable} />
              </div>
              <div className="col-span-full">
                <h2 className="mb-2 font-semibold">Permisos</h2>
                <PermisosChecklist
                  permisos={permisos}
                  seleccionados={form.permisos}
                  onChange={(codigos) => setFieldValue("permisos", codigos)}
                  disabled={!editable}
                />
              </div>
              {id && editable && (
                <label className="col-span-full flex items-center gap-2">
                  <Field type="checkbox" name="activo" /> Rol activo
                </label>
              )}
            </div>
            <div className="form-acciones">
              {editable && <Boton type="submit" disabled={isSubmitting} className="page-button">Guardar</Boton>}
              <Boton type="button" onClick={() => navigate("/roles")} className="page-button-secondary">Volver</Boton>
            </div>
          </Form>
        )}
      </Formik>
    </div>
  );
};

export default RolesFormulario;
