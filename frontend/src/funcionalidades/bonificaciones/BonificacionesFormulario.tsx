import type React from "react";
import { useState, useEffect, useCallback } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import Boton from "../../componentes/comunes/Boton";
import { ErrorMessage, Field, Form, Formik, type FormikHelpers } from "formik";
import { bonificacionEsquema } from "../../validaciones/bonificacionEsquema";
import bonificacionesApi from "../../api/bonificacionesApi";
import { toast } from "react-toastify";
import { Search } from "lucide-react";
import type {
  BonificacionResponse,
  BonificacionRegistroRequest,
  BonificacionModificacionRequest,
} from "../../types/types";

const initialBonificacionValues: BonificacionRegistroRequest &
  Partial<BonificacionModificacionRequest> = {
  descripcion: "",
  porcentajeDescuento: "0",
  observaciones: "",
  valorFijo: "0",
  activo: true,
};

const BonificacionesFormulario: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [bonificacionId, setBonificacionId] = useState<number | null>(null);
  const [formValues, setFormValues] = useState<
    BonificacionRegistroRequest & Partial<BonificacionModificacionRequest>
  >(initialBonificacionValues);
  const [mensaje, setMensaje] = useState("");
  const [idBusqueda, setIdBusqueda] = useState("");

  const resetearFormulario = useCallback(() => {
    setFormValues(initialBonificacionValues);
    setBonificacionId(null);
    setMensaje("");
    setIdBusqueda("");
  }, []);

  const convertToBonificacionFormValues = useCallback(
    (
      bonificacion: BonificacionResponse
    ): BonificacionRegistroRequest &
      Partial<BonificacionModificacionRequest> => {
      return {
        descripcion: bonificacion.descripcion,
        porcentajeDescuento: bonificacion.porcentajeDescuento,
        observaciones: bonificacion.observaciones || "",
        valorFijo: bonificacion.valorFijo ?? "0",
        activo: bonificacion.activo,
      };
    },
    []
  );

  const handleBuscar = useCallback(async () => {
    if (!idBusqueda) {
      setMensaje("Por favor, ingrese un ID de bonificacion.");
      return;
    }

    try {
      const bonificacion = await bonificacionesApi.obtenerBonificacionPorId(
        Number(idBusqueda)
      );
      const convertedBonificacion =
        convertToBonificacionFormValues(bonificacion);
      setFormValues(convertedBonificacion);
      setBonificacionId(bonificacion.id);
      setMensaje("Bonificacion encontrada.");
    } catch {
      toast.error("Error al buscar la bonificacion:");
      setMensaje("Bonificacion no encontrada.");
      resetearFormulario();
    }
  }, [idBusqueda, convertToBonificacionFormValues, resetearFormulario]);

  useEffect(() => {
    const idParam = searchParams.get("id");
    if (idParam) {
      setIdBusqueda(idParam);
      handleBuscar();
    }
  }, [searchParams, handleBuscar]);

  const handleGuardar = useCallback(
    async (
      values: BonificacionRegistroRequest &
        Partial<BonificacionModificacionRequest>,
      {
        setSubmitting,
      }: FormikHelpers<
        BonificacionRegistroRequest & Partial<BonificacionModificacionRequest>
      >
    ) => {
      try {
        if (bonificacionId) {
          await bonificacionesApi.actualizarBonificacion(
            bonificacionId,
            values as BonificacionModificacionRequest
          );
          toast.success("Bonificacion actualizada correctamente.");
        } else {
          const nuevaBonificacion = await bonificacionesApi.crearBonificacion(
            values as BonificacionRegistroRequest
          );
          setBonificacionId(nuevaBonificacion.id);
          toast.success("Bonificacion creada correctamente.");
        }
        setMensaje("Bonificacion guardada exitosamente.");
      } catch {
        toast.error("Error al guardar la bonificacion.");
        setMensaje("Error al guardar la bonificacion.");
      } finally {
        setSubmitting(false);
      }
    },
    [bonificacionId]
  );

  return (
    <div className="page-container">
      <h1 className="page-title">Formulario de Bonificacion</h1>
      <Formik
        initialValues={formValues}
        validationSchema={bonificacionEsquema}
        onSubmit={handleGuardar}
        enableReinitialize
      >
        {({ isSubmitting, resetForm }) => (
          <Form className="formulario max-w-4xl mx-auto">
            <div className="form-grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="col-span-full mb-4">
                <label htmlFor="idBusqueda" className="auth-label">
                  Numero de Bonificacion:
                </label>
                <div className="flex gap-2">
                  <input
                    type="number"
                    id="idBusqueda"
                    value={idBusqueda}
                    onChange={(e) => setIdBusqueda(e.target.value)}
                    className="form-input flex-grow"
                  />
                  <Boton
                    onClick={handleBuscar}
                    type="button"
                    className="page-button"
                  >
                    <Search className="w-5 h-5 mr-2" />
                    Buscar
                  </Boton>
                </div>
              </div>

              <div className="mb-4">
                <label htmlFor="descripcion" className="auth-label">
                  Descripcion:
                </label>
                <Field
                  type="text"
                  id="descripcion"
                  name="descripcion"
                  placeholder="Ejemplo: 1/2 BECA"
                  className="form-input"
                />
                <ErrorMessage
                  name="descripcion"
                  component="div"
                  className="auth-error"
                />
              </div>

              <div className="mb-4">
                <label htmlFor="porcentajeDescuento" className="auth-label">
                  Porcentaje de Descuento:
                </label>
                <Field
                  type="number"
                  id="porcentajeDescuento"
                  name="porcentajeDescuento"
                  placeholder="Ejemplo: 50"
                  className="form-input"
                />
                <ErrorMessage
                  name="porcentajeDescuento"
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
                  placeholder="Ejemplo: 1000"
                  className="form-input"
                />
                <ErrorMessage
                  name="valorFijo"
                  component="div"
                  className="auth-error"
                />
              </div>

              <div className="col-span-full mb-4">
                <label htmlFor="observaciones" className="auth-label">
                  Observaciones:
                </label>
                <Field
                  as="textarea"
                  id="observaciones"
                  name="observaciones"
                  className="form-input h-24"
                />
                <ErrorMessage
                  name="observaciones"
                  component="div"
                  className="auth-error"
                />
              </div>

              {bonificacionId !== null && (
                <div className="col-span-full mb-4">
                  <label className="flex items-center space-x-2">
                    <Field
                      type="checkbox"
                      name="activo"
                      className="form-checkbox"
                    />
                    <span>Activo</span>
                  </label>
                  <ErrorMessage
                    name="activo"
                    component="div"
                    className="auth-error"
                  />
                </div>
              )}
            </div>

            {mensaje && (
              <p
                className={`form-mensaje ${
                  mensaje.includes("Error") || mensaje.includes("no encontrada")
                    ? "form-mensaje-error"
                    : "form-mensaje-success"
                }`}
              >
                {mensaje}
              </p>
            )}

            <div className="form-acciones">
              <Boton
                type="submit"
                disabled={isSubmitting}
                className="page-button"
              >
                Guardar
              </Boton>
              <Boton
                type="button"
                onClick={() => {
                  resetearFormulario();
                  resetForm();
                }}
                className="page-button-secondary"
              >
                Limpiar
              </Boton>
              <Boton
                type="button"
                onClick={() => navigate("/bonificaciones")}
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

export default BonificacionesFormulario;
