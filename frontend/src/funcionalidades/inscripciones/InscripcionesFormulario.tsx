import { useEffect, useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Form, Formik, type FormikHelpers } from "formik";
import { useNavigate, useSearchParams } from "react-router-dom";
import { toast } from "react-toastify";
import alumnosApi from "../../api/alumnosApi";
import { getApiErrorMessage, getFieldErrors } from "../../api/apiError";
import bonificacionesApi from "../../api/bonificacionesApi";
import disciplinasApi from "../../api/disciplinasApi";
import inscripcionesApi from "../../api/inscripcionesApi";
import Boton from "../../componentes/comunes/Boton";
import EmptyState from "../../componentes/comunes/EmptyState";
import ErrorState from "../../componentes/comunes/ErrorState";
import FormField from "../../componentes/comunes/FormField";
import LoadingState from "../../componentes/comunes/LoadingState";
import MoneyInput from "../../componentes/comunes/MoneyInput";
import PageHeader from "../../componentes/comunes/PageHeader";
import SectionCard from "../../componentes/comunes/SectionCard";
import { queryKeys } from "../../hooks/queryKeys";
import type { AlumnoResponse, InscripcionRegistroRequest, Page } from "../../types/types";
import { normalizeMoneyInput } from "../../utils/money";
import { inscripcionEsquema } from "../../validaciones/inscripcionEsquema";

const ALUMNOS_SEARCH_SIZE = 8;
const MIN_ALUMNO_SEARCH_LENGTH = 2;

const positiveId = (value: string | null): number => {
  const id = Number(value);
  return Number.isInteger(id) && id > 0 ? id : 0;
};

const emptyRequest: InscripcionRegistroRequest = {
  alumnoId: 0,
  disciplinaId: 0,
  bonificacionId: null,
  fechaInscripcion: "",
  costoParticular: "",
};

const nombreCompletoAlumno = (alumno: AlumnoResponse): string =>
  [alumno.nombre, alumno.apellido].filter(Boolean).join(" ").trim();

const detalleAlumno = (alumno: AlumnoResponse): string => {
  const partes = [
    alumno.documento ? `DNI ${alumno.documento}` : null,
    alumno.celular1 || null,
    alumno.email || null,
  ].filter(Boolean);

  return partes.length > 0 ? partes.join(" · ") : "Sin datos de contacto cargados";
};

