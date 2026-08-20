import { fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { MemoryRouter, Route, Routes } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const mocks = vi.hoisted(() => ({
  apiGet: vi.fn(),
  hasPermission: vi.fn(),
  toastSuccess: vi.fn(),
  toastError: vi.fn(),
}));

vi.mock("../../api/axiosConfig", () => ({
  default: { get: mocks.apiGet },
}));

vi.mock("../../hooks/context/useAuth", () => ({
  useAuth: () => ({ hasPermission: mocks.hasPermission }),
}));

vi.mock("react-toastify", () => ({
  toast: {
    success: mocks.toastSuccess,
    error: mocks.toastError,
  },
}));

import AlumnosPorDisciplina from "./AlumnosPorDIsciplina";

describe("AlumnosPorDisciplina", () => {
  beforeEach(() => {
    vi.restoreAllMocks();
    vi.clearAllMocks();
    mocks.hasPermission.mockReturnValue(true);
    mocks.apiGet.mockImplementation(async (url: string) => {
      if (url === "/disciplinas") {
        return { data: disciplines() };
      }
      if (url.endsWith("/alumnos/pdf")) {
        return { data: new Uint8Array([37, 80, 68, 70]) };
      }
      if (url.endsWith("/alumnos")) {
        return { data: students() };
      }
      throw new Error(`Unexpected URL: ${url}`);
    });
  });

  it("notifica de forma segura si no puede cargar disciplinas", async () => {
    mocks.apiGet.mockRejectedValueOnce(new Error("network"));

    renderPage();

    await waitFor(() =>
      expect(mocks.toastError).toHaveBeenCalledWith(
        "Error al cargar disciplinas",
      ),
    );
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
  });

  it("navega las sugerencias con teclado, cierra al hacer clic fuera y limpia", async () => {
    renderPage();
    const search = screen.getByLabelText("Selecciona la disciplina:");

    fireEvent.focus(search);
    expect(await screen.findByText("Ballet")).toBeVisible();
    fireEvent.mouseDown(document.body);
    expect(screen.queryByText("Ballet")).not.toBeInTheDocument();

    fireEvent.focus(search);
    fireEvent.change(search, { target: { value: "danza" } });
    fireEvent.keyDown(search, { key: "ArrowUp" });
    fireEvent.keyDown(search, { key: "Enter" });

    expect(search).toHaveValue("Danza jazz");
    await waitFor(() =>
      expect(mocks.apiGet).toHaveBeenCalledWith("/disciplinas/8/alumnos"),
    );

    fireEvent.click(screen.getByRole("button", { name: "Limpiar" }));
    expect(search).toHaveValue("");
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
  });

  it("muestra loading, lista ordenada y permite invertir el orden", async () => {
    let resolveStudents!: (value: { data: ReturnType<typeof students> }) => void;
    mocks.apiGet.mockImplementation((url: string) => {
      if (url === "/disciplinas") {
        return Promise.resolve({ data: disciplines() });
      }
      return new Promise<{ data: ReturnType<typeof students> }>((resolve) => {
        resolveStudents = resolve;
      });
    });
    renderPage();

    await selectDiscipline("Ballet");
    expect(await screen.findByText("Cargando alumnos...")).toBeVisible();
    resolveStudents({ data: students() });

    const table = await screen.findByRole("table");
    expect(rowNames(table)).toEqual(["1Ana Zeta", "2Bruno Alba"]);

    fireEvent.click(screen.getByRole("button", { name: "Ordenar Descendente" }));
    expect(rowNames(table)).toEqual(["1Bruno Alba", "2Ana Zeta"]);
    expect(screen.getByRole("button", { name: "Ordenar Ascendente" })).toBeVisible();
  });

  it("representa una respuesta vacía sin tabla ni estado de carga residual", async () => {
    mocks.apiGet.mockImplementation(async (url: string) => ({
      data: url === "/disciplinas" ? disciplines() : [],
    }));
    renderPage();

    await selectDiscipline("Ballet");

    await waitFor(() =>
      expect(mocks.apiGet).toHaveBeenCalledWith("/disciplinas/7/alumnos"),
    );
    expect(screen.queryByText("Cargando alumnos...")).not.toBeInTheDocument();
    expect(screen.queryByRole("table")).not.toBeInTheDocument();
    expect(screen.queryByRole("button", { name: "Exportar PDF" })).not.toBeInTheDocument();
  });

  it("muestra error visible y toast cuando falla la carga de alumnos", async () => {
    mocks.apiGet.mockImplementation(async (url: string) => {
      if (url === "/disciplinas") return { data: disciplines() };
      throw new Error("backend");
    });
    renderPage();

    await selectDiscipline("Ballet");

    expect(
      await screen.findByText(
        "Ocurrió un error al cargar los alumnos. Por favor, intenta de nuevo.",
      ),
    ).toBeVisible();
    expect(mocks.toastError).toHaveBeenCalledWith("Error al cargar alumnos");
    expect(screen.queryByText("Cargando alumnos...")).not.toBeInTheDocument();
  });

  it("exporta el PDF con URL temporal y libera el recurso", async () => {
    const createObjectURL = vi.fn(() => "blob:alumnos");
    const revokeObjectURL = vi.fn();
    Object.defineProperty(window.URL, "createObjectURL", {
      configurable: true,
      value: createObjectURL,
    });
    Object.defineProperty(window.URL, "revokeObjectURL", {
      configurable: true,
      value: revokeObjectURL,
    });
    const linkClick = vi
      .spyOn(HTMLAnchorElement.prototype, "click")
      .mockImplementation(() => undefined);
    renderPage();
    await selectDiscipline("Ballet");
    await screen.findByRole("table");

    fireEvent.click(screen.getByRole("button", { name: "Exportar PDF" }));

    await waitFor(() =>
      expect(mocks.apiGet).toHaveBeenCalledWith(
        "/disciplinas/7/alumnos/pdf",
        { responseType: "blob" },
      ),
    );
    expect(createObjectURL).toHaveBeenCalledWith(expect.any(Blob));
    expect(linkClick).toHaveBeenCalledTimes(1);
    expect(revokeObjectURL).toHaveBeenCalledWith("blob:alumnos");
    expect(mocks.toastSuccess).toHaveBeenCalledWith(
      "PDF exportado correctamente",
    );
  });

  it("notifica un fallo de exportación sin anunciar éxito", async () => {
    mocks.apiGet.mockImplementation(async (url: string) => {
      if (url === "/disciplinas") return { data: disciplines() };
      if (url.endsWith("/alumnos/pdf")) throw new Error("pdf");
      return { data: students() };
    });
    renderPage();
    await selectDiscipline("Ballet");
    await screen.findByRole("table");

    fireEvent.click(screen.getByRole("button", { name: "Exportar PDF" }));

    await waitFor(() =>
      expect(mocks.toastError).toHaveBeenCalledWith(
        "Error al exportar alumnos a PDF",
      ),
    );
    expect(mocks.toastSuccess).not.toHaveBeenCalled();
  });

  it("oculta la exportación si faltan permisos y conserva la navegación", async () => {
    mocks.hasPermission.mockReturnValue(false);
    renderPage();
    await selectDiscipline("Ballet");
    await screen.findByRole("table");

    expect(screen.queryByRole("button", { name: "Exportar PDF" })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole("button", { name: "Volver" }));
    expect(screen.getByText("Reportes")).toBeVisible();
  });
});

function renderPage() {
  return render(
    <MemoryRouter initialEntries={["/reportes/alumnos-disciplina"]}>
      <Routes>
        <Route
          path="/reportes/alumnos-disciplina"
          element={<AlumnosPorDisciplina />}
        />
        <Route path="/reportes" element={<p>Reportes</p>} />
      </Routes>
    </MemoryRouter>,
  );
}

async function selectDiscipline(name: string) {
  const search = screen.getByLabelText("Selecciona la disciplina:");
  fireEvent.focus(search);
  fireEvent.click(await screen.findByText(name));
  await waitFor(() => expect(search).toHaveValue(name));
}

function rowNames(table: HTMLElement) {
  return within(table)
    .getAllByRole("row")
    .slice(1)
    .map((row) => row.textContent);
}

function disciplines() {
  return [
    { id: 7, nombre: "Ballet" },
    { id: 8, nombre: "Danza jazz" },
  ];
}

function students() {
  return [
    { id: 2, nombre: "Bruno", apellido: "Alba" },
    { id: 1, nombre: "Ana", apellido: "Zeta" },
  ];
}
