import { CircleAlert } from "lucide-react";

interface ErrorStateProps {
  message: string;
  onRetry?: () => void;
}

const ErrorState = ({ message, onRetry }: ErrorStateProps) => (
  <div className="state-panel" role="alert">
    <span className="state-icon bg-destructive/10 text-destructive"><CircleAlert className="size-5" aria-hidden="true" /></span>
    <h2 className="state-title">No pudimos completar la carga</h2>
    <p className="state-message">{message}</p>
    {onRetry && (
      <button type="button" className="page-button-secondary mt-4" onClick={onRetry}>
        Reintentar
      </button>
    )}
  </div>
);

export default ErrorState;
