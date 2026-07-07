import { type FormEvent, useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { toast } from "react-toastify";
import alumnosApi from "../../api/alumnosApi";
import Boton from "../../componentes/comunes/Boton";
import type { AlumnoRegistro } from "../../types/types";
import PageHeader from "../../componentes/comunes/PageHeader";
import SectionCard from "../../componentes/comunes/SectionCard";

const emptyAlumno: AlumnoRegistro = {
  nombre: "",
  apellido: "",
  fechaNacimiento: "",
  fechaIncorporacion: "",
  celular1: "",
  celular2: "",
  email: "",
  documento: "",
  fechaDeBaja: null,
  nombrePadres: "",
  autorizadoParaSalirSolo: false,
  activo: true,
  otrasNotas: "",
};

const AlumnosFormulario = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const alumnoId = Number(searchParams.get("id")) || null;
  const [values, setValues] = useState<AlumnoRegistro>(emptyAlumno);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    if (!alumnoId) return;
    alumnosApi
      .obtenerPorId(alumnoId)
      .then((alumno) =>
        setValues({
          id: alumno.id,
          nombre: alumno.nombre,
          apellido: alumno.apellido,
          fechaNacimiento: alumno.fechaNacimiento ?? "",
          fechaIncorporacion: alumno.fechaIncorporacion ?? "",
          celular1: alumno.celular1 ?? "",
          celular2: alumno.celular2 ?? "",
          email: alumno.email ?? "",
          documento: alumno.documento ?? "",
          fechaDeBaja: alumno.fechaDeBaja,
          nombrePadres: alumno.nombrePadres ?? "",
          autorizadoParaSalirSolo: alumno.autorizadoParaSalirSolo,
          activo: alumno.activo,
          otrasNotas: alumno.otrasNotas ?? "",
        })
      )
      .catch(() => toast.error("No se pudo cargar el alumno."));
  }, [alumnoId]);

  const change = (field: keyof AlumnoRegistro, value: string | boolean) =>
    setValues((current) => ({ ...current, [field]: value }));

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setSaving(true);
    try {
      if (alumnoId) await alumnosApi.actualizar(alumnoId, values);
      else await alumnosApi.registrar(values);
      toast.success("Alumno guardado correctamente.");
      navigate("/alumnos");
    } catch {
      toast.error("No se pudo guardar el alumno.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="page-container">
      <PageHeader eyebrow="Alumnos" title={alumnoId ? "Editar alumno" : "Nuevo alumno"} description="Completá la información personal y de contacto. Las inscripciones se gestionan por separado." />
      <form onSubmit={submit} className="mx-auto max-w-5xl space-y-5">
        <SectionCard title="Datos personales" description="Información principal para identificar al alumno.">
        <div className="form-grid">
          <TextField label="Nombre" value={values.nombre} onChange={(value) => change("nombre", value)} required />
          <TextField label="Apellido" value={values.apellido} onChange={(value) => change("apellido", value)} required />
          <TextField label="Fecha de nacimiento" type="date" value={values.fechaNacimiento} onChange={(value) => change("fechaNacimiento", value)} />
          <TextField label="Fecha de incorporación" type="date" value={values.fechaIncorporacion} onChange={(value) => change("fechaIncorporacion", value)} />
          <TextField label="Documento" value={values.documento ?? ""} onChange={(value) => change("documento", value)} />
        </div>
        </SectionCard>
        <SectionCard title="Contacto y autorizaciones" description="Datos para comunicación y operación diaria.">
        <div className="form-grid">
          <TextField label="Email" type="email" value={values.email ?? ""} onChange={(value) => change("email", value)} />
          <TextField label="Celular principal" value={values.celular1 ?? ""} onChange={(value) => change("celular1", value)} />
          <TextField label="Celular alternativo" value={values.celular2 ?? ""} onChange={(value) => change("celular2", value)} />
          <TextField label="Padres o responsables" value={values.nombrePadres ?? ""} onChange={(value) => change("nombrePadres", value)} />
          <label className="checkbox-field self-end">
            <input type="checkbox" checked={values.autorizadoParaSalirSolo ?? false} onChange={(event) => change("autorizadoParaSalirSolo", event.target.checked)} />
            <span><strong className="block">Autorizado para salir solo</strong><span className="mt-1 block text-xs font-normal text-muted-foreground">Permite registrar esta autorización en el perfil.</span></span>
          </label>
          {alumnoId && (
            <label className="checkbox-field self-end">
              <input type="checkbox" checked={values.activo} onChange={(event) => change("activo", event.target.checked)} />
              <span><strong className="block">Alumno activo</strong><span className="mt-1 block text-xs font-normal text-muted-foreground">Define su disponibilidad en los listados operativos.</span></span>
            </label>
          )}
          <label className="auth-label sm:col-span-2">
            Otras notas
            <textarea className="form-input" value={values.otrasNotas ?? ""} onChange={(event) => change("otrasNotas", event.target.value)} />
          </label>
        </div>
        </SectionCard>
        <div className="form-acciones">
          <Boton type="button" onClick={() => navigate("/alumnos")} className="page-button-secondary">Cancelar</Boton>
          <Boton type="submit" disabled={saving} className="page-button">{saving ? "Guardando..." : "Guardar alumno"}</Boton>
        </div>
      </form>
    </div>
  );
};

const TextField = ({ label, value, onChange, type = "text", required = false }: {
  label: string;
  value: string;
  onChange: (value: string) => void;
  type?: string;
  required?: boolean;
}) => (
  <label className="auth-label">
    {label}
    <input className="form-input" type={type} value={value} required={required} onChange={(event) => onChange(event.target.value)} />
  </label>
);

export default AlumnosFormulario;
