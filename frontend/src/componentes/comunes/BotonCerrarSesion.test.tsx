import { fireEvent, render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import BotonCerrarSesion from "./BotonCerrarSesion";

const logout = vi.fn<() => Promise<void>>();

vi.mock("../../hooks/context/useAuth", () => ({
  useAuth: () => ({ logout }),
}));

describe("BotonCerrarSesion", () => {
  beforeEach(() => {
    logout.mockReset();
    logout.mockResolvedValue();
  });

  it("expone una acción accesible y cierra la sesión", () => {
    render(<BotonCerrarSesion />);

    fireEvent.click(screen.getByRole("button", { name: "Cerrar sesión" }));

    expect(logout).toHaveBeenCalledTimes(1);
  });

  it("mantiene el nombre accesible cuando se muestra compacto", () => {
    render(<BotonCerrarSesion compact />);

    expect(screen.getByRole("button", { name: "Cerrar sesión" })).toHaveAttribute(
      "title",
      "Cerrar sesión",
    );
  });
});
