import { MoreHorizontal, type LucideIcon } from "lucide-react";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "../ui/dropdown-menu";
import { PERMISSIONS, type PermissionCode } from "../../config/permissions";
import { useAuth } from "../../hooks/context/useAuth";

export interface RowAction {
  label: string;
  icon?: LucideIcon;
  onSelect: () => void;
  destructive?: boolean;
  disabled?: boolean;
  requiredPermission?: PermissionCode;
}

interface RowActionsProps {
  label?: string;
  actions: RowAction[];
}

const RowActions = ({ label = "Abrir acciones", actions }: RowActionsProps) => {
  const { hasPermission } = useAuth();
  const visibleActions = actions.filter(({ requiredPermission }) => !requiredPermission || (
    hasPermission(PERMISSIONS.APP_ACCESS) && hasPermission(requiredPermission)
  ));

  if (visibleActions.length === 0) return null;

  return <DropdownMenu>
    <DropdownMenuTrigger asChild>
      <button type="button" className="icon-button" aria-label={label}>
        <MoreHorizontal className="size-5" aria-hidden="true" />
      </button>
    </DropdownMenuTrigger>
    <DropdownMenuContent align="end" className="min-w-44 p-1.5">
      {visibleActions.map(({ label: actionLabel, icon: Icon, onSelect, destructive, disabled }) => (
        <DropdownMenuItem
          key={actionLabel}
          disabled={disabled}
          onSelect={onSelect}
          className={destructive ? "text-destructive focus:bg-destructive/10 focus:text-destructive" : ""}
        >
          {Icon && <Icon className="mr-2 size-4" aria-hidden="true" />}
          {actionLabel}
        </DropdownMenuItem>
      ))}
    </DropdownMenuContent>
  </DropdownMenu>;
};

export default RowActions;
