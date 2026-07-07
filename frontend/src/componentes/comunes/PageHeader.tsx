import type { ReactNode } from "react";

interface PageHeaderProps {
  title: string;
  description?: string;
  eyebrow?: string;
  count?: number;
  actions?: ReactNode;
}

const PageHeader = ({ title, description, eyebrow, count, actions }: PageHeaderProps) => (
  <header className="page-header">
    <div className="page-heading">
      {eyebrow && <p className="page-eyebrow">{eyebrow}</p>}
      <h1 className="page-title">{title}</h1>
      {description && <p className="page-description">{description}</p>}
      {typeof count === "number" && (
        <p className="record-count">{count} {count === 1 ? "registro" : "registros"}</p>
      )}
    </div>
    {actions && <div className="page-actions">{actions}</div>}
  </header>
);

export default PageHeader;
