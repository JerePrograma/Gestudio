import * as Dialog from "@radix-ui/react-dialog";
import { useRef } from "react";
import { Link } from "react-router";
import { useSidebar } from "../hooks/context/useSidebar";
import { ChevronLeft, ChevronRight, Sparkles } from "lucide-react";
import { cn } from "../lib/utils";
import { useAuth } from "../hooks/context/useAuth";
import { filterNavigationItems, navigationItems } from "../config/navigation";
import NavGroup from "./NavGroup";
import BotonCerrarSesion from "./comunes/BotonCerrarSesion";

export default function Sidebar() {
  const { isExpanded, toggleSidebar } = useSidebar();
  const mobileCloseButtonRef = useRef<HTMLButtonElement>(null);

  const { hasPermission } = useAuth();

  const filteredNavigation = filterNavigationItems(navigationItems, hasPermission);

  return (
    <>
      <aside
        className={cn(
          "sidebar-surface fixed inset-y-0 left-0 z-40 hidden flex-col border-r border-border transition-[width] duration-300 md:flex",
          isExpanded ? "w-[var(--sidebar-width)]" : "w-[var(--sidebar-width-collapsed)]",
        )}
      >
        <div className="flex h-[var(--header-height)] items-center gap-3 border-b border-border px-3">
          <Link
            to="/"
            className="flex min-w-0 flex-1 items-center gap-3"
            aria-label="Ir al inicio"
          >
            <span className="flex size-10 shrink-0 items-center justify-center rounded-xl bg-primary text-primary-foreground shadow-sm">
              <Sparkles className="size-5" aria-hidden="true" />
            </span>
            {isExpanded && (
              <span className="truncate text-lg font-black tracking-tight text-foreground">
                Gestudio
              </span>
            )}
          </Link>

          <button
            onClick={toggleSidebar}
            className="icon-button size-8 shrink-0"
            aria-label={isExpanded ? "Colapsar menú" : "Expandir menú"}
          >
            {isExpanded ? (
              <ChevronLeft className="w-5 h-5" />
            ) : (
              <ChevronRight className="w-5 h-5" />
            )}
          </button>
        </div>

        <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-4" aria-label="Navegación principal">
          {isExpanded && (
            <p className="mb-2 px-3 text-[0.6875rem] font-bold uppercase tracking-[0.12em] text-muted-foreground">
              Menú principal
            </p>
          )}

          {filteredNavigation.map((item) => (
            <NavGroup key={item.id} item={item} isExpanded={isExpanded} />
          ))}
        </nav>

        <div className="border-t border-border p-3">
          <BotonCerrarSesion compact={!isExpanded} />
        </div>
      </aside>

      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-40 bg-foreground/35 backdrop-blur-sm" />
        <Dialog.Content
          id="tenant-mobile-navigation"
          className="sidebar-surface fixed inset-y-0 left-0 z-50 flex w-[min(20rem,88vw)] flex-col border-r border-border focus:outline-none"
          onOpenAutoFocus={(event) => {
            event.preventDefault();
            mobileCloseButtonRef.current?.focus();
          }}
        >
          <div className="flex h-[var(--header-height)] items-center gap-3 border-b border-border px-4">
            <span className="flex size-10 items-center justify-center rounded-xl bg-primary text-primary-foreground">
              <Sparkles className="size-5" aria-hidden="true" />
            </span>

            <Link to="/" className="text-lg font-black text-foreground">
              Gestudio
            </Link>

            <Dialog.Title className="sr-only">Menú principal</Dialog.Title>
            <Dialog.Description className="sr-only">
              Navegación principal de Gestudio
            </Dialog.Description>

            <Dialog.Close asChild>
              <button
                ref={mobileCloseButtonRef}
                type="button"
                className="icon-button ml-auto"
                aria-label="Cerrar menú"
              >
                <ChevronLeft className="w-5 h-5" aria-hidden="true" />
              </button>
            </Dialog.Close>
          </div>

          <nav className="flex-1 space-y-1 overflow-y-auto px-3 py-4" aria-label="Navegación principal">
            {filteredNavigation.map((item) => (
              <NavGroup key={item.id} item={item} isExpanded={true} />
            ))}
          </nav>

          <div className="border-t border-border p-3">
            <BotonCerrarSesion />
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </>
  );
}
