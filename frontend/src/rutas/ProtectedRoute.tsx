import { Navigate, Outlet } from "react-router";
import LoadingState from "../componentes/comunes/LoadingState";
import { useAuth } from "../hooks/context/useAuth";
import type { ReactNode } from "react";
import type { PermissionCode } from "../config/permissions";
import type { SessionScope } from "../hooks/context/auth-context";

interface ProtectedRouteProps {
  redirectPath?: string;
  unauthorizedPath?: string;
  requiredScope?: SessionScope;
  requiredAuthority?: string;

  requiredPermission?: PermissionCode;
  requiredPermissions?: readonly PermissionCode[];
  requiredAnyPermission?: readonly PermissionCode[];

  children?: ReactNode;
}

const ProtectedRoute = ({
  redirectPath,
  unauthorizedPath = "/unauthorized",
  requiredScope,
  requiredAuthority,
  requiredPermission,
  requiredPermissions,
  requiredAnyPermission,
  children,
}: ProtectedRouteProps) => {
  const {
    isAuth,
    loading,
    scope,
    user,
    platformUser,
    hasPermission,
    hasAllPermissions,
    hasAnyPermission,
  } = useAuth();

  if (
    loading ||
    (isAuth && scope === "TENANT" && !user) ||
    (isAuth && scope === "PLATFORM" && !platformUser)
  ) {
    return <LoadingState message="Cargando perfil..." />;
  }

  if (!isAuth) {
    return <Navigate to={redirectPath ?? (requiredScope === "PLATFORM" ? "/platform/login" : "/login")} replace />;
  }

  if (requiredScope && scope !== requiredScope) {
    return <Navigate to={scope === "PLATFORM" ? "/platform/tenants" : "/"} replace />;
  }

  if (requiredAuthority && !platformUser?.authorities.includes(requiredAuthority)) {
    return <Navigate to={unauthorizedPath} replace />;
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
