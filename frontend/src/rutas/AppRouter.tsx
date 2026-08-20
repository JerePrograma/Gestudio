import { Suspense } from "react";
import { Navigate, Route, Routes } from "react-router";
import LoadingState from "../componentes/comunes/LoadingState";
import MainLayout from "../componentes/layout/MainLayout";
import PlatformLayout from "../platform/PlatformLayout";
import ProtectedRoute from "./ProtectedRoute";
import {
  adminRoutes,
  otherProtectedRoutes,
  platformRoutes,
  protectedRoutes,
  publicRoutes,
  permissionsForRoute,
} from "./routes";

const AppRouter = () => (
  <Suspense fallback={<LoadingState message="Cargando pantalla..." />}>
    <Routes>
      {publicRoutes.map(({ path, Component }) => (
        <Route key={path} path={path} element={<Component />} />
      ))}

      <Route element={<ProtectedRoute requiredScope="TENANT" />}>
        <Route element={<MainLayout />}>
          {[...protectedRoutes, ...adminRoutes, ...otherProtectedRoutes].map(
            ({ path, Component }) => (
              <Route
                key={path}
                path={path}
                element={
                  <ProtectedRoute requiredPermissions={permissionsForRoute(path)}>
                    <Component />
                  </ProtectedRoute>
                }
              />
            ),
          )}
        </Route>
      </Route>

      <Route element={<ProtectedRoute requiredScope="PLATFORM" requiredAuthority="PLATFORM_SUPERADMIN" />}>
        <Route element={<PlatformLayout />}>
          {platformRoutes.map(({ path, Component }) => (
            <Route key={path} path={path} element={<Component />} />
          ))}
        </Route>
      </Route>

      <Route path="/platform" element={<Navigate to="/platform/tenants" replace />} />
      <Route path="/platform/*" element={<Navigate to="/platform/tenants" replace />} />

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  </Suspense>
);

export default AppRouter;
