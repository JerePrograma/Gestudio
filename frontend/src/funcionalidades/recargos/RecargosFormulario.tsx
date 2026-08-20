import React, { useState, useEffect, useCallback } from "react";
import { useNavigate, useSearchParams } from "react-router";
import { ErrorMessage, Field, Form, Formik, FormikHelpers } from "formik";
import { toast } from "react-toastify";
import recargosApi from "../../api/recargosApi";
import Boton from "../../componentes/comunes/Boton";
import type {
  RecargoResponse,
  RecargoRegistroRequest,
} from "../../types/types";
import { recargoEsquema } from "../../validaciones/recargoEsquema";
import { normalizeMoneyInput } from "../../utils/money";

// Valores iniciales
const initialRecargoValues: RecargoRegistroRequest = {
  descripcion: "",
  porcentaje: "0",
  valorFijo: "0",
  diaDelMesAplicacion: 1, // ✅ Se inicializa en 1
};

const RecargosFormulario: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [recargoId, setRecargoId] = useState<number | null>(null);
  const [formValues, setFormValues] =
    useState<RecargoRegistroRequest>(initialRecargoValues);
  const [isLoading, setIsLoading] = useState(false);

  // Buscar recargo si existe en la URL
  const handleBuscar = useCallback(async () => {
    const id = searchParams.get("id");
    if (!id) return;

    setIsLoading(true);
    try {
      const recargo: RecargoResponse = await recargosApi.obtenerRecargoPorId(
        Number(id)
      );
      setFormValues({
        descripcion: recargo.descripcion,
        porcentaje: recargo.porcentaje,
        valorFijo: recargo.valorFijo ?? "0",
        diaDelMesAplicacion: recargo.diaDelMesAplicacion,
      });
      setRecargoId(recargo.id);
      toast.success("Recargo cargado correctamente.");
    } catch {
      toast.error("Recargo no encontrado.");
      setFormValues(initialRecargoValues);
    } finally {
      setIsLoading(false);
    }
  }, [searchParams]);

  useEffect(() => {
    handleBuscar();
  }, [handleBuscar]);

  // Guardar o actualizar el recargo
  const handleGuardar = async (
    values: RecargoRegistroRequest,
    { setSubmitting }: FormikHelpers<RecargoRegistroRequest>
  ) => {
    const payload: RecargoRegistroRequest = {
      ...values,
      porcentaje: normalizeMoneyInput(String(values.porcentaje)) ?? String(values.porcentaje),
      valorFijo: normalizeMoneyInput(String(values.valorFijo ?? "0")) ?? String(values.valorFijo ?? "0"),
      diaDelMesAplicacion: Number(values.diaDelMesAplicacion),
    };
    try {
      if (recargoId) {
        await recargosApi.actualizarRecargo(recargoId, payload);
        toast.success("Recargo actualizado correctamente.");
      } else {
        const nuevoRecargo = await recargosApi.crearRecargo(payload);
        setRecargoId(nuevoRecargo.id);
        toast.success("Recargo creado correctamente.");
      }
    } catch {
      toast.error("Error al guardar el recargo.");
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="page-container">
      <h1 className="page-title">
        {recargoId ? "Editar Recargo" : "Nuevo Recargo"}
      </h1>

      {isLoading && <p className="text-center">Cargando datos...</p>}

      <Formik
        initialValues={formValues}
        validationSchema={recargoEsquema}
        onSubmit={handleGuardar}
        enableReinitialize
      >
        {({ isSubmitting }) => (
          <Form className="formulario max-w-4xl mx-auto">
            <div className="form-grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="mb-4">
                <label htmlFor="descripcion" className="auth-label">
                  Descripcion:
                </label>
                <Field
                  type="text"
                  id="descripcion"
                  name="descripcion"
                  className="form-input"
                />
                <ErrorMessage
                  name="descripcion"
                  component="div"
                  className="auth-error"
                />
              </div>

              <div className="mb-4">
                <label htmlFor="porcentaje" className="auth-label">
                  Porcentaje:
                </label>
                <Field
                  type="number"
                  id="porcentaje"
                  name="porcentaje"
                  className="form-input"
                />
                <ErrorMessage
                  name="porcentaje"
                  component="div"
                  className="auth-error"
                />
              </div>

              <div className="mb-4">
                <label htmlFor="valorFijo" className="auth-label">
                  Valor Fijo:
                </label>
                <Field
                  type="number"
                  id="valorFijo"
                  name="valorFijo"
                  className="form-input"
                />
                <ErrorMessage
                  name="valorFijo"
                  component="div"
                  className="auth-error"
                />
              </div>

              <div className="mb-4">
                <label htmlFor="diaDelMesAplicacion" className="auth-label">
                  Dia del Mes:
                </label>
                <Field
                  type="number"
                  id="diaDelMesAplicacion"
                  name="diaDelMesAplicacion"
                  className="form-input"
                  min="1"
                  max="31"
                />
                <ErrorMessage
                  name="diaDelMesAplicacion"
                  component="div"
                  className="auth-error"
                />
              </div>
            </div>

            <div className="form-acciones">
              <Boton
                type="submit"
                disabled={isSubmitting}
                className="page-button"
              >
                {recargoId ? "Actualizar" : "Guardar"}
              </Boton>
              <Boton
                type="button"
                onClick={() => navigate("/recargos")}
                className="page-button-secondary"
              >
                Volver al Listado
              </Boton>
            </div>
          </Form>
        )}
      </Formik>
    </div>
  );
};

export default RecargosFormulario;
