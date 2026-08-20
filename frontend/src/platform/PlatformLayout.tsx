import * as Dialog from "@radix-ui/react-dialog";
import {
  Building2,
  FileSearch,
  Menu,
  Moon,
  Shield,
  Sun,
  UserCog,
  X,
} from "lucide-react";
import { ThemeProvider, useTheme } from "next-themes";
import { useRef, useState } from "react";
import { NavLink, Outlet, useLocation } from "react-router";
import Boton from "../componentes/comunes/Boton";
import { cn } from "../lib/utils";
import { useAuth } from "../hooks/context/useAuth";
import { StepUpProvider } from "./StepUpProvider";

const navigation = [
  { to: "/platform/tenants", label: "Organizaciones", icon: Building2 },
  { to: "/platform/admins", label: "Administradores", icon: UserCog },
  { to: "/platform/audit", label: "Auditoría", icon: FileSearch },
] as const;

const currentTitle = (pathname: string): string => {
  if (pathname === "/platform/tenants/new") return "Nueva organización";
  if (/^\/platform\/tenants\/[^/]+$/.test(pathname)) return "Detalle de organización";
  return navigation.find(({ to }) => pathname.startsWith(to))?.label ?? "Control plane";
};

const PlatformShell = () => {
  const [mobileOpen, setMobileOpen] = useState(false);
  const mobileCloseButtonRef = useRef<HTMLButtonElement>(null);
  const { platformUser, logout } = useAuth();
  const { resolvedTheme, setTheme } = useTheme();
  const location = useLocation();

  const nav = (
    <nav className="space-y-1 px-3 py-4" aria-label="Navegación del control plane">
      <p className="mb-2 px-3 text-[0.6875rem] font-bold uppercase tracking-[0.12em] text-muted-foreground">
        Plataforma
      </p>
      {navigation.map(({ to, label, icon: Icon }) => (
        <NavLink
          key={to}
          to={to}
          onClick={() => setMobileOpen(false)}
          className={({ isActive }) => cn("nav-item", isActive && "nav-item-active")}
        >
          <Icon className="size-4 shrink-0" aria-hidden="true" />
          <span>{label}</span>
        </NavLink>
      ))}
    </nav>
  );

  return (
    <Dialog.Root open={mobileOpen} onOpenChange={setMobileOpen}>
      <div className="min-h-[100dvh] bg-background">
        <a className="skip-link" href="#platform-main">Saltar al contenido</a>

        <aside className="sidebar-surface fixed inset-y-0 left-0 z-40 hidden w-[var(--sidebar-width)] flex-col border-r border-border md:flex">
          <div className="flex h-[var(--header-height)] items-center gap-3 border-b border-border px-4">
            <span className="flex size-10 items-center justify-center rounded-xl bg-primary text-primary-foreground">
              <Shield className="size-5" aria-hidden="true" />
            </span>
            <div className="min-w-0">
              <p className="truncate text-base font-black">Gestudio</p>
              <p className="truncate text-xs font-semibold text-muted-foreground">Control plane</p>
            </div>
          </div>
          <div className="flex-1 overflow-y-auto">{nav}</div>
          <div className="border-t border-border p-3">
            <Boton className="page-button-secondary w-full" onClick={() => void logout().catch(() => undefined)}>
              Cerrar sesión
            </Boton>
          </div>
        </aside>

        <header className="topbar fixed inset-x-0 top-0 z-30 flex h-[var(--header-height)] items-center px-4 md:left-[var(--sidebar-width)] sm:px-6">
          <Dialog.Trigger asChild>
            <button
              type="button"
              className="icon-button mr-2 md:hidden"
              aria-label="Abrir menú"
              aria-expanded={mobileOpen}
              aria-controls="platform-mobile-navigation"
            >
              <Menu className="size-5" aria-hidden="true" />
            </button>
          </Dialog.Trigger>
          <div className="min-w-0 flex-1">
            <p className="truncate text-xs font-bold uppercase tracking-[0.1em] text-primary">Control plane</p>
            <p className="truncate text-sm font-semibold sm:text-base">{currentTitle(location.pathname)}</p>
          </div>
          <button
            type="button"
            className="icon-button"
            onClick={() => setTheme(resolvedTheme === "dark" ? "light" : "dark")}
            aria-label={resolvedTheme === "dark" ? "Usar tema claro" : "Usar tema oscuro"}
          >
            {resolvedTheme === "dark" ? <Sun className="size-5" /> : <Moon className="size-5" />}
          </button>
          <div className="ml-2 hidden border-l border-border pl-3 sm:block">
            <p className="max-w-44 truncate text-sm font-semibold">{platformUser?.nombreUsuario}</p>
            <p className="text-xs text-muted-foreground">Superadministración</p>
          </div>
        </header>

        <Dialog.Portal>
          <Dialog.Overlay className="fixed inset-0 z-50 bg-foreground/40 backdrop-blur-sm" />
          <Dialog.Content
            id="platform-mobile-navigation"
            className="sidebar-surface fixed inset-y-0 left-0 z-[51] flex w-[min(20rem,88vw)] flex-col border-r border-border focus:outline-none"
            onOpenAutoFocus={(event) => {
              event.preventDefault();
              mobileCloseButtonRef.current?.focus();
            }}
          >
            <div className="flex h-[var(--header-height)] items-center gap-3 border-b border-border px-4">
              <Shield className="size-5 text-primary" aria-hidden="true" />
              <Dialog.Title className="font-bold">Control plane</Dialog.Title>
              <Dialog.Description className="sr-only">
                Navegación de superadministración
              </Dialog.Description>
              <Dialog.Close asChild>
                <button ref={mobileCloseButtonRef} type="button" className="icon-button ml-auto" aria-label="Cerrar menú">
                  <X className="size-5" aria-hidden="true" />
                </button>
              </Dialog.Close>
            </div>
            <div className="flex-1 overflow-y-auto">{nav}</div>
            <div className="border-t border-border p-3">
              <Boton className="page-button-secondary w-full" onClick={() => void logout().catch(() => undefined)}>Cerrar sesión</Boton>
            </div>
          </Dialog.Content>
        </Dialog.Portal>

        <main
          id="platform-main"
          tabIndex={-1}
          className="min-h-[100dvh] px-[var(--container-padding)] pb-8 pt-[calc(var(--header-height)+1.5rem)] md:pl-[calc(var(--sidebar-width)+var(--container-padding))]"
        >
          <Outlet />
        </main>
      </div>
    </Dialog.Root>
  );
};

const PlatformLayout = () => (
  <ThemeProvider attribute="class" defaultTheme="system" enableSystem disableTransitionOnChange>
    <StepUpProvider>
      <PlatformShell />
    </StepUpProvider>
  </ThemeProvider>
);

export default PlatformLayout;
