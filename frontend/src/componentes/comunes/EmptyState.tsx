import { Inbox } from "lucide-react";
import type { ReactNode } from "react";

interface EmptyStateProps {
  message?: string;
  title?: string;
  action?: ReactNode;
}

const EmptyState = ({ title = "Todavía no hay información", message = "No hay datos disponibles.", action }: EmptyStateProps) => (
  <div className="state-panel" role="status">
    <span className="state-icon"><Inbox className="size-5" aria-hidden="true" /></span>
    <h2 className="state-title">{title}</h2>
    <p className="state-message">{message}</p>
    {action && <div className="mt-5">{action}</div>}
  </div>
);

export default EmptyState;
