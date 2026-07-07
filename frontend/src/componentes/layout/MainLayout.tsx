import { Outlet } from "react-router-dom";
import Header from "../Header"
import Sidebar from "../Sidebar"
import { useSidebar } from "../../hooks/context/useSidebar"
import { ThemeProvider } from "next-themes"

export default function MainLayout() {
  const { isExpanded } = useSidebar()

  return (
    <ThemeProvider attribute="class" defaultTheme="system" enableSystem disableTransitionOnChange>
      <div className="min-h-[100dvh] bg-background">
        <a className="skip-link" href="#main-content">Saltar al contenido</a>
        <Header />
        <Sidebar />
        <main
          id="main-content"
          className={`min-h-[100dvh] w-full px-[var(--container-padding)] pb-8 pt-[calc(var(--header-height)+1.5rem)] transition-[padding] duration-300 ${isExpanded ? "md:pl-[calc(var(--sidebar-width)+var(--container-padding))]" : "md:pl-[calc(var(--sidebar-width-collapsed)+var(--container-padding))]"}`}
        >
          <Outlet />
        </main>
      </div>
    </ThemeProvider>
  )
}
