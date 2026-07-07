import { cn } from "../../lib/utils";

type StatusTone = "success" | "warning" | "danger" | "info" | "neutral";

interface StatusBadgeProps {
  children: React.ReactNode;
  tone?: StatusTone;
}

const StatusBadge = ({ children, tone = "neutral" }: StatusBadgeProps) => (
  <span className={cn("status-badge", `status-badge-${tone}`)}>{children}</span>
);

export default StatusBadge;
