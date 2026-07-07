import { useMemo } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Form, Formik, type FormikHelpers } from "formik";
import { useNavigate, useSearchParams } from "react-router-dom";
import { toast } from "react-toastify";
import { getApiErrorMessage, getFieldErrors } from "../../api/apiError";
import bonificacionesApi from "../../api/bonificacionesApi";
import disciplinasApi from "../../api/disciplinasApi";
import inscripcionesApi from "../../api/inscripcionesApi";
import Boton from "../../componentes/comunes/Boton";
import ErrorState from "../../componentes/comunes/ErrorState";
import FormField from "../../componentes/comunes/FormField";
import LoadingState from "../../componentes/comunes/LoadingState";
import MoneyInput from "../../componentes/comunes/MoneyInput";
import { queryKeys } from "../../hooks/queryKeys";
import type { InscripcionRegistroRequest } from "../../types/types";
import { normalizeMoneyInput } from "../../utils/money";
import { inscripcionEsquema } from "../../validaciones/inscripcionEsquema";
import PageHeader from "../../componentes/comunes/PageHeader";
import SectionCard from "../../componentes/comunes/SectionCard";

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

const InscripcionesFormulario = () => {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [searchParams] = useSearchParams();
  const id = positiveId(searchParams.get("id"));
  const presetAlumnoId = positiveId(searchParams.get("alumnoId"));
  const disciplinas = useQuery({ queryKey: queryKeys.disciplinas, queryFn: disciplinasApi.listarDisciplinas });
  const bonificaciones = useQuery({ queryKey: queryKeys.bonificaciones, queryFn: bonificacionesApi.listarBonificaciones });
  const detalle = useQuery({ queryKey: queryKeys.inscripcion(id), queryFn: () => inscripcionesApi.obtenerPorId(id), enabled: id > 0 });
  const initialValues = useMemo<InscripcionRegistroRequest>(() => detalle.data ? {
    id: detalle.data.id,
    alumnoId: detalle.data.alumnoId,
    disciplinaId: detalle.data.disciplinaId,
    bonificacionId: detalle.data.bonificacionId ?? null,
    fechaInscripcion: detalle.data.fechaInscripcion,
    costoParticular: detalle.data.costoParticular ?? "",
  } : { ...emptyRequest, alumnoId: presetAlumnoId }, [detalle.data, presetAlumnoId]);

  const submit = async (values: InscripcionRegistroRequest, helpers: FormikHelpers<InscripcionRegistroRequest>) => {
    const costo = values.costoParticular?.trim();
    const request = { ...values, costoParticular: costo ? normalizeMoneyInput(costo) ?? costo : undefined };
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

  if (detalle.isLoading || disciplinas.isLoading || bonificaciones.isLoading) return <LoadingState message="Cargando formulario..." />;
  if (detalle.isError || disciplinas.isError || bonificaciones.isError) return <ErrorState message="No se pudieron cargar los datos del formulario." />;

  return (
    <div className="page-container">
      <PageHeader eyebrow="Inscripciones" title={id ? "Editar inscripción" : "Nueva inscripción"} description="Relacioná alumno y disciplina. El backend conserva la autoridad sobre cargos y saldos." />
      <Formik initialValues={initialValues} validationSchema={inscripcionEsquema} enableReinitialize onSubmit={submit}>
        {({ values, errors, isSubmitting, setFieldValue }) => (
          <Form className="mx-auto max-w-5xl space-y-5" noValidate>
            <SectionCard title="Datos de inscripción" description="Seleccioná las referencias y la fecha de alta.">
            <div className="form-grid">
              <FormField id="alumnoId" name="alumnoId" label="Alumno ID" type="number" min="1" required value={values.alumnoId || ""} error={errors.alumnoId} onChange={(event) => void setFieldValue("alumnoId", Number(event.target.value))} />
              <label className="auth-label" htmlFor="disciplinaId">Disciplina
                <select id="disciplinaId" name="disciplinaId" className="form-input" required value={values.disciplinaId} aria-invalid={Boolean(errors.disciplinaId)} onChange={(event) => void setFieldValue("disciplinaId", Number(event.target.value))}>
                  <option value={0}>Seleccione una disciplina</option>
                  {(disciplinas.data ?? []).filter((item) => item.activo).map((disciplina) => <option key={disciplina.id} value={disciplina.id}>{disciplina.nombre}</option>)}
                </select>
                {errors.disciplinaId && <span className="auth-error">{errors.disciplinaId}</span>}
              </label>
              <label className="auth-label" htmlFor="bonificacionId">Bonificación opcional
                <select id="bonificacionId" name="bonificacionId" className="form-input" value={values.bonificacionId ?? ""} onChange={(event) => void setFieldValue("bonificacionId", event.target.value ? Number(event.target.value) : null)}>
                  <option value="">Sin bonificación</option>
                  {(bonificaciones.data ?? []).filter((item) => item.activo).map((bonificacion) => <option key={bonificacion.id} value={bonificacion.id}>{bonificacion.descripcion}</option>)}
                </select>
              </label>
              <FormField id="fechaInscripcion" name="fechaInscripcion" label="Fecha de inscripción" type="date" required value={values.fechaInscripcion} error={errors.fechaInscripcion} onChange={(event) => void setFieldValue("fechaInscripcion", event.target.value)} />
              <MoneyInput id="costoParticular" label="Costo particular opcional" value={values.costoParticular ?? ""} error={errors.costoParticular} onChange={(value) => void setFieldValue("costoParticular", value)} />
            </div>
            <p className="mt-4 rounded-lg bg-muted/50 p-3 text-sm text-muted-foreground">El costo particular es opcional. Los cargos y saldos finales se calculan en el backend.</p>
            </SectionCard>
            <div className="form-acciones">
              <Boton type="button" onClick={() => navigate("/inscripciones")} className="page-button-secondary">Cancelar</Boton>
              <Boton type="submit" disabled={isSubmitting} className="page-button">{isSubmitting ? "Guardando..." : "Guardar inscripción"}</Boton>
            </div>
          </Form>
        )}
      </Formik>
    </div>
  );
};

export default InscripcionesFormulario;