const InscripcionesFormulario = () => {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [searchParams] = useSearchParams();

  const id = positiveId(searchParams.get("id"));
  const presetAlumnoId = positiveId(searchParams.get("alumnoId"));

  const [busquedaAlumno, setBusquedaAlumno] = useState("");
  const [alumnoSeleccionado, setAlumnoSeleccionado] = useState<AlumnoResponse | null>(null);

  const disciplinas = useQuery({
    queryKey: queryKeys.disciplinas,
    queryFn: disciplinasApi.listarDisciplinas,
  });

  const bonificaciones = useQuery({
    queryKey: queryKeys.bonificaciones,
    queryFn: bonificacionesApi.listarBonificaciones,
  });

  const detalle = useQuery({
    queryKey: queryKeys.inscripcion(id),
    queryFn: () => inscripcionesApi.obtenerPorId(id),
    enabled: id > 0,
  });

  const alumnoInicialId = detalle.data?.alumnoId ?? presetAlumnoId;

  const alumnoInicial = useQuery({
    queryKey: queryKeys.alumno(alumnoInicialId),
    queryFn: () => alumnosApi.obtenerPorId(alumnoInicialId),
    enabled: alumnoInicialId > 0,
  });

  useEffect(() => {
    if (!alumnoInicial.data) return;

    setAlumnoSeleccionado(alumnoInicial.data);
    setBusquedaAlumno(nombreCompletoAlumno(alumnoInicial.data));
  }, [alumnoInicial.data]);

  const busquedaAlumnoNormalizada = busquedaAlumno.trim();

  const alumnos = useQuery<Page<AlumnoResponse>>({
    queryKey: queryKeys.alumnosBusqueda(busquedaAlumnoNormalizada, 0, ALUMNOS_SEARCH_SIZE),
    queryFn: () => alumnosApi.buscarPorNombre(busquedaAlumnoNormalizada, 0, ALUMNOS_SEARCH_SIZE),
    enabled: alumnoSeleccionado === null && busquedaAlumnoNormalizada.length >= MIN_ALUMNO_SEARCH_LENGTH,
  });

  const initialValues = useMemo<InscripcionRegistroRequest>(() => detalle.data ? {
    id: detalle.data.id,
    alumnoId: detalle.data.alumnoId,
    disciplinaId: detalle.data.disciplinaId,
    bonificacionId: detalle.data.bonificacionId ?? null,
    fechaInscripcion: detalle.data.fechaInscripcion,
    costoParticular: detalle.data.costoParticular ?? "",
  } : {
    ...emptyRequest,
    alumnoId: presetAlumnoId,
  }, [detalle.data, presetAlumnoId]);

  const submit = async (
    values: InscripcionRegistroRequest,
    helpers: FormikHelpers<InscripcionRegistroRequest>,
  ) => {
    const costo = values.costoParticular?.trim();

    const request = {
      ...values,
      costoParticular: costo ? normalizeMoneyInput(costo) ?? costo : undefined,
    };

    try {
      if (id) await inscripcionesApi.actualizar(id, request);
      else await inscripcionesApi.crear(request);

      await queryClient.invalidateQueries({ queryKey: queryKeys.all.inscripciones });
      toast.success("Inscripción guardada correctamente.");
      navigate("/inscripciones");
    } catch (error) {
      helpers.setErrors(getFieldErrors(error));
      toast.error(getApiErrorMessage(error, "No se pudo guardar la inscripción."));
    } finally {
      helpers.setSubmitting(false);
    }
  };

  if (detalle.isLoading || disciplinas.isLoading || bonificaciones.isLoading) {
    return <LoadingState message="Cargando formulario..." />;
  }

  if (detalle.isError || disciplinas.isError || bonificaciones.isError) {
    return <ErrorState message="No se pudieron cargar los datos del formulario." />;
  }

  return (
    <div className="page-container">
      <PageHeader
        eyebrow="Inscripciones"
        title={id ? "Editar inscripción" : "Nueva inscripción"}
        description="Relacioná alumno y disciplina. El backend conserva la autoridad sobre cargos y saldos."
      />

      <Formik
        initialValues={initialValues}
        validationSchema={inscripcionEsquema}
        enableReinitialize
        onSubmit={submit}
      >
        {({ values, errors, isSubmitting, setFieldValue }) => (
          <Form className="mx-auto max-w-5xl space-y-5" noValidate>
            <SectionCard title="Datos de inscripción" description="Seleccioná alumno, disciplina y fecha de alta.">
              <div className="form-grid">
                <div className="field-group">
                  <label htmlFor="inscripcion-alumno">Alumno</label>

                  <div className="flex flex-col gap-2 sm:flex-row">
                    <input
                      id="inscripcion-alumno"
                      type="search"
                      autoComplete="off"
                      className="form-input"
                      value={busquedaAlumno}
                      placeholder="Buscar por nombre o apellido"
                      onChange={(event) => {
                        setAlumnoSeleccionado(null);
                        setBusquedaAlumno(event.target.value);
                        void setFieldValue("alumnoId", 0);
                      }}
                    />

                    {alumnoSeleccionado && (
                      <Boton
                        type="button"
                        className="page-button-secondary shrink-0"
                        onClick={() => {
                          setAlumnoSeleccionado(null);
                          setBusquedaAlumno("");
                          void setFieldValue("alumnoId", 0);
                        }}
                      >
                        Cambiar
                      </Boton>
                    )}
                  </div>

                  <span className="form-help">
                    Buscá el alumno por nombre o apellido. El ID queda sólo para uso interno del sistema.
                  </span>

                  {errors.alumnoId && <span className="auth-error">{errors.alumnoId}</span>}

                  {alumnoInicial.isLoading && alumnoInicialId > 0 && !alumnoSeleccionado && (
                    <p className="text-xs text-muted-foreground">Cargando alumno...</p>
                  )}

                  {!alumnoSeleccionado && busquedaAlumnoNormalizada.length > 0 && busquedaAlumnoNormalizada.length < MIN_ALUMNO_SEARCH_LENGTH && (
                    <p className="text-xs text-muted-foreground">
                      Escribí al menos {MIN_ALUMNO_SEARCH_LENGTH} caracteres para buscar.
                    </p>
                  )}

                  {!alumnoSeleccionado && alumnos.isLoading && (
                    <LoadingState message="Buscando alumnos..." />
                  )}

                  {!alumnoSeleccionado && alumnos.isError && (
                    <ErrorState message="No se pudieron buscar alumnos." onRetry={() => void alumnos.refetch()} />
                  )}

                  {!alumnoSeleccionado && alumnos.data?.content.length === 0 && (
                    <EmptyState title="Sin resultados" message="No se encontraron alumnos con esa búsqueda." />
                  )}

                  {!alumnoSeleccionado && alumnos.data && alumnos.data.content.length > 0 && (
                    <div className="mt-3 space-y-2">
                      {alumnos.data.content.map((alumno) => (
                        <button
                          key={alumno.id}
                          type="button"
                          disabled={!alumno.activo}
                          aria-label={`Seleccionar ${nombreCompletoAlumno(alumno)}`}
                          onClick={() => {
                            setAlumnoSeleccionado(alumno);
                            setBusquedaAlumno(nombreCompletoAlumno(alumno));
                            void setFieldValue("alumnoId", alumno.id);
                          }}
                          className="w-full rounded-xl border border-border bg-card p-3 text-left transition hover:border-primary hover:bg-muted/50 disabled:cursor-not-allowed disabled:opacity-60"
                        >
                          <span className="flex flex-wrap items-center justify-between gap-2">
                            <span className="font-semibold">{nombreCompletoAlumno(alumno)}</span>
                            <span className="rounded-full bg-muted px-2 py-0.5 text-xs text-muted-foreground">
                              {alumno.activo ? "Activo" : "Baja"}
                            </span>
                          </span>
                          <span className="mt-1 block text-xs text-muted-foreground">
                            {detalleAlumno(alumno)}
                          </span>
                        </button>
                      ))}
                    </div>
                  )}

                  {alumnoSeleccionado && (
                    <div className="mt-3 rounded-xl border border-border bg-muted/35 p-3">
                      <p className="text-sm font-semibold">{nombreCompletoAlumno(alumnoSeleccionado)}</p>
                      <p className="mt-1 text-xs text-muted-foreground">{detalleAlumno(alumnoSeleccionado)}</p>
                    </div>
                  )}
                </div>

                <label className="auth-label" htmlFor="disciplinaId">
                  Disciplina
                  <select
                    id="disciplinaId"
                    name="disciplinaId"
                    className="form-input"
                    required
                    value={values.disciplinaId}
                    aria-invalid={Boolean(errors.disciplinaId)}
                    onChange={(event) => void setFieldValue("disciplinaId", Number(event.target.value))}
                  >
                    <option value={0}>Seleccione una disciplina</option>
                    {(disciplinas.data ?? [])
                      .filter((item) => item.activo)
                      .map((disciplina) => (
                        <option key={disciplina.id} value={disciplina.id}>
                          {disciplina.nombre}
                        </option>
                      ))}
                  </select>
                  {errors.disciplinaId && <span className="auth-error">{errors.disciplinaId}</span>}
                </label>

                <label className="auth-label" htmlFor="bonificacionId">
                  Bonificación opcional
                  <select
                    id="bonificacionId"
                    name="bonificacionId"
                    className="form-input"
                    value={values.bonificacionId ?? ""}
                    onChange={(event) => void setFieldValue("bonificacionId", event.target.value ? Number(event.target.value) : null)}
                  >
                    <option value="">Sin bonificación</option>
                    {(bonificaciones.data ?? [])
                      .filter((item) => item.activo)
                      .map((bonificacion) => (
                        <option key={bonificacion.id} value={bonificacion.id}>
                          {bonificacion.descripcion}
                        </option>
                      ))}
                  </select>
                </label>

                <FormField
                  id="fechaInscripcion"
                  name="fechaInscripcion"
                  label="Fecha de inscripción"
                  type="date"
                  required
                  value={values.fechaInscripcion}
                  error={errors.fechaInscripcion}
                  onChange={(event) => void setFieldValue("fechaInscripcion", event.target.value)}
                />

                <MoneyInput
                  id="costoParticular"
                  label="Costo particular opcional"
                  value={values.costoParticular ?? ""}
                  error={errors.costoParticular}
                  onChange={(value) => void setFieldValue("costoParticular", value)}
                />
              </div>

              <p className="mt-4 rounded-lg bg-muted/50 p-3 text-sm text-muted-foreground">
                El costo particular es opcional. Los cargos y saldos finales se calculan en el backend.
              </p>
            </SectionCard>

            <div className="form-acciones">
              <Boton type="button" onClick={() => navigate("/inscripciones")} className="page-button-secondary">
                Cancelar
              </Boton>
              <Boton type="submit" disabled={isSubmitting} className="page-button">
                {isSubmitting ? "Guardando..." : "Guardar inscripción"}
              </Boton>
            </div>
          </Form>
        )}
      </Formik>
    </div>
  );
};

export default InscripcionesFormulario;