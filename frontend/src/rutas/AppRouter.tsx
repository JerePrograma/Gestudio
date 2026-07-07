import { Suspense } from "react";
import { Navigate, Route, Routes } from "react-router-dom";
import LoadingState from "../componentes/comunes/LoadingState";
import MainLayout from "../componentes/layout/MainLayout";
import ProtectedRoute from "./ProtectedRoute";
import {
  publicRoutes,
  protectedRoutes,
  adminRoutes,
  otherProtectedRoutes,
} from "./routes";

const AppRouter = () => (
    <Suspense fallback={<LoadingState message="Cargando pantalla..." />}>
      <Routes>
        {publicRoutes.map(({ path, Component }) => (
          <Route key={path} path={path} element={<Component />} />
        ))}

        <Route element={<ProtectedRoute />}>
          <Route element={<MainLayout />}>
            {protectedRoutes.map(({ path, Component }) => (
              <Route key={path} path={path} element={<Component />} />
            ))}
            <Route element={<ProtectedRoute requiredRole="ADMINISTRADOR" />}>
              {[...adminRoutes, ...otherProtectedRoutes].map(({ path, Component }) => (
                <Route key={path} path={path} element={<Component />} />
              ))}
            </Route>
          </Route>
        </Route>
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </Suspense>
);

export default AppRouter;
