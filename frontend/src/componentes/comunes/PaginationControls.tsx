import Boton from "./Boton";

interface PaginationControlsProps {
  page: number;
  totalPages: number;
  onPageChange: (page: number) => void;
  disabled?: boolean;
}

const PaginationControls = ({
  page,
  totalPages,
  onPageChange,
  disabled = false,
}: PaginationControlsProps) => {
  const safeTotalPages = Math.max(totalPages, 1);

  return (
    <nav className="pagination" aria-label="Paginación">
      <Boton
        type="button"
        disabled={disabled || page === 0}
        onClick={() => onPageChange(page - 1)}
        className="page-button-secondary"
      >
        Anterior
      </Boton>
      <span className="pagination-status" aria-live="polite">Página {page + 1} de {safeTotalPages}</span>
      <Boton
        type="button"
        disabled={disabled || page + 1 >= safeTotalPages}
        onClick={() => onPageChange(page + 1)}
        className="page-button-secondary"
      >
        Siguiente
      </Boton>
    </nav>
  );
};

export default PaginationControls;
