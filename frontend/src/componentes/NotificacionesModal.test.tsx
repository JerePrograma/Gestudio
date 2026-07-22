import { render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import NotificacionesModal from "./NotificacionesModal";

const api = vi.hoisted(() => ({ get: vi.fn() }));

vi.mock("../api/axiosConfig", () => ({ default: api }));

describe("NotificacionesModal", () => {
  it("distingue carga de vacío y muestra los cumpleaños recibidos", async () => {
    let resolveRequest: (value: { data: string[] }) => void = () => undefined;
    api.get.mockReturnValueOnce(new Promise((resolve) => { resolveRequest = resolve; }));

    render(<NotificacionesModal isOpen onClose={vi.fn()} />);

    expect(screen.getByRole("dialog", { name: "Cumpleañeros de hoy" })).toBeVisible();
    expect(screen.getByRole("status")).toHaveTextContent("Cargando cumpleaños");
    expect(screen.queryByText("No hay notificaciones para hoy.")).not.toBeInTheDocument();

    resolveRequest({ data: ["Alumno: Sofía Benítez"] });

    expect(await screen.findByText("Alumno: Sofía Benítez")).toBeVisible();
    expect(screen.queryByRole("status")).not.toBeInTheDocument();
  });

  it("ofrece un error accionable sin registrar datos de la solicitud", async () => {
    api.get.mockRejectedValueOnce(new Error("fallo sintético"));

    render(<NotificacionesModal isOpen onClose={vi.fn()} />);

    expect(await screen.findByRole("alert")).toHaveTextContent(
      "No se pudieron cargar los cumpleaños. Intentá nuevamente.",
    );
  });
});
