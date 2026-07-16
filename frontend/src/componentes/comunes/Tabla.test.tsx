import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";
import Tabla from "./Tabla";

describe("Tabla", () => {
  it("no trata la cabecera de acciones como una celda de datos", () => {
    render(
      <Tabla
        headers={["ID", "Acciones"]}
        data={[{ id: 1 }]}
        getRowKey={(row) => row.id}
        customRender={(row) => [row.id]}
        actions={() => <button type="button">Editar</button>}
      />,
    );

    expect(screen.queryByText("undefined")).not.toBeInTheDocument();
  });
});
