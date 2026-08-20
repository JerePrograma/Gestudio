import { beforeEach, describe, expect, expectTypeOf, it, vi } from "vitest";

const client = vi.hoisted(() => ({
  get: vi.fn(),
  post: vi.fn(),
  patch: vi.fn(),
  put: vi.fn(),
}));

vi.mock("../api/axiosConfig", () => ({ default: client }));

import { newIdempotencyKey, platformApi } from "./platformApi";
import type { PlatformAdmin, PlatformMembership, PlatformTenantDetail } from "./platformTypes";

describe("platformApi", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    client.get.mockResolvedValue({ data: { content: [], totalElements: 0, totalPages: 0, size: 25, number: 0, first: true, last: true } });
    client.post.mockResolvedValue({ data: {} });
    client.patch.mockResolvedValue({ data: {} });
    client.put.mockResolvedValue({ data: {} });
  });

  it("exige versiones optimistas en respuestas y mutaciones", () => {
    expectTypeOf<PlatformTenantDetail["version"]>().toEqualTypeOf<number>();
    expectTypeOf<PlatformMembership["version"]>().toEqualTypeOf<number>();
    expectTypeOf<PlatformAdmin["version"]>().toEqualTypeOf<number>();
    expectTypeOf<Parameters<typeof platformApi.updateTenant>[1]["expectedVersion"]>()
      .toEqualTypeOf<number>();
    expectTypeOf<Parameters<typeof platformApi.changeTenantStatus>[1]["expectedVersion"]>()
      .toEqualTypeOf<number>();
    expectTypeOf<Parameters<typeof platformApi.updateMembershipRoles>[2]["expectedVersion"]>()
      .toEqualTypeOf<number>();
    expectTypeOf<Parameters<typeof platformApi.changeMembershipStatus>[2]["expectedVersion"]>()
      .toEqualTypeOf<number>();
    expectTypeOf<Parameters<typeof platformApi.changeAdminStatus>[1]["expectedVersion"]>()
      .toEqualTypeOf<number>();
  });

  it("mantiene las consultas dentro de /platform y envía filtros paginados", async () => {
    await platformApi.listTenants({ page: 2, size: 25, q: "centro", status: "ACTIVE" });
    expect(client.get).toHaveBeenCalledWith(
      expect.stringMatching(/^\/platform\/tenants\?.*page=2.*size=25.*q=centro.*status=ACTIVE$/),
    );

    await platformApi.listAudit({ page: 0, size: 20, tenantId: "tenant-1", result: "DENIED" });
    expect(client.get).toHaveBeenLastCalledWith(
      expect.stringMatching(/^\/platform\/audit\?.*page=0.*size=20.*tenantId=tenant-1.*result=DENIED$/),
    );
  });

  it("conserva los headers vinculados entre challenge y mutación", async () => {
    const headers = {
      "Idempotency-Key": "00000000-0000-4000-8000-000000000001",
      "X-Step-Up-Token": "one-shot-proof",
    };
    const request = {
      status: "SUSPENDED" as const,
      expectedVersion: 4,
      reason: "Revisión operativa",
    };

    await platformApi.changeTenantStatus("tenant-1", request, headers);
    expect(client.patch).toHaveBeenCalledWith(
      "/platform/tenants/tenant-1/status",
      request,
      { headers },
    );

    await platformApi.createStepUpChallenge({
      action: "TENANT_STATUS",
      targetType: "TENANT",
      targetId: "tenant-1",
      idempotencyKey: headers["Idempotency-Key"],
    });
    expect(client.post).toHaveBeenLastCalledWith(
      "/platform/auth/step-up/challenges",
      expect.objectContaining({
        action: "TENANT_STATUS",
        targetType: "TENANT",
        targetId: "tenant-1",
        idempotencyKey: headers["Idempotency-Key"],
      }),
    );
  });

  it("no agrega un proof vacío a una mutación inicial", async () => {
    await platformApi.grantAdmin(
      { usuarioId: 17 },
      { "Idempotency-Key": "00000000-0000-4000-8000-000000000002" },
    );

    expect(client.post).toHaveBeenCalledWith(
      "/platform/admins",
      { usuarioId: 17 },
      { headers: { "Idempotency-Key": "00000000-0000-4000-8000-000000000002" } },
    );
  });

  it("mantiene el wrapper one-time del alta de membership", async () => {
    const response = {
      membership: { id: "membership-1", tenantId: "tenant-1" },
      activation: { token: "one-time-token", expiresAt: "2026-08-13T00:00:00Z" },
      replayed: false,
    };
    client.post.mockResolvedValueOnce({ data: response });

    const result = await platformApi.createMembership(
      "tenant-1",
      { identity: { mode: "NEW", nombreUsuario: "new-admin" }, roles: ["CAJA"] },
      { "Idempotency-Key": "membership-request" },
    );

    expect(result).toEqual(response);
    expect(client.post).toHaveBeenCalledWith(
      "/platform/tenants/tenant-1/memberships",
      { identity: { mode: "NEW", nombreUsuario: "new-admin" }, roles: ["CAJA"] },
      { headers: { "Idempotency-Key": "membership-request" } },
    );
  });

  it("mapea las lecturas restantes sin filtrar valores vacíos ni espacios de búsqueda", async () => {
    const tenant = { id: "tenant-1", name: "Centro", status: "ACTIVE" };
    const memberships = { content: [{ id: "membership-1" }] };
    const roles = [{ code: "ADMINISTRADOR" }];
    const identities = [{ id: 17, nombreUsuario: "admin" }];
    const admins = { content: [{ usuarioId: 17 }] };

    client.get
      .mockResolvedValueOnce({ data: tenant })
      .mockResolvedValueOnce({ data: memberships })
      .mockResolvedValueOnce({ data: roles })
      .mockResolvedValueOnce({ data: identities })
      .mockResolvedValueOnce({ data: admins });

    await expect(platformApi.getTenant("tenant-1")).resolves.toBe(tenant);
    await expect(platformApi.listMemberships("tenant-1", {
      page: 1,
      size: 10,
      q: "",
      status: "",
    })).resolves.toBe(memberships);
    await expect(platformApi.listRoles("tenant-1")).resolves.toBe(roles);
    await expect(platformApi.searchIdentities("  admin  ")).resolves.toBe(identities);
    await expect(platformApi.listAdmins({ page: 0, size: 25, q: "admin", status: "ACTIVE" }))
      .resolves.toBe(admins);

    expect(client.get).toHaveBeenNthCalledWith(1, "/platform/tenants/tenant-1");
    expect(client.get).toHaveBeenNthCalledWith(
      2,
      "/platform/tenants/tenant-1/memberships?page=1&size=10",
    );
    expect(client.get).toHaveBeenNthCalledWith(3, "/platform/tenants/tenant-1/roles");
    expect(client.get).toHaveBeenNthCalledWith(4, "/platform/identities?q=admin");
    expect(client.get).toHaveBeenNthCalledWith(
      5,
      "/platform/admins?page=0&size=25&q=admin&status=ACTIVE",
    );
  });

  it("mapea cada mutación privilegiada con payload, destino y proof exactos", async () => {
    const headers = {
      "Idempotency-Key": "00000000-0000-4000-8000-000000000010",
      "X-Step-Up-Token": "proof-10",
    };
    const responses = Array.from({ length: 8 }, (_, index) => ({ operation: index + 1 }));
    client.post
      .mockResolvedValueOnce({ data: responses[0] })
      .mockResolvedValueOnce({ data: responses[1] })
      .mockResolvedValueOnce({ data: responses[6] })
      .mockResolvedValueOnce({ data: responses[7] });
    client.patch
      .mockResolvedValueOnce({ data: responses[2] })
      .mockResolvedValueOnce({ data: responses[4] })
      .mockResolvedValueOnce({ data: responses[5] });
    client.put.mockResolvedValueOnce({ data: responses[3] });

    const activation = { token: "activation-token", password: "strong-password" };
    const tenantRequest = {
      code: "CENTRO",
      name: "Centro",
      initialAdmin: { mode: "EXISTING" as const, usuarioId: 17 },
    };
    const updateTenant = { name: "Centro actualizado", expectedVersion: 2 };
    const updateRoles = { roles: ["ADMINISTRADOR"], expectedVersion: 3 };
    const membershipStatus = { status: "REVOKED" as const, expectedVersion: 4, reason: "Baja" };
    const adminStatus = { status: "REVOKED" as const, expectedVersion: 5, reason: "Baja" };

    await expect(platformApi.activateIdentity(activation)).resolves.toBe(responses[0]);
    await expect(platformApi.createTenant(tenantRequest, headers)).resolves.toBe(responses[1]);
    await expect(platformApi.updateTenant("tenant-1", updateTenant, headers)).resolves.toBe(responses[2]);
    await expect(platformApi.updateMembershipRoles(
      "tenant-1",
      "membership-1",
      updateRoles,
      headers,
    )).resolves.toBe(responses[3]);
    await expect(platformApi.changeMembershipStatus(
      "tenant-1",
      "membership-1",
      membershipStatus,
      headers,
    )).resolves.toBe(responses[4]);
    await expect(platformApi.changeAdminStatus(17, adminStatus, headers)).resolves.toBe(responses[5]);
    await expect(platformApi.resetAdminMfa(17, headers)).resolves.toBe(responses[6]);
    await expect(platformApi.verifyStepUpChallenge("challenge-1", "123456"))
      .resolves.toBe(responses[7]);

    expect(client.post).toHaveBeenNthCalledWith(1, "/platform/identity/activate", activation);
    expect(client.post).toHaveBeenNthCalledWith(2, "/platform/tenants", tenantRequest, { headers });
    expect(client.patch).toHaveBeenNthCalledWith(
      1,
      "/platform/tenants/tenant-1",
      updateTenant,
      { headers },
    );
    expect(client.put).toHaveBeenCalledWith(
      "/platform/tenants/tenant-1/memberships/membership-1/roles",
      updateRoles,
      { headers },
    );
    expect(client.patch).toHaveBeenNthCalledWith(
      2,
      "/platform/tenants/tenant-1/memberships/membership-1/status",
      membershipStatus,
      { headers },
    );
    expect(client.patch).toHaveBeenNthCalledWith(
      3,
      "/platform/admins/17/status",
      adminStatus,
      { headers },
    );
    expect(client.post).toHaveBeenNthCalledWith(
      3,
      "/platform/admins/17/mfa/reset",
      {},
      { headers },
    );
    expect(client.post).toHaveBeenNthCalledWith(
      4,
      "/platform/auth/step-up/challenges/challenge-1/verify",
      { code: "123456" },
    );
  });

  it("genera la idempotency key con el generador criptográfico del navegador", () => {
    const expected = "00000000-0000-4000-8000-000000000099";
    const randomUUID = vi.spyOn(crypto, "randomUUID").mockReturnValue(expected);

    expect(newIdempotencyKey()).toBe(expected);
    expect(randomUUID).toHaveBeenCalledOnce();
  });
});
