import type { ReactNode } from "react";
import { PERMISSIONS, type PermissionCode } from "../../config/permissions";
import { useAuth } from "../../hooks/context/useAuth";

interface PermissionGateProps {
  permission: PermissionCode;
  children: ReactNode;
}

const PermissionGate = ({ permission, children }: PermissionGateProps) => {
  const { hasPermission } = useAuth();

  return hasPermission(PERMISSIONS.APP_ACCESS) && hasPermission(permission)
    ? children
    : null;
};

export default PermissionGate;
