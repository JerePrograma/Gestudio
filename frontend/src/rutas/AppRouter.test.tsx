import { render, screen } from "@testing-library/react";
import { MemoryRouter, Outlet } from "react-router";
import { beforeEach, describe, expect, it, vi } from "vitest";

const auth = vi.hoisted(() => ({
  isAuth: true,
  loading: false,
  scope: "PLATFORM" as "PLATFORM" | "TENANT" | null,
  user: null,
  platformUser: { authorities: ["PLATFORM_SUPERADMIN"] },
  hasPermission: vi.fn(),
  hasAllPermissions: vi.fn(),
  hasAnyPermission: vi.fn(),
}));

vi.mock("../hooks/context/useAuth", () => ({ useAuth: () => auth }));
vi.mock("../platform/PlatformLayout", () => ({ default: () => <main><Outlet /></main> }));
vi.mock("../componentes/layout/MainLayout", () => ({ default: () => <Outlet /> }));
vi.mock("../platform/pages/PlatformLogin", () => ({ default: () => <p>Login platform mock</p> }));
vi.mock("../platform/pages/PlatformActivatePage", () => ({ default: () => <p>Activate platform mock</p> }));
vi.mock("../platform/pages/TenantsPage", () => ({ default: () => <p>Tenants platform mock</p> }));
vi.mock("../platform/pages/TenantFormPage", () => ({ default: () => <p>Tenant form mock</p> }));
vi.mock("../platform/pages/TenantDetailPage", () => ({ default: () => <p>Tenant detail mock</p> }));
vi.mock("../platform/pages/PlatformAdminsPage", () => ({ default: () => <p>Admins platform mock</p> }));
vi.mock("../platform/pages/PlatformAuditPage", () => ({ default: () => <p>Audit platform mock</p> }));

import AppRouter from "./AppRouter";

const renderAt = (path: string) => render(<MemoryRouter initialEntries={[path]}><AppRouter /></MemoryRouter>);

describe("AppRouter control plane", () => {
  beforeEach(() => {
    auth.isAuth = true;
    auth.loading = false;
    auth.scope = "PLATFORM";
    auth.platformUser = { authorities: ["PLATFORM_SUPERADMIN"] };
  });

  it.each([
    ["/platform/login", "Login platform mock"],
    ["/platform/activate", "Activate platform mock"],
    ["/platform/tenants", "Tenants platform mock"],
    ["/platform/tenants/new", "Tenant form mock"],
    ["/platform/tenants/tenant-1", "Tenant detail mock"],
    ["/platform/admins", "Admins platform mock"],
    ["/platform/audit", "Audit platform mock"],
  ])("carga el import lazy real de %s", async (path, content) => {
    if (path === "/platform/login" || path === "/platform/activate") auth.isAuth = false;
    renderAt(path);
    expect(await screen.findByText(content)).toBeVisible();
  });

  it.each(["/platform", "/platform/no-existe"])("normaliza %s al listado", async (path) => {
    renderAt(path);
    expect(await screen.findByText("Tenants platform mock")).toBeVisible();
  });
});
