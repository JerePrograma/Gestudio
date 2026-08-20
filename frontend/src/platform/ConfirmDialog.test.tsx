import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import ConfirmDialog from "./ConfirmDialog";

describe("ConfirmDialog", () => {
  it("confirma o cancela una acción disponible", () => {
    const onConfirm = vi.fn();
    const onOpenChange = vi.fn();
    render(
      <ConfirmDialog
        open
        title="Suspender organización"
        description="El acceso quedará suspendido sin borrar datos."
        confirmLabel="Suspender"
        danger
        onConfirm={onConfirm}
        onOpenChange={onOpenChange}
      />,
    );

    expect(screen.getByRole("dialog", { name: "Suspender organización" })).toBeVisible();
    fireEvent.click(screen.getByRole("button", { name: "Suspender" }));
    fireEvent.click(screen.getByRole("button", { name: "Cancelar" }));

    expect(onConfirm).toHaveBeenCalledOnce();
    expect(onOpenChange).toHaveBeenCalledWith(false);
  });

  it("bloquea cierres y acciones mientras procesa", () => {
    const onConfirm = vi.fn();
    const onOpenChange = vi.fn();
    render(
      <ConfirmDialog
        open
        title="Crear organización"
        description="Se registrará una operación auditada."
        confirmLabel="Crear"
        busy
        onConfirm={onConfirm}
        onOpenChange={onOpenChange}
      />,
    );

    expect(screen.getByRole("button", { name: "Procesando…" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Cancelar" })).toBeDisabled();
    expect(screen.getByRole("button", { name: "Cerrar confirmación" })).toBeDisabled();
    fireEvent.keyDown(document, { key: "Escape" });

    expect(onConfirm).not.toHaveBeenCalled();
    expect(onOpenChange).not.toHaveBeenCalled();
  });
});
