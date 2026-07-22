import type React from "react";
import { useState, useEffect, useCallback } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { Formik, Form, Field, ErrorMessage } from "formik";
import { salonEsquema } from "../../validaciones/salonEsquema";
import salonesApi from "../../api/salonesApi";
import Boton from "../../componentes/comunes/Boton";
import { toast } from "react-toastify";
import { Search } from "lucide-react";
import type {
  SalonRegistroRequest,
  SalonModificacionRequest,
  SalonResponse,
} from "../../types/types";

const initialSalonValues: SalonRegistroRequest &
  Partial<SalonModificacionRequest> = {
  nombre: "",
  descripcion: "",
};

const SalonesFormulario: React.FC = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [salonId, setSalonId] = useState<number | null>(null);
  const [formValues, setFormValues] = useState<
    SalonRegistroRequest & Partial<SalonModificacionRequest>
  >(initialSalonValues);
  const [mensaje, setMensaje] = useState("");
  const [idBusqueda, setIdBusqueda] = useState("");

  const resetearFormulario = useCallback(() => {
    setFormValues(initialSalonValues);
    setSalonId(null);
    setMensaje("");
    setIdBusqueda("");
  }, []);

  const convertToSalonFormValues = useCallback(
    (
      salon: SalonResponse
    ): SalonRegistroRequest & Partial<SalonModificacionRequest> => {
      return {
        nombre: salon.nombre || "",
        descripcion: salon.descripcion || "",
      };
    },
    []
  );

  const handleBuscar = useCallback(async () => {
    if (!idBusqueda) {
      setMensaje("Por favor, ingrese un ID de salon.");
      return;
    }

    try {
      const salon = await salonesApi.obtenerSalonPorId(Number(idBusqueda));
      const convertedSalon = convertToSalonFormValues(salon);
      setFormValues(convertedSalon);
      setSalonId(salon.id);
      setMensaje("Salon encontrado.");
    } catch {
      toast.error("Error al buscar el salon:");
      setMensaje("Salon no encontrado.");
      resetearFormulario();
    }
  }, [idBusqueda, convertToSalonFormValues, resetearFormulario]);

  useEffect(() => {
    const idParam = searchParams.get("id");
    if (idParam) {
      setIdBusqueda(idParam);
      handleBuscar();
    }
  }, [searchParams, handleBuscar]);

  const handleGuardar = useCallback(
    async (
      values: SalonRegistroRequest & Partial<SalonModificacionRequest>
    ) => {
      try {
        if (salonId) {
          await salonesApi.actualizarSalon(
            salonId,
            values as SalonModificacionRequest
          );
          toast.success("Salon actualizado correctamente.");
        } else {
          const nuevoSalon = await salonesApi.registrarSalon(
            values as SalonRegistroRequest
          );
          setSalonId(nuevoSalon.id);
          toast.success("Salon creado correctamente.");
        }
        setMensaje("Salon guardado exitosamente.");
      } catch {
        toast.error("Error al guardar el salon.");
        setMensaje("Error al guardar el salon.");
      }
    },
    [salonId]
  );

  return (
    <div className="page-container">
      <h1 className="page-title">Formulario de Salon</h1>
      <Formik
        initialValues={formValues}
        validationSchema={salonEsquema}
        onSubmit={handleGuardar}
        enableReinitialize
      >
        {({ isSubmitting, resetForm }) => (
          <Form className="formulario max-w-4xl mx-auto">
            <div className="form-grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="col-span-full mb-4">
                <label htmlFor="idBusqueda" className="auth-label">
                  Numero de Salon:
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
                <label htmlFor="nombre" className="auth-label">
                  Nombre:
                </label>
                <Field name="nombre" type="text" className="form-input" />
                <ErrorMessage
                  name="nombre"
                  component="div"
                  className="auth-error"
                />
              </div>

              <div className="mb-4">
                <label htmlFor="descripcion" className="auth-label">
                  Descripcion:
                </label>
                <Field
                  name="descripcion"
                  as="textarea"
                  className="form-input"
                />
                <ErrorMessage
                  name="descripcion"
                  component="div"
                  className="auth-error"
                />
              </div>
            </div>

            {mensaje && (
              <p
                className={`form-mensaje ${mensaje.includes("Error") || mensaje.includes("no encontrado")
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
                onClick={() => navigate("/salones")}
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

export default SalonesFormulario;
