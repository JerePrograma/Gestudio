import React, { useState, useEffect } from "react";
import Tabla from "../../componentes/comunes/Tabla";
import Boton from "../../componentes/comunes/Boton";
import { toast } from "react-toastify";
import observacionProfesorApi from "../../api/observacionProfesorApi";
import type {
  ObservacionProfesorResponse,
  ObservacionProfesorRequest,
} from "../../types/types";
import profesoresApi from "../../api/profesoresApi";

// Tipo para Profesor (puedes tenerlo definido en otro archivo)
interface Profesor {
  id: number;
  nombre: string;
  apellido: string;
}

const ConsultaObservacionesProfesores: React.FC = () => {
  // Estados para el filtro
  const [fechaInicio, setFechaInicio] = useState<string>("");
  const [fechaFin, setFechaFin] = useState<string>("");
  const [profesorId, setProfesorId] = useState<number | null>(null);
  const [profesores, setProfesores] = useState<Profesor[]>([]);

  // Lista de observaciones filtradas
  const [observaciones, setObservaciones] = useState<
    ObservacionProfesorResponse[]
  >([]);
  const [loading, setLoading] = useState(false);

  // Estados para el modal de "Agregar Observación"
  const [showModal, setShowModal] = useState(false);
  const [nuevaFecha, setNuevaFecha] = useState<string>("");
  const [nuevaObservacion, setNuevaObservacion] = useState<string>("");

  // Inicializar fechas: inicio = primer día del mes actual, fin = hoy
  useEffect(() => {
    const hoy = new Date();
    const inicioMes = new Date(hoy.getFullYear(), hoy.getMonth(), 1);
    setFechaInicio(inicioMes.toISOString().split("T")[0]);
    setFechaFin(hoy.toISOString().split("T")[0]);
  }, []);

  // Cargar lista de profesores
  useEffect(() => {
    const cargarProfesores = async () => {
      try {
        const data = await profesoresApi.listarProfesoresActivos();
        setProfesores(data);
      } catch {
        toast.error("Error al cargar profesores.");
      }
    };
    cargarProfesores();
  }, []);

  // Función para filtrar observaciones desde el frontend
  const handleFiltrar = async () => {
    if (!profesorId) {
      toast.error("Debe seleccionar un profesor para filtrar.");
      return;
    }
    try {
      setLoading(true);
      // Se obtienen TODAS las observaciones del profesor desde el backend.
      const data = await observacionProfesorApi.listarObservacionesPorProfesor(
        profesorId
      );
      // Luego, se filtran por el rango de fechas seleccionado en el frontend.
      const filtradas = data.filter((obs) => {
        // Se asume que obs.fecha es una cadena ISO (ej. "2025-03-27")
        return obs.fecha >= fechaInicio && obs.fecha <= fechaFin;
      });
      setObservaciones(filtradas);
    } catch {
      toast.error("Error al cargar observaciones.");
    } finally {
      setLoading(false);
    }
  };

  // Abrir modal para agregar observación
  const handleAbrirModal = () => {
    if (!profesorId) {
      toast.error(
        "Debe seleccionar un profesor antes de agregar una observación."
      );
      return;
    }
    setNuevaFecha(new Date().toISOString().split("T")[0]);
    setNuevaObservacion("");
    setShowModal(true);
  };

  const handleCerrarModal = () => {
    setShowModal(false);
  };

  // Guardar nueva observación
  const handleGuardarObservacion = async () => {
    if (!nuevaFecha || !nuevaObservacion) {
      toast.error("Debe ingresar fecha y observación.");
      return;
    }
    const solicitud: ObservacionProfesorRequest = {
      profesorId: profesorId!,
      fecha: nuevaFecha,
      observacion: nuevaObservacion,
    };
    try {
      await observacionProfesorApi.crearObservacionProfesor(solicitud);
      toast.success("Observación agregada correctamente.");
      setShowModal(false);
      // Refrescar la lista de observaciones
      handleFiltrar();
    } catch {
      toast.error("Error al agregar la observación.");
    }
  };

  return (
    <div className="page-container p-4">
      <h1 className="text-2xl font-bold mb-4">Consulta de Observaciones</h1>

      {/* Filtros */}
      <div className="flex gap-4 items-end mb-4">
        <div>
          <label className="block font-medium">Fecha Inicio:</label>
          <input
            type="date"
            className="border p-2"
            value={fechaInicio}
            onChange={(e) => setFechaInicio(e.target.value)}
          />
        </div>
        <div>
          <label className="block font-medium">Fecha Fin:</label>
          <input
            type="date"
            className="border p-2"
            value={fechaFin}
            onChange={(e) => setFechaFin(e.target.value)}
          />
        </div>
        <div>
          <label className="block font-medium">Profesor:</label>
          <select
            className="border p-2"
            value={profesorId ?? ""}
            onChange={(e) => setProfesorId(Number(e.target.value))}
          >
            <option value="">Seleccione...</option>
            {profesores.map((prof) => (
              <option key={prof.id} value={prof.id}>
                {prof.nombre} {prof.apellido}
              </option>
            ))}
          </select>
        </div>
        <Boton
          onClick={handleFiltrar}
          className="bg-green-500 text-white p-2 rounded"
        >
          Ver Observaciones
        </Boton>
      </div>

      {/* Botón para Agregar Observación */}
      <div className="mb-4">
        <Boton
          onClick={handleAbrirModal}
          className="bg-blue-500 text-white p-2 rounded"
        >
          Agregar Observación
        </Boton>
      </div>

      {/* Tabla de Observaciones */}
      <div className="border p-2">
        {loading ? (
          <p>Cargando...</p>
        ) : (
          <Tabla
            headers={["ID", "Fecha", "Observación"]}
            data={observaciones}
            getRowKey={(row) => row.id}
            customRender={(obs) => [obs.id, obs.fecha, obs.observacion]}
            emptyMessage="No hay observaciones para el rango seleccionado."
          />
        )}
      </div>

      {/* Modal para Agregar Observación */}
      {showModal && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black bg-opacity-30">
          <div className="bg-white p-4 rounded shadow-md w-[300px]">
            <h2 className="text-xl font-bold mb-4">Nueva Observación</h2>
            <div className="mb-2">
              <label className="block font-medium">Fecha:</label>
              <input
                type="date"
                className="border p-2 w-full"
                value={nuevaFecha}
                onChange={(e) => setNuevaFecha(e.target.value)}
              />
            </div>
            <div className="mb-2">
              <label className="block font-medium">Observación:</label>
              <textarea
                className="border p-2 w-full"
                value={nuevaObservacion}
                onChange={(e) => setNuevaObservacion(e.target.value)}
              />
            </div>
            <div className="flex justify-end gap-2 mt-4">
              <Boton
                onClick={handleCerrarModal}
                className="bg-gray-300 text-black p-2 rounded"
              >
                Cancelar
              </Boton>
              <Boton
                onClick={handleGuardarObservacion}
                className="bg-green-500 text-white p-2 rounded"
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
