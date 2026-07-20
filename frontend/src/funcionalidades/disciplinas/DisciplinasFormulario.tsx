import { type FormEvent, useEffect, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { toast } from "react-toastify";
import disciplinasApi from "../../api/disciplinasApi";
import profesoresApi from "../../api/profesoresApi";
import salonesApi from "../../api/salonesApi";
import Boton from "../../componentes/comunes/Boton";
import {
  DiaSemana,
  type DisciplinaHorarioRequest,
  type DisciplinaRegistroRequest,
  type ProfesorListadoResponse,
  type SalonResponse,
} from "../../types/types";

type FormValues = DisciplinaRegistroRequest & { activo: boolean };

const emptyValues: FormValues = {
  nombre: "",
  salonId: 0,
  profesorId: 0,
  valorCuota: "0",
  matricula: "0",
  claseSuelta: "0",
  clasePrueba: "0",
  activo: true,
  horarios: [],
};

const emptyHorario = (): DisciplinaHorarioRequest => ({
  diaSemana: DiaSemana.LUNES,
  horarioInicio: "18:00",
  duracion: 60,
});

const DisciplinasFormulario = () => {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const id = Number(searchParams.get("id")) || null;
  const [values, setValues] = useState<FormValues>(emptyValues);
  const [salones, setSalones] = useState<SalonResponse[]>([]);
  const [profesores, setProfesores] = useState<ProfesorListadoResponse[]>([]);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    Promise.all([salonesApi.listarSalones(0, 200), profesoresApi.listarProfesoresActivos(true)])
      .then(([salonesPage, profesoresData]) => {
        setSalones(salonesPage.content);
        setProfesores(profesoresData);
      })
      .catch(() => toast.error("No se pudieron cargar salones y profesores."));
  }, []);

  useEffect(() => {
    if (!id) return;
    disciplinasApi
      .obtenerDisciplinaPorId(id)
      .then((disciplina) =>
        setValues({
          id: disciplina.id,
          nombre: disciplina.nombre,
          salonId: disciplina.salonId,
          profesorId: disciplina.profesorId ?? 0,
          valorCuota: disciplina.valorCuota,
          matricula: disciplina.matricula,
          claseSuelta: disciplina.claseSuelta ?? "0",
          clasePrueba: disciplina.clasePrueba ?? "0",
          activo: disciplina.activo,
          horarios: disciplina.horarios.map((horario) => ({
            id: horario.id,
            diaSemana: horario.diaSemana,
            horarioInicio: horario.horarioInicio,
            duracion: horario.duracion,
          })),
        })
      )
      .catch(() => toast.error("No se pudo cargar la disciplina."));
  }, [id]);

  const updateHorario = (index: number, patch: Partial<DisciplinaHorarioRequest>) =>
    setValues((current) => ({
      ...current,
      horarios: current.horarios.map((horario, currentIndex) =>
        currentIndex === index ? { ...horario, ...patch } : horario
      ),
    }));

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setSaving(true);
    try {
      if (id) {
        await disciplinasApi.actualizarDisciplina(id, {
          nombre: values.nombre,
          salonId: values.salonId,
          profesorId: values.profesorId,
          valorCuota: values.valorCuota,
          matricula: values.matricula,
          claseSuelta: values.claseSuelta,
          clasePrueba: values.clasePrueba,
          activo: values.activo,
          horarios: values.horarios,
        });
        toast.success("Disciplina guardada correctamente.");
        navigate("/disciplinas");
      } else {
        const creada = await disciplinasApi.registrarDisciplina(values);
        toast.success("Disciplina creada. Cargá ahora su tarifa inicial con vigencia.");
        navigate(`/disciplinas/${creada.id}/tarifas`);
      }
    } catch {
      toast.error("No se pudo guardar la disciplina.");
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="page-container">
      <h1 className="page-title">{id ? "Editar disciplina" : "Nueva disciplina"}</h1>
      <form onSubmit={submit} className="formulario max-w-5xl mx-auto">
        <div className="form-grid grid-cols-1 sm:grid-cols-2 gap-4">
          <TextField label="Nombre" value={values.nombre} onChange={(value) => setValues({ ...values, nombre: value })} required />
          <label className="auth-label">Salón<select className="form-input" required value={values.salonId} onChange={(event) => setValues({ ...values, salonId: Number(event.target.value) })}><option value={0}>Seleccione</option>{salones.map((salon) => <option key={salon.id} value={salon.id}>{salon.nombre}</option>)}</select></label>
          <label className="auth-label">Profesor<select className="form-input" required value={values.profesorId} onChange={(event) => setValues({ ...values, profesorId: Number(event.target.value) })}><option value={0}>Seleccione</option>{profesores.map((profesor) => <option key={profesor.id} value={profesor.id}>{profesor.apellido}, {profesor.nombre}</option>)}</select></label>
          {id && <label className="auth-label flex items-center gap-2"><input type="checkbox" checked={values.activo} onChange={(event) => setValues({ ...values, activo: event.target.checked })} />Activa</label>}
        </div>

        <p className="mt-4 rounded-lg bg-muted/50 p-3 text-sm text-muted-foreground">
          Los importes no se editan en la disciplina. Cuota, matrícula, clase suelta y clase de prueba se administran en Tarifas con una fecha de vigencia explícita. Cambiar esta ficha no reescribe precios históricos.
        </p>

        <div className="mt-6 space-y-3">
          <div className="flex justify-between items-center"><h2 className="text-lg font-semibold">Horarios</h2><Boton type="button" onClick={() => setValues({ ...values, horarios: [...values.horarios, emptyHorario()] })} className="page-button-secondary">Agregar horario</Boton></div>
          {values.horarios.map((horario, index) => (
            <div className="grid grid-cols-1 sm:grid-cols-4 gap-3" key={horario.id ?? index}>
              <select className="form-input" value={horario.diaSemana} onChange={(event) => updateHorario(index, { diaSemana: event.target.value as DiaSemana })}>{Object.values(DiaSemana).map((dia) => <option key={dia} value={dia}>{dia}</option>)}</select>
              <input className="form-input" type="time" value={horario.horarioInicio} onChange={(event) => updateHorario(index, { horarioInicio: event.target.value })} />
              <input className="form-input" type="number" min="1" value={horario.duracion} onChange={(event) => updateHorario(index, { duracion: Number(event.target.value) })} />
              <Boton type="button" onClick={() => setValues({ ...values, horarios: values.horarios.filter((_, currentIndex) => currentIndex !== index) })} className="page-button-secondary">Quitar</Boton>
            </div>
          ))}
        </div>
        <div className="form-acciones">
          <Boton type="submit" disabled={saving || values.salonId === 0 || values.profesorId === 0} className="page-button">Guardar</Boton>
          <Boton type="button" onClick={() => navigate("/disciplinas")} className="page-button-secondary">Cancelar</Boton>
        </div>
      </form>
    </div>
  );
};

const TextField = ({ label, value, onChange, required = false }: { label: string; value: string; onChange: (value: string) => void; required?: boolean }) => (
  <label className="auth-label">{label}<input className="form-input" type="text" value={value} required={required} onChange={(event) => onChange(event.target.value)} /></label>
);

export default DisciplinasFormulario;
