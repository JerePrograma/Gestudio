"use client";

import { useEffect, useState } from "react";
import { toast } from "react-toastify";
import api from "../api/axiosConfig";
import disciplinasApi from "../api/disciplinasApi";
import profesoresApi from "../api/profesoresApi";
import Boton from "../componentes/comunes/Boton";
import EmptyState from "../componentes/comunes/EmptyState";
import FilterBar from "../componentes/comunes/FilterBar";
import LoadingState from "../componentes/comunes/LoadingState";
import PageHeader from "../componentes/comunes/PageHeader";
import PermissionGate from "../componentes/comunes/PermissionGate";
import Tabla from "../componentes/comunes/Tabla";
import { PERMISSIONS } from "../config/permissions";
import type { DisciplinaListadoResponse, ProfesorListadoResponse } from "../types/types";
import { compareMoney, formatMoney, isMoney, normalizeMoneyInput } from "../utils/money";

interface ReporteMensualidad {
  cargoId: number;
  fechaEmision: string;
  alumno: string;
  disciplina: string;
  profesor: string;
  importeOriginal: string;
  importeCobrado: string;
  saldo: string;
  estado: string;
}

const Reportes = () => {
  const [desde, setDesde] = useState("");
  const [hasta, setHasta] = useState("");
  const [disciplinaId, setDisciplinaId] = useState("");
  const [profesorId, setProfesorId] = useState("");
  const [porcentajeEscuela, setPorcentajeEscuela] = useState("0.00");
  const [disciplinas, setDisciplinas] = useState<DisciplinaListadoResponse[]>([]);
  const [profesores, setProfesores] = useState<ProfesorListadoResponse[]>([]);
  const [datos, setDatos] = useState<ReporteMensualidad[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    Promise.all([
      disciplinasApi.listarDisciplinasSimplificadas(),
      profesoresApi.listarProfesoresActivos(true),
    ])
      .then(([disciplinasResponse, profesoresResponse]) => {
        setDisciplinas(disciplinasResponse);
        setProfesores(profesoresResponse);
      })
      .catch(() => toast.error("No se pudieron cargar los filtros del reporte"));
  }, []);

  const filtrosValidos = () => {
    if (!desde || !hasta || hasta < desde) {
      toast.error("Ingresá un rango de fechas válido");
      return false;
    }

    return true;
  };

  const buscar = async () => {
    if (!filtrosValidos()) return;

    setLoading(true);

    try {
      const { data } = await api.get<ReporteMensualidad[]>("/reportes/mensualidades", {
        params: {
          desde,
          hasta,
          disciplinaId: disciplinaId || undefined,
          profesorId: profesorId || undefined,
        },
      });

      setDatos(data);
    } catch {
      toast.error("No se pudo generar el reporte");
    } finally {
      setLoading(false);
    }
  };

  const exportar = async () => {
    if (!filtrosValidos()) return;

    if (!isMoney(porcentajeEscuela) || compareMoney(porcentajeEscuela, "100.00") > 0) {
      toast.error("El porcentaje de la escuela debe tener hasta dos decimales");
      return;
    }

    setLoading(true);

    try {
      const { data } = await api.post<Blob>("/reportes/mensualidades/exportar", {
        fechaInicio: desde,
        fechaFin: hasta,
        disciplinaId: disciplinaId ? Number(disciplinaId) : null,
        profesorId: profesorId ? Number(profesorId) : null,
        porcentajeEscuela: normalizeMoneyInput(porcentajeEscuela),
      }, { responseType: "blob" });

      const url = URL.createObjectURL(data);
      const link = document.createElement("a");

      link.href = url;
      link.download = "liquidacion.pdf";
      link.click();

      URL.revokeObjectURL(url);
    } catch {
      toast.error("No se pudo exportar la liquidación");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="page-container">
      <PageHeader
        eyebrow="Reportes"
        title="Reporte de mensualidades"
        description="Consultá mensualidades por período, disciplina y profesor."
        count={datos.length}
      />

      <FilterBar label="Filtros del reporte">
        <label className="field-group" htmlFor="reporte-desde">
          Desde
          <input
            id="reporte-desde"
            className="form-input"
            type="date"
            value={desde}
            onChange={(event) => setDesde(event.target.value)}
          />
        </label>

        <label className="field-group" htmlFor="reporte-hasta">
          Hasta
          <input
            id="reporte-hasta"
            className="form-input"
            type="date"
            value={hasta}
            onChange={(event) => setHasta(event.target.value)}
          />
        </label>

        <label className="field-group" htmlFor="reporte-disciplina">
          Disciplina
          <select
            id="reporte-disciplina"
            className="form-input"
            value={disciplinaId}
            onChange={(event) => setDisciplinaId(event.target.value)}
          >
            <option value="">Todas</option>
            {disciplinas.map((disciplina) => (
              <option key={disciplina.id} value={disciplina.id}>
                {disciplina.nombre}
              </option>
            ))}
          </select>
        </label>

        <label className="field-group" htmlFor="reporte-profesor">
          Profesor
          <select
            id="reporte-profesor"
            className="form-input"
            value={profesorId}
            onChange={(event) => setProfesorId(event.target.value)}
          >
            <option value="">Todos</option>
            {profesores.map((profesor) => (
              <option key={profesor.id} value={profesor.id}>
                {profesor.nombre} {profesor.apellido}
              </option>
            ))}
          </select>
        </label>

        <label className="field-group" htmlFor="porcentaje-escuela">
          Porcentaje escuela
          <input
            id="porcentaje-escuela"
            className="form-input"
            inputMode="decimal"
            value={porcentajeEscuela}
            onChange={(event) => setPorcentajeEscuela(event.target.value)}
          />
        </label>

        <div className="flex gap-2">
          <Boton onClick={buscar} disabled={loading}>Consultar</Boton>
          <PermissionGate permission={PERMISSIONS.REPORTES_EXPORTAR}>
            <Boton onClick={exportar} disabled={loading} className="page-button-secondary">Exportar PDF</Boton>
          </PermissionGate>
        </div>
      </FilterBar>

      {loading && <LoadingState message="Generando reporte..." />}

      {!loading && datos.length === 0 && (
        <EmptyState message="No hay resultados para el rango consultado." />
      )}

      {datos.length > 0 && (
        <div className="page-card">
          <Tabla
            headers={["Fecha", "Alumno", "Disciplina", "Profesor", "Original", "Cobrado", "Saldo", "Estado"]}
            data={datos}
            getRowKey={(fila) => fila.cargoId}
            customRender={(fila) => [
              fila.fechaEmision,
              fila.alumno,
              fila.disciplina,
              fila.profesor,
              <span className="numeric-cell block" key="original">$ {formatMoney(fila.importeOriginal)}</span>,
              <span className="numeric-cell block" key="cobrado">$ {formatMoney(fila.importeCobrado)}</span>,
              <span className="numeric-cell block" key="saldo">$ {formatMoney(fila.saldo)}</span>,
              fila.estado,
            ]}
          />
        </div>
      )}
    </div>
  );
};

export default Reportes;
