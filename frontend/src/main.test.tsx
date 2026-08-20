import { StrictMode } from "react";
import { describe, expect, it, vi } from "vitest";

const reactDom = vi.hoisted(() => {
  const root = { render: vi.fn(), unmount: vi.fn() };
  return { createRoot: vi.fn(() => root), root };
});

vi.mock("react-dom/client", () => ({ createRoot: reactDom.createRoot }));
vi.mock("./App.tsx", () => ({ default: () => null }));

describe("bootstrap de React", () => {
  it("crea la raíz del documento y renderiza la aplicación en StrictMode", async () => {
    document.body.innerHTML = '<div id="root"></div>';

    await import("./main");

    expect(reactDom.createRoot).toHaveBeenCalledWith(document.getElementById("root"));
    expect(reactDom.root.render).toHaveBeenCalledWith(
      expect.objectContaining({ type: StrictMode }),
    );
  });
});
