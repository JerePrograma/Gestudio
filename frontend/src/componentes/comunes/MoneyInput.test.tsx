import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import MoneyInput from "./MoneyInput";

describe("MoneyInput", () => {
  it("normaliza el decimal como string al perder foco y asocia el error", () => {
    const onChange = vi.fn();
    const { rerender } = render(
      <MoneyInput id="monto" label="Monto" value="1,2" onChange={onChange} error="Importe inválido" />,
    );

    const input = screen.getByLabelText("Monto");
    expect(input).toHaveAttribute("aria-invalid", "true");
    expect(input).toHaveAccessibleDescription("Importe inválido");
    fireEvent.blur(input);
    expect(onChange).toHaveBeenCalledWith("1.20");

    rerender(<MoneyInput id="monto" label="Monto" value="9007199254740993.99" onChange={onChange} />);
    fireEvent.blur(screen.getByLabelText("Monto"));
    expect(onChange).toHaveBeenLastCalledWith("9007199254740993.99");
  });
});
