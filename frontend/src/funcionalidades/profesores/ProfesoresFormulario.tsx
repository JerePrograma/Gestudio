import type React from "react"
import { useState, useEffect, useCallback } from "react"
import { useNavigate, useSearchParams } from "react-router-dom"
import { Formik, Form, Field, ErrorMessage } from "formik"
import { profesorEsquema } from "../../validaciones/profesorEsquema"
import profesoresApi from "../../api/profesoresApi"
import Boton from "../../componentes/comunes/Boton"
import { toast } from "react-toastify"
import { Search } from "lucide-react"
import type { ProfesorRegistroRequest, ProfesorModificacionRequest, ProfesorDetalleResponse } from "../../types/types"
import { format, parse } from "date-fns"

const initialProfesorValues: ProfesorRegistroRequest & Partial<ProfesorModificacionRequest> = {
  nombre: "",
  apellido: "",
  fechaNacimiento: "",
  telefono: "",
  activo: true,
}

const ProfesoresFormulario: React.FC = () => {
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const [profesorId, setProfesorId] = useState<number | null>(null)
  const [formValues, setFormValues] = useState<ProfesorRegistroRequest & Partial<ProfesorModificacionRequest>>(
    initialProfesorValues,
  )
  const [mensaje, setMensaje] = useState("")
  const [idBusqueda, setIdBusqueda] = useState("")

  const resetearFormulario = useCallback(() => {
    setFormValues(initialProfesorValues)
    setProfesorId(null)
    setMensaje("")
    setIdBusqueda("")
  }, [])

  const convertToProfesorFormValues = useCallback(
    (profesor: ProfesorDetalleResponse): ProfesorRegistroRequest & Partial<ProfesorModificacionRequest> => {
      return {
        nombre: profesor.nombre || "",
        apellido: profesor.apellido || "",
        fechaNacimiento: profesor.fechaNacimiento || "",
        telefono: profesor.telefono || "",
        activo: profesor.activo,
      }
    },
    [],
  )

  const handleBuscar = useCallback(async () => {
    if (!idBusqueda) {
      setMensaje("Por favor, ingrese un ID de profesor.")
      return
    }

    try {
      const profesor = await profesoresApi.obtenerProfesorPorId(Number(idBusqueda))
      const convertedProfesor = convertToProfesorFormValues(profesor)
      setFormValues(convertedProfesor)
      setProfesorId(profesor.id)
      setMensaje("Profesor encontrado.")
    } catch {
      toast.error("Error al buscar el profesor:")
      setMensaje("Profesor no encontrado.")
      resetearFormulario()
    }
  }, [idBusqueda, convertToProfesorFormValues, resetearFormulario])

  useEffect(() => {
    const idParam = searchParams.get("id")
    if (idParam) {
      setIdBusqueda(idParam)
      handleBuscar()
    }
  }, [searchParams, handleBuscar])

  const handleGuardar = useCallback(
    async (values: ProfesorRegistroRequest & Partial<ProfesorModificacionRequest>) => {
      const cleanedValues = { ...values }
      if (cleanedValues.fechaNacimiento) {
        const parsedDate = parse(cleanedValues.fechaNacimiento, "yyyy-MM-dd", new Date())
        cleanedValues.fechaNacimiento = format(parsedDate, "yyyy-MM-dd")
      }
      try {
        if (profesorId) {
          await profesoresApi.actualizarProfesor(profesorId, cleanedValues as ProfesorModificacionRequest)
          toast.success("Profesor actualizado correctamente.")
        } else {
          const nuevoProfesor = await profesoresApi.registrarProfesor(cleanedValues as ProfesorRegistroRequest)
          setProfesorId(nuevoProfesor.id)
          toast.success("Profesor creado correctamente.")
        }
        setMensaje("Profesor guardado exitosamente.")
      } catch {
        toast.error("Error al guardar el profesor.")
        setMensaje("Error al guardar el profesor.")
      }
    },
    [profesorId],
  )

  return (
    <div className="page-container">
      <h1 className="page-title">Formulario de Profesor</h1>
      <Formik initialValues={formValues} validationSchema={profesorEsquema} onSubmit={handleGuardar} enableReinitialize>
        {({ isSubmitting, resetForm }) => (
          <Form className="formulario max-w-4xl mx-auto">
            <div className="form-grid grid-cols-1 sm:grid-cols-2 gap-4">
              <div className="col-span-full mb-4">
                <label htmlFor="idBusqueda" className="auth-label">
                  Numero de Profesor:
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
                <ErrorMessage name="nombre" component="div" className="auth-error" />
              </div>

              <div className="mb-4">
                <label htmlFor="apellido" className="auth-label">
                  Apellido:
                </label>
                <Field name="apellido" type="text" className="form-input" />
                <ErrorMessage name="apellido" component="div" className="auth-error" />
              </div>
              <div className="mb-4">
                <label htmlFor="fechaNacimiento" className="auth-label">
                  Fecha de Nacimiento:
                </label>
                <Field name="fechaNacimiento" type="date" className="form-input" />
                <ErrorMessage name="fechaNacimiento" component="div" className="auth-error" />
              </div>

              <div className="mb-4">
                <label htmlFor="telefono" className="auth-label">
                  Telefono:
                </label>
                <Field name="telefono" type="text" className="form-input" />
                <ErrorMessage name="telefono" component="div" className="auth-error" />
              </div>

              {profesorId !== null && (
                <div className="col-span-full mb-4">
                  <label className="flex items-center space-x-2">
                    <Field type="checkbox" name="activo" className="form-checkbox" />
                    <span>Activo</span>
                  </label>
                  <ErrorMessage name="activo" component="div" className="auth-error" />
                </div>
              )}
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
              <Boton type="submit" disabled={isSubmitting} className="page-button">
                Guardar
              </Boton>
              <Boton
                type="button"
                onClick={() => {
                  resetearFormulario()
                  resetForm()
                }}
                className="page-button-secondary"
              >
                Limpiar
              </Boton>
              <Boton type="button" onClick={() => navigate("/profesores")} className="page-button-secondary">
                Volver al Listado
              </Boton>
            </div>
          </Form>
        )}
      </Formik>
    </div>
  )
}

export default ProfesoresFormulario
