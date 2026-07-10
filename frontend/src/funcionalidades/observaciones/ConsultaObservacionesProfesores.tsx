import React, { useEffect, useState } from "react";
import { toast } from "react-toastify";
import observacionProfesorApi from "../../api/observacionProfesorApi";
import profesoresApi from "../../api/profesoresApi";
import Boton from "../../componentes/comunes/Boton";
import EmptyState from "../../componentes/comunes/EmptyState";
import FilterBar from "../../componentes/comunes/FilterBar";
import LoadingState from "../../componentes/comunes/LoadingState";
import PageHeader from "../../componentes/comunes/PageHeader";
import SectionCard from "../../componentes/comunes/SectionCard";
import Tabla from "../../componentes/comunes/Tabla";
import type {
  ObservacionProfesorRequest,
  ObservacionProfesorResponse,
} from "../../types/types";

interface Profesor {
  id: number;
  nombre: string;
  apellido: string;
}

const ConsultaObservacionesProfesores: React.FC = () => {
  const [fechaInicio, setFechaInicio] = useState("");
  const [fechaFin, setFechaFin] = useState("");
  const [profesorId, setProfesorId] = useState<number | null>(null);
  const [profesores, setProfesores] = useState<Profesor[]>([]);
  const [observaciones, setObservaciones] = useState<ObservacionProfesorResponse[]>([]);
  const [loading, setLoading] = useState(false);

  const [showModal, setShowModal] = useState(false);
  const [nuevaFecha, setNuevaFecha] = useState("");
  const [nuevaObservacion, setNuevaObservacion] = useState("");

  useEffect(() => {
    const hoy = new Date();
    const inicioMes = new Date(hoy.getFullYear(), hoy.getMonth(), 1);

    setFechaInicio(inicioMes.toISOString().split("T")[0]);
    setFechaFin(hoy.toISOString().split("T")[0]);
  }, []);

  useEffect(() => {
    const cargarProfesores = async () => {
      try {
        const data = await profesoresApi.listarProfesoresActivos();
        setProfesores(data);
      } catch {
        toast.error("Error al cargar profesores.");
      }
    };

    void cargarProfesores();
  }, []);

  const profesorSeleccionado = profesores.find((profesor) => profesor.id === profesorId);

  const handleFiltrar = async () => {
    if (!profesorId) {
      toast.error("Seleccioná un profesor para consultar observaciones.");
      return;
    }

    try {
      setLoading(true);

      const data = await observacionProfesorApi.listarObservacionesPorProfesor(profesorId);
      const filtradas = data.filter((obs) => obs.fecha >= fechaInicio && obs.fecha <= fechaFin);

      setObservaciones(filtradas);
    } catch {
      toast.error("Error al cargar observaciones.");
    } finally {
      setLoading(false);
    }
  };

  const handleAbrirModal = () => {
    if (!profesorId) {
      toast.error("Seleccioná un profesor antes de agregar una observación.");
      return;
    }

    setNuevaFecha(new Date().toISOString().split("T")[0]);
    setNuevaObservacion("");
    setShowModal(true);
  };

  const handleGuardarObservacion = async () => {
    if (!nuevaFecha || !nuevaObservacion.trim()) {
      toast.error("Ingresá fecha y observación.");
      return;
    }

    const solicitud: ObservacionProfesorRequest = {
      profesorId: profesorId!,
      fecha: nuevaFecha,
      observacion: nuevaObservacion.trim(),
    };

    try {
      await observacionProfesorApi.crearObservacionProfesor(solicitud);
      toast.success("Observación agregada correctamente.");
      setShowModal(false);
      await handleFiltrar();
    } catch {
      toast.error("Error al agregar la observación.");
    }
  };

  return (
    <div className="page-container">
      <PageHeader
        eyebrow="Gestión académica"
        title="Observaciones de profesores"
        description="Consultá y registrá observaciones docentes por rango de fechas."
        count={observaciones.length}
        actions={(
          <Boton onClick={handleAbrirModal} className="page-button">
            Agregar observación
          </Boton>
        )}
      />

      <FilterBar label="Filtrar observaciones">
        <label className="field-group" htmlFor="fecha-inicio">
          Fecha inicio
          <input
            id="fecha-inicio"
            type="date"
            className="form-input"
            value={fechaInicio}
            onChange={(event) => setFechaInicio(event.target.value)}
          />
        </label>

        <label className="field-group" htmlFor="fecha-fin">
          Fecha fin
          <input
            id="fecha-fin"
            type="date"
            className="form-input"
            value={fechaFin}
            onChange={(event) => setFechaFin(event.target.value)}
          />
        </label>

        <label className="field-group" htmlFor="profesor">
          Profesor
          <select
            id="profesor"
            className="form-input"
            value={profesorId ?? ""}
            onChange={(event) => setProfesorId(event.target.value ? Number(event.target.value) : null)}
          >
            <option value="">Seleccione un profesor</option>
            {profesores.map((profesor) => (
              <option key={profesor.id} value={profesor.id}>
                {profesor.nombre} {profesor.apellido}
              </option>
            ))}
          </select>
        </label>

        <Boton onClick={handleFiltrar} disabled={loading}>
          Ver observaciones
        </Boton>
      </FilterBar>

      {profesorSeleccionado && (
        <SectionCard
          title={`${profesorSeleccionado.nombre} ${profesorSeleccionado.apellido}`}
          description={`Observaciones entre ${fechaInicio || "inicio"} y ${fechaFin || "fin"}.`}
        >
          {loading && <LoadingState message="Cargando observaciones..." />}

          {!loading && observaciones.length === 0 && (
            <EmptyState message="No hay observaciones para el rango seleccionado." />
          )}

          {!loading && observaciones.length > 0 && (
            <Tabla
              headers={["Fecha", "Observación"]}
              data={observaciones}
              getRowKey={(row) => row.id}
              customRender={(obs) => [
                obs.fecha,
                obs.observacion,
              ]}
            />
          )}
        </SectionCard>
      )}

      {!profesorSeleccionado && (
        <EmptyState title="Seleccioná un profesor" message="Elegí un profesor y un rango de fechas para consultar observaciones." />
      )}

      {showModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4">
          <div className="w-full max-w-md rounded-xl border border-border bg-card p-5 shadow-lg">
            <h2 className="text-xl font-bold">Nueva observación</h2>
            <p className="mt-1 text-sm text-muted-foreground">
              {profesorSeleccionado
                ? `Profesor: ${profesorSeleccionado.nombre} ${profesorSeleccionado.apellido}`
                : "Seleccioná un profesor antes de guardar."}
            </p>

            <div className="mt-4 space-y-4">
              <label className="field-group" htmlFor="nueva-fecha">
                Fecha
                <input
                  id="nueva-fecha"
                  type="date"
                  className="form-input"
                  value={nuevaFecha}
                  onChange={(event) => setNuevaFecha(event.target.value)}
                />
              </label>

              <label className="field-group" htmlFor="nueva-observacion">
                Observación
                <textarea
                  id="nueva-observacion"
                  className="form-input min-h-32"
                  value={nuevaObservacion}
                  onChange={(event) => setNuevaObservacion(event.target.value)}
                />
              </label>
            </div>

            <div className="mt-5 flex justify-end gap-2">
              <Boton
                type="button"
                onClick={() => setShowModal(false)}
                className="page-button-secondary"
              >
                Cancelar
              </Boton>
              <Boton
                type="button"
                onClick={handleGuardarObservacion}
                className="page-button"
              >
                Guardar
              </Boton>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default ConsultaObservacionesProfesores;