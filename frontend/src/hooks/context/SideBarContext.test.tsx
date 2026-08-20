import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import { SidebarProvider } from "./SideBarContext";
import { useSidebar } from "./useSidebar";

describe("SidebarProvider", () => {
  it("expone expansión y apertura móvil con transiciones reversibles", () => {
    render(<SidebarProvider><Probe /></SidebarProvider>);
    expect(screen.getByTestId("state")).toHaveTextContent("expanded/closed");

    fireEvent.click(screen.getByRole("button", { name: "Alternar" }));
    expect(screen.getByTestId("state")).toHaveTextContent("collapsed/closed");
    fireEvent.click(screen.getByRole("button", { name: "Abrir móvil" }));
    expect(screen.getByTestId("state")).toHaveTextContent("collapsed/open");
    fireEvent.click(screen.getByRole("button", { name: "Cerrar móvil" }));
    expect(screen.getByTestId("state")).toHaveTextContent("collapsed/closed");
  });

  it("falla de forma explícita fuera del provider", () => {
    const consoleError = vi.spyOn(console, "error").mockImplementation(() => undefined);
    expect(() => render(<Probe />)).toThrow("useSidebar must be used within a SidebarProvider");
    consoleError.mockRestore();
  });
});

function Probe() {
  const sidebar = useSidebar();
  return <>
    <span data-testid="state">{sidebar.isExpanded ? "expanded" : "collapsed"}/{sidebar.mobileSidebarOpen ? "open" : "closed"}</span>
    <button onClick={sidebar.toggleSidebar}>Alternar</button>
    <button onClick={() => sidebar.setMobileSidebarOpen(true)}>Abrir móvil</button>
    <button onClick={() => sidebar.setMobileSidebarOpen(false)}>Cerrar móvil</button>
    <button onClick={sidebar.closeSidebar}>Colapsar</button>
  </>;
}
