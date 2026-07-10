import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { BadgePercent, Pencil, PlusCircle } from "lucide-react";
import { useNavigate } from "react-router-dom";
import inscripcionesApi from "../../api/inscripcionesApi";
import Boton from "../../componentes/comunes/Boton";
import ErrorState from "../../componentes/comunes/ErrorState";
import FilterBar from "../../componentes/comunes/FilterBar";
import LoadingState from "../../componentes/comunes/LoadingState";
import PageHeader from "../../componentes/comunes/PageHeader";
import PaginationControls from "../../componentes/comunes/PaginationControls";
import RowActions from "../../componentes/comunes/RowActions";
import SearchInput from "../../componentes/comunes/SearchInput";
import StatusBadge from "../../componentes/comunes/StatusBadge";
import Tabla from "../../componentes/comunes/Tabla";
import { queryKeys } from "../../hooks/queryKeys";
import { formatMoney } from "../../utils/money";

const PAGE_SIZE = 50;

const InscripcionesPagina = () => {
  const navigate = useNavigate();
  const [search, setSearch] = useState("");
  const [page, setPage] = useState(0);

  const inscripciones = useQuery({
    queryKey: queryKeys.inscripciones(page, PAGE_SIZE, search),
    queryFn: () => inscripcionesApi.listar(page, PAGE_SIZE, search.trim()),
  });

  if (inscripciones.isLoading) return <LoadingState message="Cargando inscripciones..." />;

  if (inscripciones.isError) {
    return (
      <ErrorState
        message="No se pudieron cargar las inscripciones."
        onRetry={() => void inscripciones.refetch()}
      />
    );
  }

  return (
    <div className="page-container">
      <PageHeader
        eyebrow="Gestión académica"
        title="Inscripciones"
        description="Seguimiento de altas, condiciones y estado de cursada."
        count={inscripciones.data?.totalElements ?? 0}
        actions={(
          <Boton onClick={() => navigate("/inscripciones/formulario")} className="page-button">
            <PlusCircle className="size-4" /> Nueva inscripción
          </Boton>
        )}
      />

      <FilterBar label="Buscar inscripciones">
        <SearchInput
          id="buscar-inscripcion"
          label="Buscar inscripción"
          placeholder="Buscar por alumno o disciplina"
          value={search}
          onChange={(event) => {
            setPage(0);
            setSearch(event.target.value);
          }}
        />
      </FilterBar>

      <div>
        <Tabla
          headers={["Alumno", "Disciplina", "Fecha", "Estado", "Costo particular"]}
          data={inscripciones.data?.content ?? []}
          getRowKey={(row) => row.id}
          customRender={(row) => [
            <span className="font-semibold" key="alumno">{row.alumno}</span>,
            row.disciplina,
            row.fechaInscripcion,
            <StatusBadge key="estado" tone={row.estado === "ACTIVA" ? "success" : "neutral"}>
              {row.estado}
            </StatusBadge>,
            <span className="numeric-cell block" key="costo">
              {row.costoParticular ? `$ ${formatMoney(row.costoParticular)}` : "—"}
            </span>,
          ]}
          actions={(row) => (
            <RowActions
              label={`Acciones de inscripción de ${row.alumno}`}
              actions={[
                {
                  label: "Condiciones",
                  icon: BadgePercent,
                  onSelect: () => navigate(`/inscripciones/${row.id}/condiciones-economicas`),
                },
                {
                  label: "Editar",
                  icon: Pencil,
                  onSelect: () => navigate(`/inscripciones/formulario?id=${row.id}`),
                },
              ]}
            />
          )}
        />
      </div>

      <PaginationControls
        page={page}
        totalPages={inscripciones.data?.totalPages ?? 0}
        onPageChange={setPage}
        disabled={inscripciones.isFetching}
      />
    </div>
  );
};

export default InscripcionesPagina;