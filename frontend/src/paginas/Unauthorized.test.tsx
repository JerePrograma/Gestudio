import { fireEvent, render, screen } from "@testing-library/react";
import { MemoryRouter, Route, Routes, useLocation } from "react-router";
import { describe, expect, it } from "vitest";
import Unauthorized from "./Unauthorized";

describe("Unauthorized", () => {
  it("explica el rechazo y vuelve al inicio", () => {
    render(
      <MemoryRouter initialEntries={["/sin-permiso"]}>
        <Routes>
          <Route path="/sin-permiso" element={<Unauthorized />} />
          <Route path="/" element={<LocationProbe />} />
        </Routes>
      </MemoryRouter>,
    );
    expect(screen.getByRole("heading", { name: "Acceso no autorizado" })).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Volver al inicio" }));
    expect(screen.getByTestId("location")).toHaveTextContent("/");
  });
});

function LocationProbe() {
  return <span data-testid="location">{useLocation().pathname}</span>;
}
