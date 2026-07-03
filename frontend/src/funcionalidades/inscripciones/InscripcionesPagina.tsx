import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { BadgePercent, Pencil, PlusCircle } from "lucide-react";
import { useNavigate } from "react-router-dom";
import inscripcionesApi from "../../api/inscripcionesApi";
import Boton from "../../componentes/comunes/Boton";
import Tabla from "../../componentes/comunes/Tabla";
import { queryKeys } from "../../hooks/queryKeys";

const PAGE_SIZE = 50;

const InscripcionesPagina = () => {
  const navigate = useNavigate();
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(0);
  const { data, isLoading, isError } = useQuery({
    queryKey: queryKeys.inscripciones(page, PAGE_SIZE, search),
    queryFn: () => inscripcionesApi.listar(page, PAGE_SIZE, search.trim()),
  });
  const rows = data?.content ?? [];

  if (isLoading) return <div className="text-center py-4">Cargando...</div>;
  if (isError) return <div className="text-center py-4 text-destructive">No se pudieron cargar las inscripciones.</div>;

  return (
    <div className="container mx-auto p-6 space-y-6">
      <div className="flex items-center justify-between">
        <div><h1 className="text-3xl font-bold tracking-tight">Inscripciones</h1><p className="text-sm text-gray-600">{data?.totalElements ?? 0} registros</p></div>
        <Boton onClick={() => navigate("/inscripciones/formulario")} className="page-button"><PlusCircle className="w-4 h-4" /> Nueva</Boton>
      </div>
      <input className="form-input max-w-md" placeholder="Buscar alumno o disciplina" value={search} onChange={(event) => { setPage(0); setSearch(event.target.value); }} />
      <div className="page-card overflow-x-auto">
        <Tabla
          headers={["ID", "Alumno", "Disciplina", "Fecha", "Estado", "Costo particular"]}
          data={rows}
          customRender={(row) => [row.id, row.alumno, row.disciplina, row.fechaInscripcion, row.estado, row.costoParticular ?? "-"]}
          actions={(row) => <div className="flex gap-2"><Boton onClick={() => navigate(`/inscripciones/${row.id}/condiciones-economicas`)} className="page-button-secondary"><BadgePercent className="w-4 h-4" /> Condiciones</Boton><Boton onClick={() => navigate(`/inscripciones/formulario?id=${row.id}`)} className="page-button-secondary"><Pencil className="w-4 h-4" /> Editar</Boton></div>}
        />
      </div>
      <div><Boton disabled={page === 0} onClick={() => setPage((value) => value - 1)} className="page-button-secondary">Anterior</Boton><span> Página {page + 1} de {Math.max(data?.totalPages ?? 1, 1)} </span><Boton disabled={!data || page + 1 >= data.totalPages} onClick={() => setPage((value) => value + 1)} className="page-button-secondary">Siguiente</Boton></div>
    </div>
  );
};

export default InscripcionesPagina;
