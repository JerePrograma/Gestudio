import React, {
  useEffect,
  useState,
  useCallback,
  useMemo,
  useRef,
} from "react";
import { useNavigate } from "react-router-dom";
import { toast } from "react-toastify";
import { Check, X } from "lucide-react";
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
import DatePicker from "react-datepicker";
import "react-datepicker/dist/react-datepicker.css";
import asistenciasApi from "../../api/asistenciasApi";
import api from "../../api/axiosConfig";
import {
  AsistenciaDiariaRegistroRequest,
  AsistenciaDiariaResponse,
  AsistenciaMensualDetalleResponse,
  EstadoAsistencia,
  DisciplinaDetalleResponse,
} from "../../types/types";
import { debounce } from "../../utils/debounce";
import Boton from "../../componentes/comunes/Boton";
import EmptyState from "../../componentes/comunes/EmptyState";
import ErrorState from "../../componentes/comunes/ErrorState";
import LoadingState from "../../componentes/comunes/LoadingState";
import PageHeader from "../../componentes/comunes/PageHeader";
import SectionCard from "../../componentes/comunes/SectionCard";
import { PERMISSIONS } from "../../config/permissions";
import { useAuth } from "../../hooks/context/useAuth";

interface Disciplina {
  id: number;
  nombre: string;
  diasSemana: string[];
}

