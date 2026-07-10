"use client";

import { useEffect, useState, useCallback, useMemo } from "react";
import { useNavigate } from "react-router-dom";
import { PlusCircle, Pencil, Trash2 } from "lucide-react";
import { toast } from "react-toastify";
import Tabla from "../../componentes/comunes/Tabla";
import profesoresApi from "../../api/profesoresApi";
import Boton from "../../componentes/comunes/Boton";
import type { ProfesorListadoResponse } from "../../types/types";
import ListaConCargaManual from "../../componentes/comunes/ListaConCargaManual";
import ErrorState from "../../componentes/comunes/ErrorState";
import FilterBar from "../../componentes/comunes/FilterBar";
import LoadingState from "../../componentes/comunes/LoadingState";
import PageHeader from "../../componentes/comunes/PageHeader";
import RowActions from "../../componentes/comunes/RowActions";
import SearchInput from "../../componentes/comunes/SearchInput";
import StatusBadge from "../../componentes/comunes/StatusBadge";

const itemsPerPage = 25;

const Profesores = () => {
  const [profesores, setProfesores] = useState<ProfesorListadoResponse[]>([]);
  const [visibleCount, setVisibleCount] = useState(itemsPerPage);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState("");
  const [sortOrder, setSortOrder] = useState<"asc" | "desc">("asc");
  const navigate = useNavigate();

  const fetchProfesores = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await profesoresApi.listarProfesoresActivos();
      setProfesores(response);
    } catch {
      toast.error("Error al cargar profesores.");
      setError("Error al cargar profesores.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchProfesores();
  }, [fetchProfesores]);

  const profesoresFiltradosYOrdenados = useMemo(() => {
    const filtrados = profesores.filter((profesor) => {
      const nombreCompleto = `${profesor.nombre} ${profesor.apellido}`.toLowerCase();
      return nombreCompleto.includes(searchTerm.toLowerCase());
    });

    return filtrados.sort((a, b) => {
      const nombreA = `${a.nombre} ${a.apellido}`.toLowerCase();
      const nombreB = `${b.nombre} ${b.apellido}`.toLowerCase();

      if (sortOrder === "asc") return nombreA.localeCompare(nombreB);
      return nombreB.localeCompare(nombreA);
    });
  }, [profesores, searchTerm, sortOrder]);

  const currentItems = useMemo(
    () => profesoresFiltradosYOrdenados.slice(0, visibleCount),
    [profesoresFiltradosYOrdenados, visibleCount],
  );

  const hasMore = useMemo(
    () => visibleCount < profesoresFiltradosYOrdenados.length,
    [visibleCount, profesoresFiltradosYOrdenados.length],
  );

  const onLoadMore = useCallback(() => {
    if (hasMore) setVisibleCount((prev) => prev + itemsPerPage);
  }, [hasMore]);

  const nombresUnicos = useMemo(() => {
    const nombresSet = new Set(
      profesores.map((profesor) => `${profesor.nombre} ${profesor.apellido}`),
    );

    return Array.from(nombresSet);
  }, [profesores]);

  const handleSearchChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setSearchTerm(e.target.value);
    setVisibleCount(itemsPerPage);
  };

  const handleEliminarProfesor = async (id: number, nombreCompleto: string) => {
    if (!window.confirm(`¿Eliminar a ${nombreCompleto}?`)) return;

    try {
      await profesoresApi.eliminarProfesor(id);
      toast.success("Profesor eliminado correctamente.");
      await fetchProfesores();
    } catch {
      toast.error("Error al eliminar el profesor.");
    }
  };

  if (loading && profesores.length === 0) return <LoadingState message="Cargando profesores..." />;

  if (error) {
    return <ErrorState message={error} onRetry={() => void fetchProfesores()} />;
  }

  return (
    <div className="page-container">
      <PageHeader
        eyebrow="Gestión académica"
        title="Profesores"
        description="Equipo docente, estado y datos de contacto."
        count={profesoresFiltradosYOrdenados.length}
        actions={(
          <Boton
            onClick={() => navigate("/profesores/formulario")}
            className="page-button"
            aria-label="Registrar nuevo profesor"
          >
            <PlusCircle className="size-4" /> Nuevo profesor
          </Boton>
        )}
      />

      <FilterBar label="Filtrar profesores">
        <SearchInput
          id="search"
          list="nombres"
          label="Buscar profesor"
          value={searchTerm}
          onChange={handleSearchChange}
          placeholder="Buscar por nombre o apellido"
        />
        <datalist id="nombres">
          {nombresUnicos.map((nombre) => (
            <option key={nombre} value={nombre} />
          ))}
        </datalist>

        <label className="field-group sm:w-52" htmlFor="sortOrder">
          Orden
          <select
            id="sortOrder"
            value={sortOrder}
            onChange={(e) => setSortOrder(e.target.value as "asc" | "desc")}
            className="form-input"
          >
            <option value="asc">Ascendente</option>
            <option value="desc">Descendente</option>
          </select>
        </label>
      </FilterBar>

      <div>
        <Tabla
          headers={["Profesor", "Estado"]}
          data={currentItems}
          getRowKey={(row) => row.id}
          customRender={(fila) => {
            const nombreCompleto = `${fila.nombre} ${fila.apellido}`.trim();

            return [
              <span className="font-semibold" key="profesor">{nombreCompleto}</span>,
              <StatusBadge key="estado" tone={fila.activo ? "success" : "neutral"}>
                {fila.activo ? "Activo" : "Baja"}
              </StatusBadge>,
            ];
          }}
          actions={(fila) => {
            const nombreCompleto = `${fila.nombre} ${fila.apellido}`.trim();

            return (
              <RowActions
                label={`Acciones de ${nombreCompleto}`}
                actions={[
                  {
                    label: "Editar",
                    icon: Pencil,
                    onSelect: () => navigate(`/profesores/formulario?id=${fila.id}`),
                  },
                  {
                    label: "Eliminar",
                    icon: Trash2,
                    destructive: true,
                    onSelect: () => void handleEliminarProfesor(fila.id, nombreCompleto),
                  },
                ]}
              />
            );
          }}
        />

        {hasMore && (
          <div className="py-4 border-t">
            <ListaConCargaManual
              onLoadMore={onLoadMore}
              hasMore={hasMore}
              loading={loading}
              className="justify-center w-full"
            >
              {loading && <div className="text-center py-2">Cargando más...</div>}
            </ListaConCargaManual>
          </div>
        )}
      </div>
    </div>
  );
};

export default Profesores;