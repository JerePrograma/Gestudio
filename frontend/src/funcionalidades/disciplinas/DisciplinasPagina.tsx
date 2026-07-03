"use client";

import { useEffect, useState, useCallback, useMemo } from "react";
import { useNavigate } from "react-router-dom";
import Tabla from "../../componentes/comunes/Tabla";
import api from "../../api/axiosConfig";
import Boton from "../../componentes/comunes/Boton";
import { PlusCircle, Pencil, Trash2, BadgeDollarSign } from "lucide-react";
import disciplinasApi from "../../api/disciplinasApi";
import { toast } from "react-toastify";
import ListaConCargaManual from "../../componentes/comunes/ListaConCargaManual";

interface Disciplina {
  id: number;
  nombre: string;
  horario: string;
}

const itemsPerPage = 25;

const Disciplinas = () => {
  const [disciplinas, setDisciplinas] = useState<Disciplina[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState("");
  const [sortOrder, setSortOrder] = useState<"asc" | "desc">("asc");
  // Se utiliza visibleCount para controlar cuántos elementos se muestran
  const [visibleCount, setVisibleCount] = useState(itemsPerPage);
  const navigate = useNavigate();

  const fetchDisciplinas = useCallback(async () => {
    try {
      setLoading(true);
      setError(null);
      const response = await api.get<Disciplina[]>("/disciplinas");
      setDisciplinas(response.data);
    } catch {
      toast.error("Error al cargar disciplinas:");
      setError("Error al cargar disciplinas.");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    fetchDisciplinas();
  }, [fetchDisciplinas]);

  // Filtrar y ordenar disciplinas según el término y orden de búsqueda
  const disciplinasFiltradasYOrdenadas = useMemo(() => {
    const filtradas = disciplinas.filter((disciplina) =>
      disciplina.nombre.toLowerCase().includes(searchTerm.toLowerCase())
    );
    return filtradas.sort((a, b) => {
      const nombreA = a.nombre.toLowerCase();
      const nombreB = b.nombre.toLowerCase();
      return sortOrder === "asc"
        ? nombreA.localeCompare(nombreB)
        : nombreB.localeCompare(nombreA);
    });
  }, [disciplinas, searchTerm, sortOrder]);

  // Se obtiene el subconjunto de disciplinas a mostrar
  const currentItems = useMemo(
    () => disciplinasFiltradasYOrdenadas.slice(0, visibleCount),
    [disciplinasFiltradasYOrdenadas, visibleCount]
  );

  // Determina si hay más elementos para cargar
  const hasMore = useMemo(
    () => visibleCount < disciplinasFiltradasYOrdenadas.length,
    [visibleCount, disciplinasFiltradasYOrdenadas.length]
  );

  // Función que incrementa visibleCount en bloques de itemsPerPage
  const onLoadMore = useCallback(() => {
    if (hasMore) {
      setVisibleCount((prev) => prev + itemsPerPage);
    }
  }, [hasMore]);

  const nombresUnicos = useMemo(() => {
    const nombresSet = new Set(
      disciplinas.map((disciplina) => disciplina.nombre)
    );
    return Array.from(nombresSet);
  }, [disciplinas]);

  // Al cambiar el término de búsqueda se reinicia visibleCount
  const handleSearchChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setSearchTerm(e.target.value);
    setVisibleCount(itemsPerPage);
  };

  const handleEliminarDisciplina = useCallback(async (id: number) => {
    if (window.confirm("¿Seguro que deseas eliminar esta disciplina?")) {
      try {
        await disciplinasApi.eliminarDisciplina(id);
        setDisciplinas((prev) => prev.filter((d) => d.id !== id));
      } catch {
        toast.error("Error al eliminar disciplina:");
      }
    }
  }, []);

  if (loading && disciplinas.length === 0)
    return <div className="text-center py-4">Cargando...</div>;
  if (error)
    return <div className="text-center py-4 text-destructive">{error}</div>;

  return (
    <div className="container mx-auto p-6 space-y-6">
      <div className="flex items-center justify-between">
        <h1 className="text-3xl font-bold tracking-tight">Disciplinas</h1>
        <Boton
          onClick={() => navigate("/disciplinas/formulario")}
          className="inline-flex items-center gap-2 bg-primary text-primary-foreground hover:bg-primary/90"
          aria-label="Registrar nueva disciplina"
        >
          <PlusCircle className="w-5 h-5" />
          Registrar Nueva Disciplina
        </Boton>
      </div>

      {/* Controles de búsqueda y orden */}
      <div className="flex flex-col sm:flex-row sm:justify-between gap-4">
        <div>
          <label htmlFor="search" className="mr-2 font-medium">
            Buscar por nombre:
          </label>
          <input
            id="search"
            list="nombres"
            type="text"
            value={searchTerm}
            onChange={handleSearchChange}
            placeholder="Escribe o selecciona un nombre..."
            className="border rounded px-2 py-1"
          />
          <datalist id="nombres">
            {nombresUnicos.map((nombre) => (
              <option key={nombre} value={nombre} />
            ))}
          </datalist>
        </div>
        <div>
          <label htmlFor="sortOrder" className="mr-2 font-medium">
            Orden:
          </label>
          <select
            id="sortOrder"
            value={sortOrder}
            onChange={(e) => setSortOrder(e.target.value as "asc" | "desc")}
            className="border rounded px-2 py-1"
          >
            <option value="asc">Ascendente</option>
            <option value="desc">Descendente</option>
          </select>
        </div>
      </div>

      <div className="rounded-lg border bg-card text-card-foreground shadow-sm">
        <Tabla
          headers={["ID", "Nombre", "Horario", "Acciones"]}
          data={currentItems}
          customRender={(fila: Disciplina) => [
            fila.id,
            fila.nombre,
            fila.horario,
          ]}
          actions={(fila: Disciplina) => (
            <div className="flex gap-2">
              <Boton
                onClick={() => navigate(`/disciplinas/${fila.id}/tarifas`)}
                className="inline-flex items-center gap-2 bg-secondary text-secondary-foreground hover:bg-secondary/90"
                aria-label={`Ver tarifas de ${fila.nombre}`}
              >
                <BadgeDollarSign className="w-4 h-4" />
                Tarifas
              </Boton>
              <Boton
                onClick={() =>
                  navigate(`/disciplinas/formulario?id=${fila.id}`)
                }
                className="inline-flex items-center gap-2 bg-secondary text-secondary-foreground hover:bg-secondary/90"
                aria-label={`Editar disciplina ${fila.nombre}`}
              >
                <Pencil className="w-4 h-4" />
                Editar
              </Boton>
              <Boton
                onClick={() => handleEliminarDisciplina(fila.id)}
                className="inline-flex items-center gap-2 bg-destructive text-destructive-foreground hover:bg-destructive/90"
                aria-label={`Eliminar disciplina ${fila.nombre}`}
              >
                <Trash2 className="w-4 h-4" />
                Eliminar
              </Boton>
            </div>
          )}
        />

        {hasMore && (
          <div className="py-4 border-t">
            <ListaConCargaManual
              onLoadMore={onLoadMore}
              hasMore={hasMore}
              loading={loading}
              className="justify-center w-full"
            >
              {loading && (
                <div className="text-center py-2">Cargando más...</div>
              )}
            </ListaConCargaManual>
          </div>
        )}
      </div>
    </div>
  );
};

export default Disciplinas;
