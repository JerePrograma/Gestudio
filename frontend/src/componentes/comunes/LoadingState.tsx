interface LoadingStateProps {
  message?: string;
}

const LoadingState = ({ message = "Cargando..." }: LoadingStateProps) => (
  <div className="state-panel" role="status" aria-live="polite">
    <span className="state-icon"><span className="loading-spinner" aria-hidden="true" /></span>
    <p className="state-title">{message}</p>
    <p className="state-message">Esto puede demorar unos segundos.</p>
  </div>
);

export default LoadingState;
