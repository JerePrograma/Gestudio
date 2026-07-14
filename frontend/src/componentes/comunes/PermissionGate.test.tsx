import { render, screen } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";
import { PERMISSIONS } from "../../config/permissions";

const hasPermission = vi.hoisted(() => vi.fn<(permission: string) => boolean>());

vi.mock("../../hooks/context/useAuth", () => ({
  useAuth: () => ({ hasPermission }),
}));

import PermissionGate from "./PermissionGate";
import RowActions from "./RowActions";

describe("PermissionGate", () => {
  beforeEach(() => hasPermission.mockReset());

  it("oculta la acción sin APP aunque exista el permiso funcional", () => {
    hasPermission.mockImplementation((permission) => permission === PERMISSIONS.PAGOS_ANULAR);

    render(<PermissionGate permission={PERMISSIONS.PAGOS_ANULAR}>Anular pago</PermissionGate>);

    expect(screen.queryByText("Anular pago")).not.toBeInTheDocument();
  });

  it("oculta la acción sin permiso funcional", () => {
    hasPermission.mockImplementation((permission) => permission === PERMISSIONS.APP_ACCESS);

    render(<PermissionGate permission={PERMISSIONS.REPORTES_EXPORTAR}>Exportar</PermissionGate>);

    expect(screen.queryByText("Exportar")).not.toBeInTheDocument();
  });

  it.each([
    ["alumnos", PERMISSIONS.ALUMNOS_ADMIN],
    ["inscripciones", PERMISSIONS.INSCRIPCIONES_ADMIN],
    ["disciplinas", PERMISSIONS.DISCIPLINAS_ADMIN],
    ["profesores", PERMISSIONS.PROFESORES_ADMIN],
    ["asistencias", PERMISSIONS.ASISTENCIAS_REGISTRAR],
    ["pagos", PERMISSIONS.PAGOS_ANULAR],
    ["egresos", PERMISSIONS.EGRESOS_ADMIN],
    ["stock", PERMISSIONS.STOCK_ADMIN],
    ["venta de stock", PERMISSIONS.STOCK_VENDER],
    ["tarifas", PERMISSIONS.TARIFAS_ADMIN],
    ["condiciones", PERMISSIONS.CONDICIONES_ECONOMICAS_ADMIN],
    ["reportes", PERMISSIONS.REPORTES_EXPORTAR],
    ["usuarios", PERMISSIONS.USUARIOS_ADMIN],
    ["roles", PERMISSIONS.ROLES_ADMIN],
    ["configuración", PERMISSIONS.CONFIG_ADMIN],
  ] as const)("prueba permitido y denegado para %s", (label, permission) => {
    hasPermission.mockImplementation((candidate) => candidate === PERMISSIONS.APP_ACCESS);
    const denied = render(<PermissionGate permission={permission}>{label}</PermissionGate>);
    expect(screen.queryByText(label)).not.toBeInTheDocument();
    denied.unmount();

    hasPermission.mockReturnValue(true);

    render(<PermissionGate permission={permission}>{label}</PermissionGate>);

    expect(screen.getByText(label)).toBeVisible();
  });

  it("filtra acciones de fila con la misma conjunción APP y permiso funcional", () => {
    hasPermission.mockImplementation((permission) => permission === PERMISSIONS.PAGOS_ANULAR);
    const denied = render(<RowActions actions={[{
      label: "Anular pago",
      requiredPermission: PERMISSIONS.PAGOS_ANULAR,
      onSelect: vi.fn(),
    }]} />);
    expect(screen.queryByRole("button", { name: "Abrir acciones" })).not.toBeInTheDocument();
    denied.unmount();

    hasPermission.mockReturnValue(true);
    render(<RowActions actions={[{
      label: "Anular pago",
      requiredPermission: PERMISSIONS.PAGOS_ANULAR,
      onSelect: vi.fn(),
    }]} />);
    expect(screen.getByRole("button", { name: "Abrir acciones" })).toBeVisible();
  });
});
