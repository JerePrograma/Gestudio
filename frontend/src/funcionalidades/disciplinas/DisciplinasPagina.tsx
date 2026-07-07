import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { BadgeDollarSign, Pencil, PlusCircle, Trash2 } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { toast } from "react-toastify";
import { getApiErrorMessage } from "../../api/apiError";
import disciplinasApi from "../../api/disciplinasApi";
import Boton from "../../componentes/comunes/Boton";
import ErrorState from "../../componentes/comunes/ErrorState";
import ListaConCargaManual from "../../componentes/comunes/ListaConCargaManual";
import LoadingState from "../../componentes/comunes/LoadingState";
import Tabla from "../../componentes/comunes/Tabla";
import { queryKeys } from "../../hooks/queryKeys";

const PAGE_SIZE = 25;

const DisciplinasPagina = () => {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const [sortOrder, setSortOrder] = useState<"asc" | "desc">("asc");
  const [visibleCount, setVisibleCount] = useState(PAGE_SIZE);
  const disciplinas = useQuery({ queryKey: queryKeys.disciplinas, queryFn: disciplinasApi.listarDisciplinas });
  const baja = useMutation({
    mutationFn: (id: number) => disciplinasApi.darBajaDisciplina(id),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.all.disciplinas });
      toast.success("Disciplina dada de baja.");
    },
    onError: (error) => toast.error(getApiErrorMessage(error, "No se pudo dar de baja la disciplina.")),
  });
  const filtered = useMemo(() => [...(disciplinas.data ?? [])]
    .filter((item) => item.nombre.toLocaleLowerCase().includes(search.trim().toLocaleLowerCase()))
    .sort((left, right) => sortOrder === "asc"
      ? left.nombre.localeCompare(right.nombre)
      : right.nombre.localeCompare(left.nombre)), [disciplinas.data, search, sortOrder]);
  const visible = filtered.slice(0, visibleCount);

  if (disciplinas.isLoading) return <LoadingState message="Cargando disciplinas..." />;
  if (disciplinas.isError) return <ErrorState message="No se pudieron cargar las disciplinas." onRetry={() => void disciplinas.refetch()} />;

  return (
    <div className="page-container space-y-6">
      <div className="flex items-center justify-between gap-4">
        <h1 className="page-title">Disciplinas</h1>
        <Boton onClick={() => navigate("/disciplinas/formulario")} className="page-button"><PlusCircle className="w-5 h-5" /> Nueva disciplina</Boton>
      </div>
      <div className="flex flex-col sm:flex-row gap-4">
        <label className="auth-label" htmlFor="disciplina-search">Buscar<input id="disciplina-search" className="form-input" value={search} onChange={(event) => { setSearch(event.target.value); setVisibleCount(PAGE_SIZE); }} /></label>
        <label className="auth-label" htmlFor="disciplina-order">Orden<select id="disciplina-order" className="form-input" value={sortOrder} onChange={(event) => setSortOrder(event.target.value as "asc" | "desc")}><option value="asc">Ascendente</option><option value="desc">Descendente</option></select></label>
      </div>
      <div className="page-card">
        <Tabla
          headers={["ID", "Nombre", "Horarios", "Estado"]}
          data={visible}
          getRowKey={(row) => row.id}
          customRender={(row) => [row.id, row.nombre, row.horarios.map((horario) => `${horario.diaSemana} ${horario.horarioInicio}`).join(", ") || "Sin horarios", row.activo ? "Activa" : "Baja"]}
          actions={(row) => <div className="flex flex-wrap gap-2"><Boton onClick={() => navigate(`/disciplinas/${row.id}/tarifas`)} className="page-button-secondary"><BadgeDollarSign className="w-4 h-4" /> Tarifas</Boton><Boton onClick={() => navigate(`/disciplinas/formulario?id=${row.id}`)} className="page-button-secondary"><Pencil className="w-4 h-4" /> Editar</Boton>{row.activo && <Boton disabled={baja.isPending} onClick={() => window.confirm(`¿Dar de baja ${row.nombre}?`) && baja.mutate(row.id)} className="page-button-danger"><Trash2 className="w-4 h-4" /> Baja</Boton>}</div>}
        />
        <ListaConCargaManual onLoadMore={() => setVisibleCount((count) => count + PAGE_SIZE)} hasMore={visibleCount < filtered.length} loading={false}>
          <span className="sr-only">{visible.length} disciplinas visibles</span>
        </ListaConCargaManual>
      </div>
    </div>
  );
};

export default DisciplinasPagina;
