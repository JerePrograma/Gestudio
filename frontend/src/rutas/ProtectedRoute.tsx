import { Navigate, Outlet } from "react-router-dom";
import LoadingState from "../componentes/comunes/LoadingState";
import { useAuth } from "../hooks/context/useAuth";

interface ProtectedRouteProps {
  redirectPath?: string;
  requiredRole?: string;
}

const ProtectedRoute = ({
  redirectPath = "/login",
  requiredRole,
}: ProtectedRouteProps) => {
  const { isAuth, loading, user, hasRole } = useAuth();

  if (loading || (isAuth && !user)) {
    return <LoadingState message="Cargando perfil..." />;
  }

  if (!isAuth) {
    return <Navigate to={redirectPath} replace />;
  }

  if (requiredRole && !hasRole(requiredRole)) {
    return <Navigate to="/unauthorized" replace />;
  }

  return <Outlet />;
};

export default ProtectedRoute;
