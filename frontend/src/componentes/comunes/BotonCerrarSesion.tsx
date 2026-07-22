import type React from "react";
import { useAuth } from "../../hooks/context/useAuth";
import Boton from "./Boton";
import { LogOut } from "lucide-react";

interface BotonCerrarSesionProps {
  compact?: boolean;
}

const BotonCerrarSesion: React.FC<BotonCerrarSesionProps> = ({ compact = false }) => {
  const { logout } = useAuth();

  const handleLogout = () => {
    void logout().catch(() => undefined);
  };

  return (
    <Boton
      onClick={handleLogout}
      className={`page-button-secondary w-full ${compact ? "justify-center px-0" : ""}`}
      aria-label="Cerrar sesión"
      title={compact ? "Cerrar sesión" : undefined}
    >
      <LogOut className={compact ? "size-4" : "mr-2 size-4"} aria-hidden="true" />
      {!compact && <span>Cerrar sesión</span>}
    </Boton>
  );
};

export default BotonCerrarSesion;
