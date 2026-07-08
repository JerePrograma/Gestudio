import { Navigate, Outlet } from "react-router-dom";
import LoadingState from "../componentes/comunes/LoadingState";
import { useAuth } from "../hooks/context/useAuth";
import type { ReactNode } from "react";

interface ProtectedRouteProps {
  redirectPath?: string;
  requiredRole?: string;
  requiredPermission?: string;
  children?: ReactNode;
}

const ProtectedRoute = ({
  redirectPath = "/login",
  requiredRole,
  requiredPermission,
  children,
}: ProtectedRouteProps) => {
  const { isAuth, loading, user, hasRole, hasPermission } = useAuth();

  if (loading || (isAuth && !user)) {
    return <LoadingState message="Cargando perfil..." />;
  }

  if (!isAuth) {
    return <Navigate to={redirectPath} replace />;
  }

  if (requiredRole && !hasRole(requiredRole)) {
    return <Navigate to="/unauthorized" replace />;
  }

  if (requiredPermission && !hasPermission(requiredPermission)) {
    return <Navigate to="/unauthorized" replace />;
  }

  return children ?? <Outlet />;
};

export default ProtectedRoute;
