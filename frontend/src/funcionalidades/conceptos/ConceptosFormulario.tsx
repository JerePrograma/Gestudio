import { useState, useEffect, useCallback } from "react";
import { useNavigate, useSearchParams } from "react-router";
import { Formik, Form, Field, ErrorMessage } from "formik";
import { toast } from "react-toastify";
import Boton from "../../componentes/comunes/Boton";
import * as Yup from "yup";
import conceptosApi from "../../api/conceptosApi";
import subConceptosApi from "../../api/subConceptosApi";
import type {
  ConceptoRegistroRequest,
} from "../../types/types";
import type { ConceptoResponse, SubConceptoResponse } from "../../types/types";
import { normalizeMoneyInput } from "../../utils/money";

interface FormValues {
  id?: number;
  descripcion: string;
  precio: string;
  subConceptoId: number;
  activo: boolean;
}

const initialConceptoValues: FormValues = {
  descripcion: "",
  precio: "0",
  subConceptoId: 0,
  activo: true,
};

const conceptoSchema = Yup.object().shape({
  descripcion: Yup.string().required("La descripción es obligatoria"),
  precio: Yup.number().positive().required("El precio es obligatorio"),
  subConceptoId: Yup.number().min(1, "Selecciona un subconcepto").required("El subconcepto es obligatorio"),
});

const ConceptosFormulario: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [conceptoId, setConceptoId] = useState<number | null>(null);
  const [formValues, setFormValues] = useState<FormValues>(initialConceptoValues);
  const [mensaje, setMensaje] = useState("");
  const [subConceptos, setSubConceptos] = useState<SubConceptoResponse[]>([]);

  // Al montar el componente, cargar la lista completa de subconceptos.
  useEffect(() => {
    const fetchSubConceptos = async () => {
      try {
        const subs = await subConceptosApi.listarSubConceptos();
        setSubConceptos(subs);
      } catch {
        toast.error("Error al cargar la lista de subconceptos");
      }
    };
    fetchSubConceptos();
  }, []);

  // Si hay un parámetro "id" en la URL, cargar el concepto para edición
  const handleBuscar = useCallback(async () => {
    const idParam = searchParams.get("id");
    if (idParam) {
      try {
        const concepto: ConceptoResponse = await conceptosApi.obtenerConceptoPorId(Number(idParam));
        setFormValues({
          id: concepto.id,
          descripcion: concepto.descripcion,
          precio: concepto.precio,
          subConceptoId: concepto.subConcepto.id,
          activo: concepto.activo ?? true,
        });
        setConceptoId(concepto.id);
        setMensaje("Concepto encontrado.");
      } catch {
        toast.error("Error al buscar el concepto:");
        setMensaje("Concepto no encontrado.");
        setFormValues(initialConceptoValues);
        setConceptoId(null);
      }
    }
  }, [searchParams]);

  useEffect(() => {
    handleBuscar();
  }, [handleBuscar]);

  const handleSubmit = useCallback(
    async (values: FormValues) => {
      try {
        const payload: ConceptoRegistroRequest = {
          descripcion: values.descripcion,
          precio: normalizeMoneyInput(String(values.precio)) ?? String(values.precio),
          // Se construye el objeto de subconcepto únicamente con el id
          subConcepto: { id: Number(values.subConceptoId), descripcion: "" },
          activo: values.activo,
        };

        if (conceptoId) {
          await conceptosApi.actualizarConcepto(conceptoId, payload);
          toast.success("Concepto actualizado correctamente.");
        } else {
          await conceptosApi.registrarConcepto(payload);
          toast.success("Concepto creado correctamente.");
        }
        setMensaje("Concepto guardado exitosamente.");
        navigate("/conceptos");
      } catch {
        toast.error("Error al guardar el concepto.");
        setMensaje("Error al guardar el concepto.");
      }
    },
    [conceptoId, navigate]
  );

  return (
    <div className="page-container">
      <h1 className="page-title">Formulario de Concepto</h1>
      {mensaje && (
        <p className={`form-mensaje ${mensaje.includes("Error") ? "form-mensaje-error" : "form-mensaje-success"}`}>
          {mensaje}
        </p>
      )}
      <Formik
        initialValues={formValues}
        validationSchema={conceptoSchema}
        onSubmit={handleSubmit}
        enableReinitialize
      >
        {({ isSubmitting, resetForm }) => (
          <Form className="formulario max-w-4xl mx-auto">
            {/* Campos principales: Descripción y Precio */}
            <div className="form-grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="mb-4">
                <label htmlFor="descripcion" className="auth-label">
                  Descripción:
                </label>
                <Field id="descripcion" name="descripcion" type="text" className="form-input" />
                <ErrorMessage name="descripcion" component="div" className="auth-error" />
              </div>
              <div className="mb-4">
                <label htmlFor="precio" className="auth-label">
                  Precio:
                </label>
                <Field id="precio" name="precio" type="number" className="form-input" />
                <ErrorMessage name="precio" component="div" className="auth-error" />
              </div>
            </div>

            {/* Campo de Subconcepto (select) */}
            <div className="mb-4">
              <label htmlFor="subConceptoId" className="auth-label">
                Subconcepto:
              </label>
              <Field id="subConceptoId" as="select" name="subConceptoId" className="form-input">
                <option value={0}>Seleccione un subconcepto...</option>
                {subConceptos.map((sub) => (
                  <option key={sub.id} value={sub.id}>
                    {sub.descripcion}
                  </option>
                ))}
              </Field>
              <ErrorMessage name="subConceptoId" component="div" className="auth-error" />
            </div>

            <div className="form-acciones">
              <Boton type="submit" disabled={isSubmitting} className="page-button">
                {conceptoId ? "Actualizar" : "Crear"} Concepto
              </Boton>
              <Boton type="button" onClick={() => resetForm()} className="page-button-secondary">
                Limpiar
              </Boton>
              <Boton type="button" onClick={() => navigate("/conceptos")} className="page-button-secondary">
                Cancelar
              </Boton>
            </div>
          </Form>
        )}
      </Formik>
    </div>
  );
};

export default ConceptosFormulario;
