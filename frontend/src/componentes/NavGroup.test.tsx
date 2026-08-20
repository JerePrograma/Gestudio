import { render, screen } from "@testing-library/react";
import { MemoryRouter } from "react-router";
import { describe, expect, it } from "vitest";
import { Bell } from "lucide-react";
import NavGroup from "./NavGroup";

describe("NavGroup", () => {
  it("marca enlaces activos y oculta la etiqueta en modo compacto", () => {
    const item = { id: "alumnos", label: "Alumnos", href: "/alumnos", icon: Bell };
    const { rerender } = render(<MemoryRouter initialEntries={["/alumnos/7"]}><NavGroup item={item} isExpanded /></MemoryRouter>);

    expect(screen.getByRole("link", { name: "Alumnos" })).toHaveClass("nav-item-active");
    rerender(<MemoryRouter initialEntries={["/otra"]}><NavGroup item={item} isExpanded={false} /></MemoryRouter>);
    expect(screen.getByTitle("Alumnos")).not.toHaveTextContent("Alumnos");
  });

  it("abre la categoría del hijo activo y representa subrutas", () => {
    render(
      <MemoryRouter initialEntries={["/roles/editar"]}>
        <NavGroup
          isExpanded
          item={{
            id: "seguridad",
            label: "Seguridad",
            icon: Bell,
            items: [
              { id: "usuarios", label: "Usuarios", href: "/usuarios" },
              { id: "roles", label: "Roles", href: "/roles", icon: Bell },
            ],
          }}
        />
      </MemoryRouter>,
    );

    expect(screen.getByRole("link", { name: "Roles" })).toHaveClass("nav-item-active");
    expect(screen.getByRole("link", { name: "Usuarios" })).not.toHaveClass("nav-item-active");
  });

  it("mantiene ocultos los hijos cuando el menú está colapsado", () => {
    render(
      <MemoryRouter>
        <NavGroup item={{ id: "grupo", label: "Grupo", items: [{ id: "uno", label: "Uno", href: "/uno" }] }} isExpanded={false} />
      </MemoryRouter>,
    );

    expect(screen.getByTitle("Grupo")).toBeVisible();
    expect(screen.queryByRole("link", { name: "Uno" })).not.toBeInTheDocument();
  });
});
