import { Navigate, Outlet } from "react-router-dom";
import LoadingState from "../componentes/comunes/LoadingState";
import { useAuth } from "../hooks/context/useAuth";
import type { ReactNode } from "react";

interface ProtectedRouteProps {
  redirectPath?: string;
  unauthorizedPath?: string;

  /**
   * Compatibilidad transicional.
   * Preferir requiredPermission / requiredPermissions / requiredAnyPermission.
   */
  requiredRole?: string;
  requiredAnyRole?: string[];

  requiredPermission?: string;
  requiredPermissions?: string[];
  requiredAnyPermission?: string[];

  children?: ReactNode;
}

const ProtectedRoute = ({
  redirectPath = "/login",
  unauthorizedPath = "/unauthorized",
  requiredRole,
  requiredAnyRole,
  requiredPermission,
  requiredPermissions,
  requiredAnyPermission,
  children,
}: ProtectedRouteProps) => {
  const {
    isAuth,
    loading,
    user,
    hasRole,
    hasAnyRole,
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

  if (requiredRole && !hasRole(requiredRole)) {
    return <Navigate to={unauthorizedPath} replace />;
  }

  if (requiredAnyRole && requiredAnyRole.length > 0 && !hasAnyRole(requiredAnyRole)) {
    return <Navigate to={unauthorizedPath} replace />;
  }

  return children ?? <Outlet />;
};

export default ProtectedRoute;