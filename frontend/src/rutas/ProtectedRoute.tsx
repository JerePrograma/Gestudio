import { Navigate, Outlet } from "react-router-dom";
import LoadingState from "../componentes/comunes/LoadingState";
import { useAuth } from "../hooks/context/useAuth";
import type { ReactNode } from "react";
import type { PermissionCode } from "../config/permissions";

interface ProtectedRouteProps {
  redirectPath?: string;
  unauthorizedPath?: string;

  requiredPermission?: PermissionCode;
  requiredPermissions?: readonly PermissionCode[];
  requiredAnyPermission?: readonly PermissionCode[];

  children?: ReactNode;
}

const ProtectedRoute = ({
  redirectPath = "/login",
  unauthorizedPath = "/unauthorized",
  requiredPermission,
  requiredPermissions,
  requiredAnyPermission,
  children,
}: ProtectedRouteProps) => {
  const {
    isAuth,
    loading,
    user,
    hasPermission,
    hasAllPermissions,
    hasAnyPermission,
  } = useAuth();

  if (loading || (isAuth && !user)) {
    return <LoadingState message="Cargando perfil..." />;
  }

  if (!isAuth) {
    return <Navigate to={redirectPath} replace />;
  }

  if (requiredPermission && !hasPermission(requiredPermission)) {
    return <Navigate to={unauthorizedPath} replace />;
  }

  if (requiredPermissions && requiredPermissions.length > 0 && !hasAllPermissions(requiredPermissions)) {
    return <Navigate to={unauthorizedPath} replace />;
  }

  if (requiredAnyPermission && requiredAnyPermission.length > 0 && !hasAnyPermission(requiredAnyPermission)) {
    return <Navigate to={unauthorizedPath} replace />;
  }

  return children ?? <Outlet />;
};

export default ProtectedRoute;
