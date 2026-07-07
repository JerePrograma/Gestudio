import { describe, expect, it } from "vitest";
import { queryKeys } from "./queryKeys";

describe("queryKeys paginadas", () => {
  it("incluyen pagina, tamaño, filtros y orden estable", () => {
    expect(queryKeys.alumnos(0, 50, " Ana ")).toEqual(["alumnos", 0, 50, "Ana", "id,asc"]);
    expect(queryKeys.alumnos(1, 50, "Ana")).not.toEqual(queryKeys.alumnos(0, 50, "Ana"));
    expect(queryKeys.inscripciones(0, 50, "danza")).toEqual([
      "inscripciones", 0, 50, "danza", "id,desc",
    ]);
    expect(queryKeys.caja("2026-01-01", "2026-01-31", 2, 50)).toEqual([
      "caja", "2026-01-01", "2026-01-31", 2, 50, "fecha,asc;id,asc",
    ]);
    expect(queryKeys.inscripcion(42)).toEqual(["inscripciones", "detalle", 42]);
    expect(queryKeys.stock(7)).toEqual(["stocks", "detalle", 7]);
    expect(queryKeys.all.alumnos).toEqual(["alumnos"]);
  });
});
