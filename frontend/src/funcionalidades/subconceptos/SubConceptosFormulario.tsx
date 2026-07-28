import { useState, useEffect, useCallback } from "react";
import { useNavigate, useSearchParams } from "react-router";
import { Formik, Form, Field, ErrorMessage } from "formik";
import { subConceptoEsquema } from "../../validaciones/subConceptoEsquema";
import subConceptosApi from "../../api/subConceptosApi";
import Boton from "../../componentes/comunes/Boton";
import { toast } from "react-toastify";
import type { SubConceptoRegistroRequest, SubConceptoModificacionRequest, SubConceptoResponse } from "../../types/types";

const initialSubConceptoValues: SubConceptoRegistroRequest & Partial<SubConceptoModificacionRequest> = {
    descripcion: "",
};

const SubConceptosFormulario: React.FC = () => {
    const navigate = useNavigate();
    const [searchParams] = useSearchParams();
    const [subConceptoId, setSubConceptoId] = useState<number | null>(null);
    const [formValues, setFormValues] = useState(initialSubConceptoValues);
    const [mensaje, setMensaje] = useState("");
    const [idBusqueda, setIdBusqueda] = useState("");

    const resetearFormulario = useCallback(() => {
        setFormValues(initialSubConceptoValues);
        setSubConceptoId(null);
        setMensaje("");
        setIdBusqueda("");
    }, []);

    const convertToSubConceptoFormValues = useCallback(
        (sub: SubConceptoResponse): SubConceptoRegistroRequest & Partial<SubConceptoModificacionRequest> => ({
            descripcion: sub.descripcion,
        }),
        []
    );

    const handleBuscar = useCallback(async () => {
        if (!idBusqueda) {
            setMensaje("Por favor, ingrese un ID de subconcepto.");
            return;
        }
        try {
            const sub = await subConceptosApi.obtenerSubConceptoPorId(Number(idBusqueda));
            const converted = convertToSubConceptoFormValues(sub);
            setFormValues(converted);
            setSubConceptoId(sub.id);
            setMensaje("Subconcepto encontrado.");
        } catch {
            toast.error("Error al buscar el subconcepto:");
            setMensaje("Subconcepto no encontrado.");
            resetearFormulario();
        }
    }, [idBusqueda, convertToSubConceptoFormValues, resetearFormulario]);

    useEffect(() => {
        const idParam = searchParams.get("id");
        if (idParam) {
            setIdBusqueda(idParam);
            handleBuscar();
        }
    }, [searchParams, handleBuscar]);

    const handleGuardar = useCallback(
        async (values: SubConceptoRegistroRequest & Partial<SubConceptoModificacionRequest>) => {
            try {
                if (subConceptoId) {
                    await subConceptosApi.actualizarSubConcepto(subConceptoId, values as SubConceptoModificacionRequest);
                    toast.success("Subconcepto actualizado correctamente.");
                } else {
                    const nuevoSub = await subConceptosApi.registrarSubConcepto(values as SubConceptoRegistroRequest);
                    setSubConceptoId(nuevoSub.id);
                    toast.success("Subconcepto creado correctamente.");
                }
                setMensaje("Subconcepto guardado exitosamente.");
            } catch {
                toast.error("Error al guardar el subconcepto.");
                setMensaje("Error al guardar el subconcepto.");
            }
        },
        [subConceptoId]
    );

    return (
        <div className="page-container">
            <h1 className="page-title">Formulario de Subconcepto</h1>
            <Formik
                initialValues={formValues}
                validationSchema={subConceptoEsquema}
                onSubmit={handleGuardar}
                enableReinitialize
            >
                {({ isSubmitting, resetForm }) => (
                    <Form className="formulario max-w-4xl mx-auto">
                        <div className="form-grid grid-cols-1 sm:grid-cols-2 gap-4">
                            <div className="col-span-full mb-4">
                                <label htmlFor="idBusqueda" className="auth-label">
                                    ID de Subconcepto:
                                </label>
                                <div className="flex gap-2">
                                    <input
                                        type="number"
                                        id="idBusqueda"
                                        value={idBusqueda}
                                        onChange={(e) => setIdBusqueda(e.target.value)}
                                        className="form-input flex-grow"
                                    />
                                    <Boton onClick={handleBuscar} type="button" className="page-button">
                                        Buscar
                                    </Boton>
                                </div>
                            </div>
                            <div className="mb-4">
                                <label htmlFor="descripcion" className="auth-label">
                                    Descripcion:
                                </label>
                                <Field name="descripcion" type="text" className="form-input" />
                                <ErrorMessage name="descripcion" component="div" className="auth-error" />
                            </div>
                        </div>
                        <div className="form-acciones">
                            <Boton type="submit" disabled={isSubmitting} className="page-button">
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
                            <Boton type="button" onClick={() => navigate("/subconceptos")} className="page-button-secondary">
                                Volver al Listado
                            </Boton>
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
                    </Form>
                )}
            </Formik>
        </div>
    );
};

export default SubConceptosFormulario;
