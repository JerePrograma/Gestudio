import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { BadgeDollarSign, Pencil, PlusCircle, Trash2 } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { toast } from "react-toastify";
import { getApiErrorMessage } from "../../api/apiError";
import disciplinasApi from "../../api/disciplinasApi";
import Boton from "../../componentes/comunes/Boton";
import ErrorState from "../../componentes/comunes/ErrorState";
import FilterBar from "../../componentes/comunes/FilterBar";
import ListaConCargaManual from "../../componentes/comunes/ListaConCargaManual";
import LoadingState from "../../componentes/comunes/LoadingState";
import PageHeader from "../../componentes/comunes/PageHeader";
import PermissionGate from "../../componentes/comunes/PermissionGate";
import RowActions from "../../componentes/comunes/RowActions";
import SearchInput from "../../componentes/comunes/SearchInput";
import StatusBadge from "../../componentes/comunes/StatusBadge";
import Tabla from "../../componentes/comunes/Tabla";
import { queryKeys } from "../../hooks/queryKeys";
import { PERMISSIONS } from "../../config/permissions";

const PAGE_SIZE = 25;

const DisciplinasPagina = () => {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [search, setSearch] = useState("");
  const [sortOrder, setSortOrder] = useState<"asc" | "desc">("asc");
  const [visibleCount, setVisibleCount] = useState(PAGE_SIZE);

  const disciplinas = useQuery({
    queryKey: queryKeys.disciplinas,
    queryFn: disciplinasApi.listarDisciplinas,
  });

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

  if (disciplinas.isError) {
    return (
      <ErrorState
        message="No se pudieron cargar las disciplinas."
        onRetry={() => void disciplinas.refetch()}
      />
    );
  }

  return (
    <div className="page-container">
      <PageHeader
        eyebrow="Gestión académica"
        title="Disciplinas"
        description="Cursos, horarios y estado de cursada disponibles."
        count={filtered.length}
        actions={(
          <PermissionGate permission={PERMISSIONS.DISCIPLINAS_ADMIN}>
            <Boton onClick={() => navigate("/disciplinas/formulario")} className="page-button">
              <PlusCircle className="size-4" /> Nueva disciplina
            </Boton>
          </PermissionGate>
        )}
      />

      <FilterBar label="Filtrar disciplinas">
        <SearchInput
          id="disciplina-search"
          label="Buscar"
          placeholder="Buscar por nombre"
          value={search}
          onChange={(event) => {
            setSearch(event.target.value);
            setVisibleCount(PAGE_SIZE);
          }}
        />

        <label className="field-group sm:w-52" htmlFor="disciplina-order">
          Orden
          <select
            id="disciplina-order"
            className="form-input"
            value={sortOrder}
            onChange={(event) => setSortOrder(event.target.value as "asc" | "desc")}
          >
            <option value="asc">Ascendente</option>
            <option value="desc">Descendente</option>
          </select>
        </label>
      </FilterBar>

      <div className="page-card">
        <Tabla
          headers={["Disciplina", "Horarios", "Estado"]}
          data={visible}
          getRowKey={(row) => row.id}
          customRender={(row) => [
            <span className="font-semibold" key="nombre">{row.nombre}</span>,
            row.horarios.map((horario) => `${horario.diaSemana} ${horario.horarioInicio}`).join(", ") || "Sin horarios",
            <StatusBadge key="estado" tone={row.activo ? "success" : "neutral"}>
              {row.activo ? "Activa" : "Baja"}
            </StatusBadge>,
          ]}
          actions={(row) => (
            <RowActions
              label={`Acciones de ${row.nombre}`}
              actions={[
                {
                  label: "Tarifas",
                  icon: BadgeDollarSign,
                  requiredPermission: PERMISSIONS.TARIFAS_ADMIN,
                  onSelect: () => navigate(`/disciplinas/${row.id}/tarifas`),
                },
                {
                  label: "Editar",
                  icon: Pencil,
                  requiredPermission: PERMISSIONS.DISCIPLINAS_ADMIN,
                  onSelect: () => navigate(`/disciplinas/formulario?id=${row.id}`),
                },
                ...(row.activo
                  ? [{
                      label: "Dar de baja",
                      icon: Trash2,
                      requiredPermission: PERMISSIONS.DISCIPLINAS_ADMIN,
                      destructive: true,
                      disabled: baja.isPending,
                      onSelect: () => window.confirm(`¿Dar de baja ${row.nombre}?`) && baja.mutate(row.id),
                    }]
                  : []),
              ]}
            />
          )}
        />

        <ListaConCargaManual
          onLoadMore={() => setVisibleCount((count) => count + PAGE_SIZE)}
          hasMore={visibleCount < filtered.length}
          loading={false}
        >
          <span className="sr-only">{visible.length} disciplinas visibles</span>
        </ListaConCargaManual>
      </div>
    </div>
  );
};

export default DisciplinasPagina;
