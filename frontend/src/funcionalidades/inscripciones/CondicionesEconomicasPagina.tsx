import { type FormEvent, useCallback, useEffect, useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { toast } from "react-toastify";
import bonificacionesApi from "../../api/bonificacionesApi";
import condicionesApi, { type CondicionEconomica } from "../../api/condicionesEconomicasApi";
import Boton from "../../componentes/comunes/Boton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "../../componentes/ui/table";
import type { BonificacionResponse } from "../../types/types";

const CondicionesEconomicasPagina = () => {
  const inscripcionId = Number(useParams().id);
  const navigate = useNavigate();
  const [condiciones, setCondiciones] = useState<CondicionEconomica[]>([]);
  const [bonificaciones, setBonificaciones] = useState<BonificacionResponse[]>([]);
  const [vigenteDesde, setVigenteDesde] = useState("");
  const [costoParticular, setCostoParticular] = useState("");
  const [bonificacionId, setBonificacionId] = useState("");
  const [motivo, setMotivo] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);

  const cargar = useCallback(async () => {
    try {
      const [history, discounts] = await Promise.all([
        condicionesApi.listar(inscripcionId),
        bonificacionesApi.listarBonificaciones(),
      ]);
      setCondiciones(history);
      setBonificaciones(discounts.filter((value) => value.activo));
    } catch {
      toast.error("No se pudieron cargar las condiciones económicas.");
    } finally {
      setLoading(false);
    }
  }, [inscripcionId]);

  useEffect(() => { void cargar(); }, [cargar]);

  const submit = async (event: FormEvent) => {
    event.preventDefault();
    setSaving(true);
    try {
      await condicionesApi.crear(inscripcionId, {
        vigenteDesde,
        costoParticular: costoParticular.trim() === "" ? null : costoParticular,
        bonificacionId: bonificacionId === "" ? null : Number(bonificacionId),
        motivo,
      });
      toast.success("Condición económica creada correctamente.");
      setVigenteDesde(""); setCostoParticular(""); setBonificacionId(""); setMotivo("");
      await cargar();
    } catch {
      toast.error("No se pudo crear la condición. Verifique fecha, datos y permisos.");
    } finally {
      setSaving(false);
    }
  };

  if (loading) return <div className="text-center py-4">Cargando...</div>;
  return <div className="page-container space-y-6">
    <div className="flex items-center justify-between"><div><h1 className="page-title">Condiciones económicas</h1><p className="text-muted-foreground">Inscripción #{inscripcionId}. La bonificación queda copiada como snapshot.</p></div><Boton onClick={() => navigate("/inscripciones")} className="page-button-secondary">Volver</Boton></div>
    <form onSubmit={submit} className="formulario max-w-4xl mx-auto">
      <div className="form-grid grid-cols-1 sm:grid-cols-2 gap-4">
        <label className="auth-label">Vigente desde<input className="form-input" type="date" required value={vigenteDesde} onChange={(event) => setVigenteDesde(event.target.value)} /></label>
        <label className="auth-label">Costo particular opcional<input className="form-input" type="text" inputMode="decimal" value={costoParticular} onChange={(event) => setCostoParticular(event.target.value)} /></label>
        <label className="auth-label">Bonificación<select className="form-input" value={bonificacionId} onChange={(event) => setBonificacionId(event.target.value)}><option value="">Sin bonificación</option>{bonificaciones.map((value) => <option key={value.id} value={value.id}>{value.descripcion}</option>)}</select></label>
        <label className="auth-label">Motivo<input className="form-input" required value={motivo} onChange={(event) => setMotivo(event.target.value)} /></label>
      </div>
      <div className="form-acciones"><Boton type="submit" disabled={saving} className="page-button">{saving ? "Guardando..." : "Crear condición"}</Boton></div>
    </form>
    <div className="rounded-lg border bg-card shadow-sm"><Table><TableHeader><TableRow><TableHead>Vigencia</TableHead><TableHead>Costo particular</TableHead><TableHead>Bonificación</TableHead><TableHead>Porcentaje</TableHead><TableHead>Valor fijo</TableHead><TableHead>Motivo</TableHead><TableHead>Creador</TableHead><TableHead>Uso</TableHead></TableRow></TableHeader><TableBody>{condiciones.map((value) => <TableRow key={value.id}><TableCell>{value.vigenteDesde}</TableCell><TableCell>{value.costoParticular ?? "Tarifa de disciplina"}</TableCell><TableCell>{value.bonificacionDescripcion ?? "Sin bonificación"}</TableCell><TableCell>{value.bonificacionPorcentaje}</TableCell><TableCell>{value.bonificacionValorFijo}</TableCell><TableCell>{value.motivo}</TableCell><TableCell>{value.creadaPorUsername}</TableCell><TableCell>{value.utilizada ? "Utilizada" : "Sin liquidaciones"}</TableCell></TableRow>)}</TableBody></Table>{condiciones.length === 0 && <p className="p-6 text-center text-muted-foreground">No hay condiciones verificadas cargadas.</p>}</div>
  </div>;
};

export default CondicionesEconomicasPagina;