const AsistenciaDiariaFormAdaptado: React.FC = () => {
  const navigate = useNavigate();
  const { hasPermission } = useAuth();
  const canRegister = hasPermission(PERMISSIONS.APP_ACCESS)
    && hasPermission(PERMISSIONS.ASISTENCIAS_REGISTRAR);

  // Estados para filtros y datos
  const [disciplinas, setDisciplinas] = useState<Disciplina[]>([]);
  const [disciplineFilter, setDisciplineFilter] = useState<string>("");
  const [selectedDisciplineId, setSelectedDisciplineId] = useState<
    number | null
  >(null);
  const [selectedDate, setSelectedDate] = useState<Date>(new Date());
  const [monthlyDetail, setMonthlyDetail] =
    useState<AsistenciaMensualDetalleResponse | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);
  const [showSuggestions, setShowSuggestions] = useState<boolean>(false);
  const [activeSuggestionIndex, setActiveSuggestionIndex] =
    useState<number>(-1);
  const searchWrapperRef = useRef<HTMLDivElement>(null);
  const [isValidClassDay, setIsValidClassDay] = useState<boolean>(false);
  const [, setDiasClase] = useState<string[]>([]);

  // Cargar lista de disciplinas
  const fetchDisciplinas = useCallback(async () => {
    try {
      const data = await asistenciasApi.listarDisciplinasSimplificadas();
      const disciplinasConDias = data.map((disciplina) => ({
        id: disciplina.id,
        nombre: disciplina.nombre,
        diasSemana: disciplina.horarios?.map((horario) => horario.diaSemana) ?? [],
      }));
      setDisciplinas(disciplinasConDias);
    } catch {
      setError("Error al cargar disciplinas");
    }
  }, []);

  useEffect(() => {
    fetchDisciplinas();
  }, [fetchDisciplinas]);

  const filteredDisciplinas = useMemo(() => {
    if (!disciplineFilter.trim()) return disciplinas;
    return disciplinas.filter((d) =>
      d.nombre.toLowerCase().includes(disciplineFilter.toLowerCase())
    );
  }, [disciplineFilter, disciplinas]);

  // Obtiene los días de clase de la disciplina seleccionada
  const fetchDiasClase = useCallback(async (): Promise<string[]> => {
    if (!selectedDisciplineId) return [];
    try {
      const response = await api.get<DisciplinaDetalleResponse>(`/disciplinas/${selectedDisciplineId}`);
      const horarios = response.data?.horarios || [];
      const dias = horarios.map((horario) => horario.diaSemana);
      setDiasClase(dias);
      return dias;
    } catch {
      return [];
    }
  }, [selectedDisciplineId]);

  const handleSeleccionarDisciplina = (disciplina: Disciplina) => {
    setSelectedDisciplineId(disciplina.id);
    setDisciplineFilter(disciplina.nombre);
    setActiveSuggestionIndex(-1);
    setShowSuggestions(false);
    fetchDiasClase();
  };

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

  const limpiarDisciplina = () => {
    setDisciplineFilter("");
    setSelectedDisciplineId(null);
    setShowSuggestions(false);
  };

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

  const handleBuscarAsistencia = async () => {
    if (!selectedDate || !selectedDisciplineId) {
      toast.warn("Complete los filtros");
      return;
    }
    const dias = await fetchDiasClase();
    const diasAbreviados = dias.map((d) => d.substring(0, 3).toUpperCase());
    const diasReferencia = ["DOM", "LUN", "MAR", "MIE", "JUE", "VIE", "SAB"];
    const dayStr = diasReferencia[selectedDate.getDay()];
    if (!diasAbreviados.includes(dayStr)) {
      setIsValidClassDay(false);
      setMonthlyDetail(null);
      return;
    }
    setIsValidClassDay(true);
    cargarAsistencias(selectedDate);
  };

  const cargarAsistencias = useCallback(
    async (fecha: Date) => {
      if (!selectedDisciplineId) return;
      setLoading(true);
      setError(null);
      try {
        const mes = fecha.getMonth() + 1;
        const anio = fecha.getFullYear();
        const detail =
          await asistenciasApi.obtenerAsistenciaMensualDetallePorParametros(
            selectedDisciplineId,
            mes,
            anio
          );
        setMonthlyDetail(detail);
      } catch {
        setError("Error al cargar las asistencias");
      } finally {
        setLoading(false);
      }
    },
    [selectedDisciplineId]
  );

  // Deduplicamos los registros de alumnos basándonos en el ID del alumno
  const uniqueAlumnos = useMemo(() => {
    if (!monthlyDetail) return [];
    const alumnosMap = new Map<number, (typeof monthlyDetail.alumnos)[0]>();
    monthlyDetail.alumnos.forEach((alumno) => {
      const alumnoId = alumno.alumno?.id;
      if (alumnoId) {
        if (!alumnosMap.has(alumnoId)) {
          alumnosMap.set(alumnoId, { ...alumno });
        } else {
          const existing = alumnosMap.get(alumnoId)!;
          existing.asistenciasDiarias = [
            ...existing.asistenciasDiarias,
            ...alumno.asistenciasDiarias,
          ];
          if (!existing.observacion && alumno.observacion) {
            existing.observacion = alumno.observacion;
          }
        }
      } else {
        alumnosMap.set(alumno.id, alumno);
      }
    });
    return Array.from(alumnosMap.values());
  }, [monthlyDetail]);

  // Generamos la lista de registros diarios a partir de los alumnos únicos
  const dailyRecords = useMemo(() => {
    if (!monthlyDetail) return [];
    const selectedIso = selectedDate.toISOString().split("T")[0];
    return uniqueAlumnos.map((alumno) => {
      // Buscamos el registro de asistencia para la fecha seleccionada
      const asistenciaDiaria = alumno.asistenciasDiarias.find(
        (ad) => ad.fecha === selectedIso
      );
      // Usamos directamente la información mapeada en "alumno"
      const alumnoNombre = alumno.alumno?.nombre || "";
      const alumnoApellido = alumno.alumno?.apellido || "";
      return {
        alumnoId: alumno.id,
        alumnoNombre,
        alumnoApellido,
        asistenciaDiaria,
      };
    });
  }, [monthlyDetail, selectedDate, uniqueAlumnos]);

  const toggleAsistencia = async (
    alumnoId: number,
    currentRecord: AsistenciaDiariaResponse | undefined
  ) => {
    if (!canRegister || !selectedDate || !monthlyDetail) return;
    const fechaFormateada = selectedDate.toISOString().split("T")[0];
    if (!currentRecord) {
      const alumnoRegistro = uniqueAlumnos.find((a) => a.id === alumnoId);
      if (!alumnoRegistro) {
        return;
      }
      const newRecord: AsistenciaDiariaRegistroRequest = {
        fecha: fechaFormateada,
        estado: EstadoAsistencia.PRESENTE,
        asistenciaAlumnoMensualId: alumnoRegistro.id,
      };
      try {
        const created = await asistenciasApi.registrarAsistenciaDiaria(
          newRecord
        );
        const updatedAlumnos = monthlyDetail.alumnos.map((alumno) => {
          if (alumno.id === alumnoId) {
            return {
              ...alumno,
              asistenciasDiarias: [...alumno.asistenciasDiarias, created],
            };
          }
          return alumno;
        });
        setMonthlyDetail({ ...monthlyDetail, alumnos: updatedAlumnos });
      } catch {
        toast.error("No se pudo registrar la asistencia");
      }
      return;
    }
    try {
      const nuevoEstado =
        currentRecord.estado === EstadoAsistencia.PRESENTE
          ? EstadoAsistencia.AUSENTE
          : EstadoAsistencia.PRESENTE;
      const request: AsistenciaDiariaRegistroRequest = {
        id: currentRecord.id,
        fecha: fechaFormateada,
        estado: nuevoEstado,
        asistenciaAlumnoMensualId: currentRecord.asistenciaAlumnoMensualId,
      };
      const updated = await asistenciasApi.registrarAsistenciaDiaria(request);
      const updatedAlumnos = monthlyDetail.alumnos.map((alumno) => {
        if (alumno.id === alumnoId) {
          return {
            ...alumno,
            asistenciasDiarias: alumno.asistenciasDiarias.map((ad) =>
              ad.fecha === fechaFormateada ? updated : ad
            ),
          };
        }
        return alumno;
      });
      setMonthlyDetail({ ...monthlyDetail, alumnos: updatedAlumnos });
    } catch {
      toast.error("No se pudo actualizar la asistencia");
    }
  };

  const debouncedActualizarObservacion = useMemo(
    () => debounce(async (alumnoId: number, obs: string) => {
      if (!canRegister || !monthlyDetail) return;
      const alumno = monthlyDetail.alumnos.find((a) => a.id === alumnoId);
      if (!alumno) return;
      const payload = {
        asistenciasAlumnoMensual: [
          { id: alumno.id, observacion: obs, asistenciasDiarias: [] },
        ],
      };
      try {
        await asistenciasApi.actualizarAsistenciaMensual(
          monthlyDetail.id,
          payload
        );
      } catch {
        toast.error("No se pudo guardar la observación");
      }
    }, 500),
    [canRegister, monthlyDetail]
  );

  const handleObservacionChange = (alumnoId: number, newObs: string) => {
    if (monthlyDetail) {
      const updatedAlumnos = monthlyDetail.alumnos.map((alumno) => {
        if (alumno.id === alumnoId) {
          return { ...alumno, observacion: newObs };
        }
        return alumno;
      });
      setMonthlyDetail({ ...monthlyDetail, alumnos: updatedAlumnos });
    }
    debouncedActualizarObservacion(alumnoId, newObs);
  };

  const formatHeaderDate = (date: Date): string => {
    const weekday = date
      .toLocaleDateString("es-ES", { weekday: "short" })
      .replace(".", "");
    const day = date.toLocaleDateString("es-ES", { day: "numeric" });
    return `${weekday} ${day}`;
  };

  return (
    <div className="page-container">
      <PageHeader
        eyebrow="Gestión académica"
        title="Asistencia diaria"
        description="Elegí una disciplina y una fecha para registrar la asistencia del grupo."
        actions={<Boton onClick={() => navigate("/asistencias-mensuales")} className="page-button-secondary">Volver</Boton>}
      />

      <SectionCard title="Seleccionar clase" description="La fecha debe corresponder a un día de cursada de la disciplina.">
        <div className="grid gap-4 lg:grid-cols-[minmax(16rem,1fr)_minmax(12rem,0.55fr)_auto] lg:items-end">
          <div className="field-group" ref={searchWrapperRef}>
            <label htmlFor="searchDiscipline">Disciplina</label>
            <div className="relative">
              <Input
                id="searchDiscipline"
                placeholder="Buscar disciplina"
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
                <ul className="absolute z-20 mt-1 max-h-64 w-full overflow-y-auto rounded-xl border border-border bg-popover p-1 text-popover-foreground shadow-lg" role="listbox">
                  {filteredDisciplinas.map((disciplina, index) => (
                    <li
                      key={disciplina.id}
                      onClick={() => handleSeleccionarDisciplina(disciplina)}
                      onMouseEnter={() => setActiveSuggestionIndex(index)}
                      className={`cursor-pointer rounded-lg px-3 py-2 text-sm ${index === activeSuggestionIndex ? "bg-accent text-accent-foreground" : ""}`}
                      role="option"
                      aria-selected={index === activeSuggestionIndex}
                    >
                      {disciplina.nombre}
                    </li>
                  ))}
                </ul>
              )}
            </div>
            {selectedDisciplineId && (
              <Button onClick={limpiarDisciplina} variant="outline" size="sm" className="mt-1 w-fit">Limpiar</Button>
            )}
          </div>

          <div className="field-group">
            <label htmlFor="datePicker">Fecha</label>
            <DatePicker
              id="datePicker"
              selected={selectedDate}
              onChange={(date: Date | null) => date && setSelectedDate(new Date(date))}
              dateFormat="dd/MM/yyyy"
              className="form-input w-full"
            />
          </div>

          <Boton onClick={handleBuscarAsistencia} disabled={!selectedDisciplineId}>Buscar asistencia</Boton>
        </div>
      </SectionCard>

      {!loading && selectedDisciplineId && selectedDate && !isValidClassDay && (
        <EmptyState title="No hay clase ese día" message="Probá otra fecha programada para la disciplina seleccionada." />
      )}
      {loading && <LoadingState message="Cargando asistencia..." />}
      {error && <ErrorState message={error} />}

      {monthlyDetail && dailyRecords.length > 0 && (
        <SectionCard title="Lista de asistencia" description={`${dailyRecords.length} alumnos · ${formatHeaderDate(selectedDate)}`} className="p-0 [&_.section-card-header]:m-0 [&_.section-card-header]:p-5">
          <div className="data-table-scroll">
            <Table key={selectedDate.toISOString()} className="data-table">
              <TableHeader>
                <TableRow>
                  <TableHead>Alumno</TableHead>
                  <TableHead className="text-center">{formatHeaderDate(selectedDate)}</TableHead>
                  <TableHead>Observación</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {dailyRecords.map((record) => (
                  <TableRow key={record.alumnoId}>
                    <TableCell className="font-semibold">{`${record.alumnoApellido}, ${record.alumnoNombre}`}</TableCell>
                    <TableCell className="text-center">
                      {canRegister ? (
                        <Button
                          size="sm"
                          variant={record.asistenciaDiaria?.estado === EstadoAsistencia.PRESENTE ? "default" : "outline"}
                          onClick={() => toggleAsistencia(record.alumnoId, record.asistenciaDiaria)}
                          aria-label={`${record.asistenciaDiaria?.estado === EstadoAsistencia.PRESENTE ? "Marcar ausente" : "Marcar presente"} a ${record.alumnoNombre} ${record.alumnoApellido}`}
                        >
                          {record.asistenciaDiaria?.estado === EstadoAsistencia.PRESENTE ? <Check className="size-4" /> : <X className="size-4" />}
                        </Button>
                      ) : (
                        <span aria-label={record.asistenciaDiaria?.estado === EstadoAsistencia.PRESENTE ? "Presente" : "Ausente"}>
                          {record.asistenciaDiaria?.estado === EstadoAsistencia.PRESENTE ? <Check className="mx-auto size-4" /> : <X className="mx-auto size-4" />}
                        </span>
                      )}
                    </TableCell>
                    <TableCell>
                      <Input
                        className="form-input"
                        placeholder="Agregar observación"
                        value={monthlyDetail.alumnos.find((a) => a.id === record.alumnoId)?.observacion || ""}
                        onChange={(e) => handleObservacionChange(record.alumnoId, e.target.value)}
                        readOnly={!canRegister}
                      />
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </div>
        </SectionCard>
      )}

      {monthlyDetail && dailyRecords.length === 0 && <EmptyState title="Sin alumnos para registrar" message="La disciplina no tiene alumnos disponibles para esta fecha." />}
      {!monthlyDetail && !loading && !error && !selectedDisciplineId && <EmptyState title="Prepará la asistencia" message="Seleccioná una disciplina y una fecha para comenzar." />}
    </div>
  );
};

export default AsistenciaDiariaFormAdaptado;
