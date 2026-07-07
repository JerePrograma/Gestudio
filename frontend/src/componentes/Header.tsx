import { useState } from "react";
import { useTheme } from "next-themes";
import { useSidebar } from "../hooks/context/useSidebar";
import { Bell, Menu, Moon, Sun } from "lucide-react";
import { useLocation } from "react-router-dom";
import { cn } from "../lib/utils";
import NotificacionesModal from "./NotificacionesModal";
import { useAuth } from "../hooks/context/useAuth";
import { navigationItems, type NavigationItem } from "../config/navigation";

const findCurrentLabel = (items: NavigationItem[], pathname: string): string | undefined => {
  for (const item of items) {
    if (item.href && (pathname === item.href || pathname.startsWith(`${item.href}/`))) return item.label;
    const childLabel = item.items && findCurrentLabel(item.items, pathname);
    if (childLabel) return childLabel;
  }
  return pathname === "/" ? "Inicio" : undefined;
};

export default function Header() {
  const unreadCount = 0;
  const { isExpanded, setMobileSidebarOpen } = useSidebar();
  const { resolvedTheme, setTheme } = useTheme();
  const { user } = useAuth();
  const location = useLocation();
  const [showModal, setShowModal] = useState(false);
  const currentLabel = findCurrentLabel(navigationItems, location.pathname) ?? "Panel administrativo";
  const initial = user?.nombreUsuario.trim().charAt(0).toUpperCase() || "L";

  const toggleTheme = () => setTheme(resolvedTheme === "dark" ? "light" : "dark");

  const handleModalOpen = () => setShowModal(true);
  const handleModalClose = () => setShowModal(false);

  return (
    <>
      <header
        className={cn(
          "topbar fixed right-0 top-0 z-30 flex h-[var(--header-height)] items-center px-4 transition-[left] duration-300 sm:px-6",
          "left-0",
          {
            "md:left-[var(--sidebar-width)]": isExpanded,
            "md:left-[var(--sidebar-width-collapsed)]": !isExpanded,
          }
        )}
      >
        <button
          onClick={() => setMobileSidebarOpen(true)}
          className="icon-button mr-2 md:hidden"
          aria-label="Abrir menú"
        >
          <Menu className="size-5" />
        </button>

        <div className="flex min-w-0 flex-1 items-center justify-between gap-4">
          <div className="min-w-0">
            <p className="truncate text-xs font-bold uppercase tracking-[0.1em] text-primary">LE DANCE</p>
            <p className="truncate text-sm font-semibold text-foreground sm:text-base">{currentLabel}</p>
          </div>

          <div className="flex items-center gap-1 sm:gap-2">
            <button
              onClick={toggleTheme}
              className="icon-button"
              aria-label={resolvedTheme === "dark" ? "Usar tema claro" : "Usar tema oscuro"}
            >
              {resolvedTheme === "dark" ? (
                <Sun className="size-5" />
              ) : (
                <Moon className="size-5" />
              )}
            </button>

            <button
              onClick={handleModalOpen}
              className="icon-button relative"
              aria-label="Notificaciones"
            >
              <Bell className="size-5" />
              {unreadCount > 0 && (
                <span className="absolute top-1 right-1 w-4 h-4 flex items-center justify-center bg-[hsl(var(--destructive))] rounded-full text-xs text-white">
                  {unreadCount > 9 ? "9+" : unreadCount}
                </span>
              )}
            </button>
            <div className="ml-1 hidden items-center gap-2 border-l border-border pl-3 sm:flex">
              <span className="flex size-9 items-center justify-center rounded-full bg-primary/10 text-sm font-bold text-primary">{initial}</span>
              <div className="hidden max-w-36 lg:block">
                <p className="truncate text-sm font-semibold">{user?.nombreUsuario ?? "Usuario"}</p>
                <p className="truncate text-xs text-muted-foreground">{user?.rol ?? "Gestión"}</p>
              </div>
            </div>
          </div>
        </div>
      </header>

      <NotificacionesModal isOpen={showModal} onClose={handleModalClose} />
    </>
  );
}
