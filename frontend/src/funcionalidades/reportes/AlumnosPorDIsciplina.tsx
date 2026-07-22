"use client";

import React, {
  useEffect,
  useState,
  useCallback,
  useMemo,
  useRef,
} from "react";
import { useNavigate } from "react-router-dom";
import { toast } from "react-toastify";
import {
  Card,
  CardContent,
  CardHeader,
  CardTitle,
} from "../../componentes/ui/card";
import { Button } from "../../componentes/ui/button";
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "../../componentes/ui/table";
import { Input } from "../../componentes/ui/input";
import api from "../../api/axiosConfig";
import PermissionGate from "../../componentes/comunes/PermissionGate";
import { PERMISSIONS } from "../../config/permissions";

interface Disciplina {
  id: number;
  nombre: string;
}

interface Alumno {
  id: number;
  nombre: string;
  apellido: string;
}

const AlumnosPorDisciplina: React.FC = () => {
  const navigate = useNavigate();
  const [disciplinas, setDisciplinas] = useState<Disciplina[]>([]);
  const [disciplineFilter, setDisciplineFilter] = useState<string>("");
  const [selectedDisciplineId, setSelectedDisciplineId] = useState<
    number | null
  >(null);
  const [alumnos, setAlumnos] = useState<Alumno[]>([]);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [showSuggestions, setShowSuggestions] = useState<boolean>(false);
  const [activeSuggestionIndex, setActiveSuggestionIndex] =
    useState<number>(-1);
  const [sortAsc, setSortAsc] = useState<boolean>(true);
  const searchWrapperRef = useRef<HTMLDivElement>(null);

  // Carga de disciplinas al montar el componente
  const fetchDisciplinas = useCallback(async () => {
    try {
      const response = await api.get<Disciplina[]>("/disciplinas");
      setDisciplinas(response.data);
    } catch {
      toast.error("Error al cargar disciplinas");
    }
  }, []);

  useEffect(() => {
    fetchDisciplinas();
  }, [fetchDisciplinas]);

  // Filtrado de disciplinas según el texto ingresado
  const filteredDisciplinas = useMemo(() => {
    if (!disciplineFilter.trim()) return disciplinas;
    return disciplinas.filter((d) =>
      d.nombre.toLowerCase().includes(disciplineFilter.toLowerCase())
    );
  }, [disciplineFilter, disciplinas]);

  // Al seleccionar disciplina: guarda ID, texto y carga alumnos
  const handleSeleccionarDisciplina = (disciplina: Disciplina) => {
    setSelectedDisciplineId(disciplina.id);
    setDisciplineFilter(disciplina.nombre);
    setActiveSuggestionIndex(-1);
    setShowSuggestions(false);
    fetchAlumnosPorDisciplina(disciplina.id);
  };

  // Consulta alumnos para la disciplina seleccionada
  const fetchAlumnosPorDisciplina = async (disciplinaId: number) => {
    setLoading(true);
    setError(null);
    try {
      const response = await api.get<Alumno[]>(
        `/disciplinas/${disciplinaId}/alumnos`
      );
      setAlumnos(response.data);
    } catch {
      toast.error("Error al cargar alumnos");
      setError(
        "Ocurrió un error al cargar los alumnos. Por favor, intenta de nuevo."
      );
    } finally {
      setLoading(false);
    }
  };

  // Función para exportar alumnos a PDF
  const descargarAlumnosPDF = async (): Promise<void> => {
    if (!selectedDisciplineId) return;
    try {
      const response = await api.get(
        `/disciplinas/${selectedDisciplineId}/alumnos/pdf`,
        { responseType: "blob" }
      );
      const url = window.URL.createObjectURL(new Blob([response.data]));
      const link = document.createElement("a");
      link.href = url;
      link.setAttribute(
        "download",
        `alumnos_disciplina_${selectedDisciplineId}.pdf`
      );
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      window.URL.revokeObjectURL(url);
      toast.success("PDF exportado correctamente");
    } catch {
      toast.error("Error al exportar alumnos a PDF");
    }
  };

  // Manejo de teclas para la lista de sugerencias
  const handleDisciplineKeyDown = (
    e: React.KeyboardEvent<HTMLInputElement>
  ) => {
    if (filteredDisciplinas.length > 0) {
      if (e.key === "ArrowDown") {
        e.preventDefault();
        setActiveSuggestionIndex((prev) =>
          prev < filteredDisciplinas.length - 1 ? prev + 1 : 0
        );
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        setActiveSuggestionIndex((prev) =>
          prev > 0 ? prev - 1 : filteredDisciplinas.length - 1
        );
      } else if (e.key === "Enter" || e.key === "Tab") {
        if (
          activeSuggestionIndex >= 0 &&
          activeSuggestionIndex < filteredDisciplinas.length
        ) {
          e.preventDefault();
          handleSeleccionarDisciplina(
            filteredDisciplinas[activeSuggestionIndex]
          );
        }
      }
    }
  };

  // Limpiar selección de disciplina
  const limpiarDisciplina = () => {
    setDisciplineFilter("");
    setSelectedDisciplineId(null);
    setAlumnos([]);
    setShowSuggestions(false);
  };

  // Cerrar sugerencias al hacer clic fuera
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (
        searchWrapperRef.current &&
        !searchWrapperRef.current.contains(e.target as Node)
      ) {
        setShowSuggestions(false);
      }
    };
    document.addEventListener("mousedown", handleClickOutside);
    return () => document.removeEventListener("mousedown", handleClickOutside);
  }, []);

  // Ordenar alumnos alfabéticamente por nombre y apellido
  const sortedAlumnos = useMemo(() => {
    return [...alumnos].sort((a, b) => {
      const nameA = `${a.nombre.toLowerCase()} ${a.apellido.toLowerCase()}`;
      const nameB = `${b.nombre.toLowerCase()} ${b.apellido.toLowerCase()}`;
      if (nameA < nameB) return sortAsc ? -1 : 1;
      if (nameA > nameB) return sortAsc ? 1 : -1;
      return 0;
    });
  }, [alumnos, sortAsc]);

  return (
    <div className="container mx-auto py-6">
      <Card>
        <CardHeader>
          <CardTitle>Alumnos por Disciplina</CardTitle>
        </CardHeader>
        <CardContent>
          {/* Filtro de disciplina */}
          <div className="mb-4" ref={searchWrapperRef}>
            <label
              htmlFor="searchDiscipline"
              className="block text-sm font-medium text-gray-700 mb-1"
            >
              Selecciona la disciplina:
            </label>
            <div className="relative">
              <Input
                id="searchDiscipline"
                placeholder="Escribe el nombre..."
                value={disciplineFilter}
                onChange={(e) => {
                  setDisciplineFilter(e.target.value);
                  setShowSuggestions(true);
                }}
                onFocus={() => setShowSuggestions(true)}
                onKeyDown={handleDisciplineKeyDown}
                className="form-input w-full"
              />
              {showSuggestions && filteredDisciplinas.length > 0 && (
                <ul className="absolute z-10 w-full bg-white text-black border">
                  {filteredDisciplinas.map((disciplina, index) => (
                    <li
                      key={disciplina.id}
                      onClick={() => handleSeleccionarDisciplina(disciplina)}
                      onMouseEnter={() => setActiveSuggestionIndex(index)}
                      className={`p-2 cursor-pointer ${
                        index === activeSuggestionIndex ? "bg-gray-200" : ""
                      }`}
                    >
                      {disciplina.nombre}
                    </li>
                  ))}
                </ul>
              )}
            </div>
            <Button
              onClick={limpiarDisciplina}
              variant="outline"
              size="sm"
              className="mt-2"
            >
              Limpiar
            </Button>
          </div>

          {/* Controles: ordenar e exportar PDF */}
          {alumnos.length > 0 && (
            <div className="mb-4 flex justify-between">
              <Button onClick={() => setSortAsc((prev) => !prev)}>
                {sortAsc ? "Ordenar Descendente" : "Ordenar Ascendente"}
              </Button>
              <PermissionGate permission={PERMISSIONS.REPORTES_EXPORTAR}>
                <PermissionGate permission={PERMISSIONS.DISCIPLINAS_LEER}>
                  <Button variant="outline" size="sm" onClick={descargarAlumnosPDF}>
                    Exportar PDF
                  </Button>
                </PermissionGate>
              </PermissionGate>
            </div>
          )}

          {/* Mensajes de loading o error */}
          {loading && <p className="text-center py-4">Cargando alumnos...</p>}
          {error && <p className="text-center text-red-600 py-4">{error}</p>}

          {/* Tabla con la lista de alumnos */}
          {sortedAlumnos.length > 0 && (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>#</TableHead>
                  <TableHead>Alumno</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {sortedAlumnos.map((alumno, index) => (
                  <TableRow key={alumno.id}>
                    <TableCell>{index + 1}</TableCell>
                    <TableCell>
                      {`${alumno.nombre} ${alumno.apellido}`}
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          )}

          <div className="mt-6 flex justify-end">
            <Button onClick={() => navigate("/reportes")}>Volver</Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
};

export default AlumnosPorDisciplina;
