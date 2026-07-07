import type { ReactNode } from "react";

interface StatCardProps {
  label: string;
  value: ReactNode;
  detail?: string;
}

const StatCard = ({ label, value, detail }: StatCardProps) => (
  <article className="stat-card">
    <p className="stat-card-label">{label}</p>
    <p className="stat-card-value">{value}</p>
    {detail && <p className="stat-card-detail">{detail}</p>}
  </article>
);

export default StatCard;
