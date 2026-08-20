import { fireEvent, render, screen } from "@testing-library/react";
import { describe, expect, it, vi } from "vitest";
import OneTimeActivationNotice from "./OneTimeActivationNotice";

describe("OneTimeActivationNotice", () => {
  it("muestra el token sólo en memoria, permite copiarlo y descartarlo", () => {
    const writeText = vi.fn().mockResolvedValue(undefined);
    Object.defineProperty(navigator, "clipboard", {
      configurable: true,
      value: { writeText },
    });
    const onDismiss = vi.fn();
    const localStorageEntries = localStorage.length;
    const sessionStorageEntries = sessionStorage.length;
    const activationUrl = `${window.location.origin}/platform/activate#token=one-time-membership-token`;

    render(
      <OneTimeActivationNotice
        activation={{ token: "one-time-membership-token", expiresAt: "2030-01-01T00:00:00Z" }}
        onDismiss={onDismiss}
      />,
    );

    expect(screen.getByText(activationUrl)).toBeVisible();
    expect(activationUrl).not.toContain("?token=");
    expect(localStorage.length).toBe(localStorageEntries);
    expect(sessionStorage.length).toBe(sessionStorageEntries);
    fireEvent.click(screen.getByRole("button", { name: "Copiar" }));
    expect(writeText).toHaveBeenCalledWith(activationUrl);
    fireEvent.click(screen.getByRole("button", { name: "Descartar token de activación" }));
    expect(onDismiss).toHaveBeenCalledOnce();
  });
});
