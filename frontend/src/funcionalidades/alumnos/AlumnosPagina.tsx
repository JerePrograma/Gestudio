import { useState } from "react";
import { keepPreviousData, useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { CreditCard, Pencil, PlusCircle, Trash2 } from "lucide-react";
import { useNavigate } from "react-router-dom";
import { toast } from "react-toastify";
import alumnosApi from "../../api/alumnosApi";
import { getApiErrorMessage } from "../../api/apiError";
import Boton from "../../componentes/comunes/Boton";
import ErrorState from "../../componentes/comunes/ErrorState";
import FilterBar from "../../componentes/comunes/FilterBar";
import LoadingState from "../../componentes/comunes/LoadingState";
import PageHeader from "../../componentes/comunes/PageHeader";
import PaginationControls from "../../componentes/comunes/PaginationControls";
import PermissionGate from "../../componentes/comunes/PermissionGate";
import RowActions from "../../componentes/comunes/RowActions";
import SearchInput from "../../componentes/comunes/SearchInput";
import StatusBadge from "../../componentes/comunes/StatusBadge";
import Tabla from "../../componentes/comunes/Tabla";
import { queryKeys } from "../../hooks/queryKeys";
import { PERMISSIONS } from "../../config/permissions";

const PAGE_SIZE = 50;

const AlumnosPagina = () => {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [page, setPage] = useState(0);
  const [search, setSearch] = useState("");

  const alumnos = useQuery({
    queryKey: queryKeys.alumnos(page, PAGE_SIZE, search),
    queryFn: () => search.trim()
      ? alumnosApi.buscarPorNombre(search.trim(), page, PAGE_SIZE)
      : alumnosApi.listar(page, PAGE_SIZE),
    placeholderData: keepPreviousData,
  });

  const baja = useMutation({
    mutationFn: (id: number) => alumnosApi.darBaja(id),
    onSuccess: async () => {
      await queryClient.invalidateQueries({ queryKey: queryKeys.all.alumnos });
      toast.success("Alumno dado de baja.");
    },
    onError: (error) => toast.error(getApiErrorMessage(error, "No se pudo dar de baja el alumno.")),
  });

  const confirmarBaja = (id: number, nombre: string) => {
    if (window.confirm(`¿Dar de baja a ${nombre}?`)) baja.mutate(id);
  };

  if (alumnos.isLoading) return <LoadingState message="Cargando alumnos..." />;

  if (alumnos.isError) {
    return <ErrorState message="No se pudieron cargar alumnos." onRetry={() => void alumnos.refetch()} />;
  }

  return (
    <div className="page-container">
      <PageHeader
        eyebrow="Gestión académica"
        title="Alumnos"
        description="Consultá perfiles, estado y accesos rápidos de cada alumno."
        count={alumnos.data?.totalElements ?? 0}
        actions={(
          <PermissionGate permission={PERMISSIONS.ALUMNOS_ADMIN}>
            <Boton onClick={() => navigate("/alumnos/formulario")} className="page-button">
              <PlusCircle className="size-4" /> Nuevo alumno
            </Boton>
          </PermissionGate>
        )}
      />

      <FilterBar label="Buscar alumnos">
        <SearchInput
          id="buscar-alumno"
          label="Buscar"
          placeholder="Buscar por nombre, apellido o documento"
          value={search}
          onChange={(event) => {
            setPage(0);
            setSearch(event.target.value);
          }}
        />
      </FilterBar>

      <div>
        <Tabla
          headers={["Alumno", "Documento", "Contacto", "Estado"]}
          data={alumnos.data?.content ?? []}
          getRowKey={(row) => row.id}
          emptyMessage="No hay alumnos para mostrar."
          customRender={(row) => {
            const nombreCompleto = `${row.nombre} ${row.apellido}`.trim();
            const contacto = row.celular1 || row.celular2 || row.email || "Sin contacto";

            return [
              <div key="alumno" className="min-w-0">
                <p className="font-semibold">{nombreCompleto}</p>
                {row.nombrePadres && (
                  <p className="mt-1 truncate text-xs text-muted-foreground">
                    Familia/responsable: {row.nombrePadres}
                  </p>
                )}
              </div>,
              row.documento || "Sin documento",
              <span key="contacto" className="text-sm">
                {contacto}
              </span>,
              <StatusBadge key="estado" tone={row.activo ? "success" : "neutral"}>
                {row.activo ? "Activo" : "Baja"}
              </StatusBadge>,
            ];
          }}
          actions={(row) => {
            const nombreCompleto = `${row.nombre} ${row.apellido}`.trim();

            return (
              <RowActions
                label={`Acciones de ${nombreCompleto}`}
                actions={[
                  { label: "Editar", icon: Pencil, requiredPermission: PERMISSIONS.ALUMNOS_ADMIN, onSelect: () => navigate(`/alumnos/formulario?id=${row.id}`) },
                  { label: "Ver pagos", icon: CreditCard, requiredPermission: PERMISSIONS.PAGOS_LEER, onSelect: () => navigate(`/pagos?alumnoId=${row.id}`) },
                  ...(row.activo
                    ? [{
                        label: "Dar de baja",
                        icon: Trash2,
                        requiredPermission: PERMISSIONS.ALUMNOS_ADMIN,
                        destructive: true,
                        disabled: baja.isPending,
                        onSelect: () => confirmarBaja(row.id, nombreCompleto),
                      }]
                    : []),
                ]}
              />
            );
          }}
        />
      </div>

      <PaginationControls
        page={page}
        totalPages={alumnos.data?.totalPages ?? 0}
        onPageChange={setPage}
        disabled={alumnos.isFetching}
      />
    </div>
  );
};

export default AlumnosPagina;
