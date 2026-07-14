import { type FormEvent, useCallback, useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { toast } from "react-toastify";
import disciplinasApi from "../../api/disciplinasApi";
import tarifasApi, { type CrearTarifaDisciplina, type TarifaDisciplina } from "../../api/tarifasApi";
import Boton from "../../componentes/comunes/Boton";
import PermissionGate from "../../componentes/comunes/PermissionGate";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../../componentes/ui/table";
import { APP_TIME_ZONE } from "../../config/environment";
import { PERMISSIONS } from "../../config/permissions";
import { useAuth } from "../../hooks/context/useAuth";
import { canUseTariffEffectiveDate, currentDateInTimeZone } from "./tariffEffectiveDate";

const empty: CrearTarifaDisciplina = {
  vigenteDesde: "",
  valorCuota: "",
  matricula: "0.00",
  claseSuelta: "0.00",
  clasePrueba: "0.00",
  motivo: "",
};

const TarifasDisciplinaPagina = () => {
  const disciplinaId = Number(useParams().id);
  const navigate = useNavigate();
  const { hasPermission } = useAuth();
  const canCreateHistorical = hasPermission(PERMISSIONS.APP_ACCESS)
    && hasPermission(PERMISSIONS.TARIFAS_HISTORICAS);
  const today = currentDateInTimeZone(APP_TIME_ZONE);
  const [nombre, setNombre] = useState("");
  const [tarifas, setTarifas] = useState<TarifaDisciplina[]>([]);
  const [values, setValues] = useState<CrearTarifaDisciplina>(empty);
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const cargar = useCallback(async () => {
    if (!Number.isInteger(disciplinaId) || disciplinaId <= 0) return;
    try {
      const [disciplina, history] = await Promise.all([
        disciplinasApi.obtenerDisciplinaPorId(disciplinaId),
        tarifasApi.listar(disciplinaId),
      ]);
      setNombre(disciplina.nombre);
      setTarifas(history);
    } catch {
      toast.error("No se pudo cargar el historial de tarifas.");
    } finally {
      setLoading(false);
    }
  }, [disciplinaId]);

  useEffect(() => { void cargar(); }, [cargar]);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    if (!canUseTariffEffectiveDate(values.vigenteDesde, today, canCreateHistorical)) {
      toast.error("Se requiere permiso para cargar una tarifa con vigencia histórica.");
      return;
    }
    setSaving(true);
    try {
      await tarifasApi.crear(disciplinaId, values);
      toast.success("Tarifa creada correctamente.");
      setValues(empty);
      await cargar();
    } catch {
      toast.error("No se pudo crear la tarifa. Verifique fecha, importes y permisos.");
    } finally {
      setSaving(false);
    }
  };

  if (loading) return <div className="text-center py-4">Cargando...</div>;

  return (
    <div className="page-container space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div><h1 className="page-title">Tarifas de {nombre}</h1><p className="text-muted-foreground">Cada fila entra en vigencia en su fecha y conserva autor y motivo.</p></div>
        <Boton type="button" onClick={() => navigate("/disciplinas")} className="page-button-secondary">Volver</Boton>
      </div>

      <PermissionGate permission={PERMISSIONS.TARIFAS_ADMIN}>
        <form onSubmit={submit} className="formulario max-w-5xl mx-auto">
          <h2 className="text-lg font-semibold">Programar tarifa</h2>
          <div className="form-grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <Field label="Vigente desde" type="date" min={canCreateHistorical ? undefined : today} value={values.vigenteDesde} onChange={(value) => setValues({ ...values, vigenteDesde: value })} />
            <Field label="Cuota" value={values.valorCuota} onChange={(value) => setValues({ ...values, valorCuota: value })} />
            <Field label="Matrícula" value={values.matricula} onChange={(value) => setValues({ ...values, matricula: value })} />
            <Field label="Clase suelta" value={values.claseSuelta} onChange={(value) => setValues({ ...values, claseSuelta: value })} />
            <Field label="Clase de prueba" value={values.clasePrueba} onChange={(value) => setValues({ ...values, clasePrueba: value })} />
            <Field label="Motivo" value={values.motivo} onChange={(value) => setValues({ ...values, motivo: value })} />
          </div>
          <div className="form-acciones"><Boton type="submit" disabled={saving} className="page-button">{saving ? "Guardando..." : "Crear tarifa"}</Boton></div>
        </form>
      </PermissionGate>

      <div className="rounded-lg border bg-card shadow-sm">
        <Table>
          <TableHeader><TableRow><TableHead>Vigencia</TableHead><TableHead>Cuota</TableHead><TableHead>Matrícula</TableHead><TableHead>Clase suelta</TableHead><TableHead>Clase prueba</TableHead><TableHead>Motivo</TableHead><TableHead>Creador</TableHead><TableHead>Creación</TableHead><TableHead>Uso</TableHead></TableRow></TableHeader>
          <TableBody>{tarifas.map((tarifa) => <TableRow key={tarifa.id}><TableCell>{tarifa.vigenteDesde}</TableCell><TableCell>{tarifa.valorCuota}</TableCell><TableCell>{tarifa.matricula}</TableCell><TableCell>{tarifa.claseSuelta}</TableCell><TableCell>{tarifa.clasePrueba}</TableCell><TableCell>{tarifa.motivo}</TableCell><TableCell>{tarifa.creadaPorUsername}</TableCell><TableCell>{new Date(tarifa.createdAt).toLocaleString()}</TableCell><TableCell>{tarifa.utilizada ? "Utilizada" : "Sin liquidaciones"}</TableCell></TableRow>)}</TableBody>
        </Table>
        {tarifas.length === 0 && <p className="p-6 text-center text-muted-foreground">No hay tarifas verificadas cargadas.</p>}
      </div>
    </div>
  );
};

const Field = ({ label, value, onChange, type = "text", min }: { label: string; value: string; onChange: (value: string) => void; type?: "text" | "date"; min?: string }) => (
  <label className="auth-label">{label}<input className="form-input" type={type} inputMode={type === "text" && label !== "Motivo" ? "decimal" : undefined} min={min ?? (type === "text" && label !== "Motivo" ? "0" : undefined)} step={type === "text" && label !== "Motivo" ? "0.01" : undefined} required value={value} onChange={(event) => onChange(event.target.value)} /></label>
);

export default TarifasDisciplinaPagina;
