"use client"

import { useEffect, useState, useCallback, useMemo } from "react"
import { useNavigate } from "react-router-dom"
import Tabla from "../../componentes/comunes/Tabla"
import profesoresApi from "../../api/profesoresApi"
import Boton from "../../componentes/comunes/Boton"
import { PlusCircle, Pencil, Trash2 } from "lucide-react"
import type { ProfesorListadoResponse } from "../../types/types"
import { toast } from "react-toastify"
import ListaConCargaManual from "../../componentes/comunes/ListaConCargaManual"
import ErrorState from "../../componentes/comunes/ErrorState"
import FilterBar from "../../componentes/comunes/FilterBar"
import LoadingState from "../../componentes/comunes/LoadingState"
import PageHeader from "../../componentes/comunes/PageHeader"
import RowActions from "../../componentes/comunes/RowActions"
import SearchInput from "../../componentes/comunes/SearchInput"
import StatusBadge from "../../componentes/comunes/StatusBadge"

const itemsPerPage = 25

const Profesores = () => {
  const [profesores, setProfesores] = useState<ProfesorListadoResponse[]>([])
  const [visibleCount, setVisibleCount] = useState(itemsPerPage)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  // Estados para búsqueda y orden
  const [searchTerm, setSearchTerm] = useState("")
  const [sortOrder, setSortOrder] = useState<"asc" | "desc">("asc")
  const navigate = useNavigate()

  const fetchProfesores = useCallback(async () => {
    try {
      setLoading(true)
      setError(null)
      const response = await profesoresApi.listarProfesoresActivos()
      setProfesores(response)
    } catch {
      toast.error("Error al cargar profesores:")
      setError("Error al cargar profesores.")
    } finally {
      setLoading(false)
    }
  }, [])

  useEffect(() => {
    fetchProfesores()
  }, [fetchProfesores])

  // Filtrar y ordenar profesores
  const profesoresFiltradosYOrdenados = useMemo(() => {
    const filtrados = profesores.filter((profesor) => {
      const nombreCompleto = `${profesor.nombre} ${profesor.apellido}`.toLowerCase()
      return nombreCompleto.includes(searchTerm.toLowerCase())
    })
    return filtrados.sort((a, b) => {
      const nombreA = `${a.nombre} ${a.apellido}`.toLowerCase()
      const nombreB = `${b.nombre} ${b.apellido}`.toLowerCase()
      if (sortOrder === "asc") return nombreA.localeCompare(nombreB)
      return nombreB.localeCompare(nombreA)
    })
  }, [profesores, searchTerm, sortOrder])

  // Subconjunto de profesores a mostrar
  const currentItems = useMemo(
    () => profesoresFiltradosYOrdenados.slice(0, visibleCount),
    [profesoresFiltradosYOrdenados, visibleCount],
  )

  // Determina si hay más elementos para cargar
  const hasMore = useMemo(() => visibleCount < profesoresFiltradosYOrdenados.length, [
    visibleCount,
    profesoresFiltradosYOrdenados.length,
  ])

  // Función para cargar más elementos
  const onLoadMore = useCallback(() => {
    if (hasMore) {
      setVisibleCount((prev) => prev + itemsPerPage)
    }
  }, [hasMore])

  // Opciones únicas para el datalist (nombres completos)
  const nombresUnicos = useMemo(() => {
    const nombresSet = new Set(
      profesores.map((profesor) => `${profesor.nombre} ${profesor.apellido}`),
    )
    return Array.from(nombresSet)
  }, [profesores])

  // Reinicia la cantidad visible al cambiar el filtro de búsqueda
  const handleSearchChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    setSearchTerm(e.target.value)
    setVisibleCount(itemsPerPage)
  }

  const handleEliminarProfesor = async (id: number) => {
    try {
      await profesoresApi.eliminarProfesor(id)
      toast.success("Profesor eliminado correctamente.")
      fetchProfesores()
    } catch {
      toast.error("Error al eliminar el profesor.")
    }
  }

  if (loading && profesores.length === 0)
    return <LoadingState message="Cargando profesores..." />
  if (error) return <ErrorState message={error} onRetry={() => void fetchProfesores()} />

  return (
    <div className="page-container">
      <PageHeader eyebrow="Gestión académica" title="Profesores" description="Equipo docente, estado y datos de contacto." count={profesoresFiltradosYOrdenados.length}
        actions={<Boton
          onClick={() => navigate("/profesores/formulario")}
          className="page-button"
          aria-label="Registrar nuevo profesor"
        >
          <PlusCircle className="size-4" /> Nuevo profesor
        </Boton>} />

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
        <label className="field-group sm:w-52" htmlFor="sortOrder">Orden
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
          headers={["ID", "Nombre", "Apellido", "Estado"]}
          data={currentItems}
          getRowKey={(row) => row.id}
          customRender={(fila) => [
            fila.id,
            fila.nombre,
            fila.apellido,
            <StatusBadge key="estado" tone={fila.activo ? "success" : "neutral"}>{fila.activo ? "Activo" : "Baja"}</StatusBadge>,
          ]}
          actions={(fila) => (
            <RowActions label={`Acciones de ${fila.nombre} ${fila.apellido}`} actions={[
              { label: "Editar", icon: Pencil, onSelect: () => navigate(`/profesores/formulario?id=${fila.id}`) },
              { label: "Eliminar", icon: Trash2, destructive: true, onSelect: () => void handleEliminarProfesor(fila.id) },
            ]} />
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
              {loading && <div className="text-center py-2">Cargando más...</div>}
            </ListaConCargaManual>
          </div>
        )}
      </div>
    </div>
  )
}

export default Profesores
