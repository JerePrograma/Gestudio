import type { ReactNode } from "react";
import { cn } from "../../lib/utils";

interface SectionCardProps {
  title?: string;
  description?: string;
  actions?: ReactNode;
  children: ReactNode;
  className?: string;
}

const SectionCard = ({ title, description, actions, children, className }: SectionCardProps) => (
  <section className={cn("section-card", className)}>
    {(title || description || actions) && (
      <div className="section-card-header">
        <div>
          {title && <h2 className="section-card-title">{title}</h2>}
          {description && <p className="section-card-description">{description}</p>}
        </div>
        {actions}
      </div>
    )}
    {children}
  </section>
);

export default SectionCard;
