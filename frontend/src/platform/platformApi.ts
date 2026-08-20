import api from "../api/axiosConfig";
import type {
  ActivationDelivery,
  AdminFilters,
  AuditFilters,
  CreateMembershipRequest,
  CreateTenantRequest,
  MembershipFilters,
  MembershipStatus,
  PlatformAdmin,
  PlatformActivationRequest,
  PlatformActivationResponse,
  PlatformAdminStatus,
  PlatformAuditEvent,
  PlatformIdentity,
  PlatformMembership,
  PlatformPage,
  PlatformRole,
  PlatformTenantDetail,
  PlatformTenantStatus,
  PlatformTenantSummary,
  ProvisionedTenantResponse,
  ProvisionedMembershipResponse,
  ProvisionedPlatformAdminResponse,
  StepUpChallenge,
  StepUpDescriptor,
  StepUpHeaders,
  StepUpProof,
  TenantFilters,
} from "./platformTypes";

const params = (values: object): URLSearchParams => {
  const result = new URLSearchParams();
  Object.entries(values).forEach(([key, value]) => {
    if (value !== undefined && value !== "") result.set(key, String(value));
  });
  return result;
};

const requestHeaders = (headers: StepUpHeaders): Record<string, string> => ({
  "Idempotency-Key": headers["Idempotency-Key"],
  ...(headers["X-Step-Up-Token"]
    ? { "X-Step-Up-Token": headers["X-Step-Up-Token"] }
    : {}),
});

export const newIdempotencyKey = (): string => crypto.randomUUID();

export const platformApi = {
  async activateIdentity(request: PlatformActivationRequest): Promise<PlatformActivationResponse> {
    const { data } = await api.post<PlatformActivationResponse>(
      "/platform/identity/activate",
      request,
    );
    return data;
  },

  async listTenants(filters: TenantFilters): Promise<PlatformPage<PlatformTenantSummary>> {
    const { data } = await api.get<PlatformPage<PlatformTenantSummary>>(
      `/platform/tenants?${params(filters)}`,
    );
    return data;
  },

  async getTenant(tenantId: string): Promise<PlatformTenantDetail> {
    const { data } = await api.get<PlatformTenantDetail>(`/platform/tenants/${tenantId}`);
    return data;
  },

  async createTenant(
    request: CreateTenantRequest,
    headers: StepUpHeaders,
  ): Promise<ProvisionedTenantResponse> {
    const { data } = await api.post<ProvisionedTenantResponse>(
      "/platform/tenants",
      request,
      { headers: requestHeaders(headers) },
    );
    return data;
  },

  async updateTenant(
    tenantId: string,
    request: { name: string; expectedVersion: number },
    headers: StepUpHeaders,
  ): Promise<PlatformTenantDetail> {
    const { data } = await api.patch<PlatformTenantDetail>(
      `/platform/tenants/${tenantId}`,
      request,
      { headers: requestHeaders(headers) },
    );
    return data;
  },

  async changeTenantStatus(
    tenantId: string,
    request: { status: PlatformTenantStatus; expectedVersion: number; reason: string },
    headers: StepUpHeaders,
  ): Promise<PlatformTenantDetail> {
    const { data } = await api.patch<PlatformTenantDetail>(
      `/platform/tenants/${tenantId}/status`,
      request,
      { headers: requestHeaders(headers) },
    );
    return data;
  },

  async listMemberships(
    tenantId: string,
    filters: MembershipFilters,
  ): Promise<PlatformPage<PlatformMembership>> {
    const { data } = await api.get<PlatformPage<PlatformMembership>>(
      `/platform/tenants/${tenantId}/memberships?${params(filters)}`,
    );
    return data;
  },

  async createMembership(
    tenantId: string,
    request: CreateMembershipRequest,
    headers: StepUpHeaders,
  ): Promise<ProvisionedMembershipResponse> {
    const { data } = await api.post<ProvisionedMembershipResponse>(
      `/platform/tenants/${tenantId}/memberships`,
      request,
      { headers: requestHeaders(headers) },
    );
    return data;
  },

  async updateMembershipRoles(
    tenantId: string,
    membershipId: string,
    request: { roles: string[]; expectedVersion: number },
    headers: StepUpHeaders,
  ): Promise<PlatformMembership> {
    const { data } = await api.put<PlatformMembership>(
      `/platform/tenants/${tenantId}/memberships/${membershipId}/roles`,
      request,
      { headers: requestHeaders(headers) },
    );
    return data;
  },

  async changeMembershipStatus(
    tenantId: string,
    membershipId: string,
    request: { status: MembershipStatus; expectedVersion: number; reason: string },
    headers: StepUpHeaders,
  ): Promise<PlatformMembership> {
    const { data } = await api.patch<PlatformMembership>(
      `/platform/tenants/${tenantId}/memberships/${membershipId}/status`,
      request,
      { headers: requestHeaders(headers) },
    );
    return data;
  },

  async listRoles(tenantId: string): Promise<PlatformRole[]> {
    const { data } = await api.get<PlatformRole[]>(`/platform/tenants/${tenantId}/roles`);
    return data;
  },

  async searchIdentities(q: string): Promise<PlatformIdentity[]> {
    const { data } = await api.get<PlatformIdentity[]>(
      `/platform/identities?${params({ q: q.trim() })}`,
    );
    return data;
  },

  async listAdmins(filters: AdminFilters): Promise<PlatformPage<PlatformAdmin>> {
    const { data } = await api.get<PlatformPage<PlatformAdmin>>(
      `/platform/admins?${params(filters)}`,
    );
    return data;
  },

  async grantAdmin(
    request: { usuarioId: number },
    headers: StepUpHeaders,
  ): Promise<ProvisionedPlatformAdminResponse> {
    const { data } = await api.post<ProvisionedPlatformAdminResponse>("/platform/admins", request, { headers: requestHeaders(headers) });
    return data;
  },

  async changeAdminStatus(
    usuarioId: number,
    request: { status: PlatformAdminStatus; expectedVersion: number; reason: string },
    headers: StepUpHeaders,
  ): Promise<PlatformAdmin> {
    const { data } = await api.patch<PlatformAdmin>(
      `/platform/admins/${usuarioId}/status`,
      request,
      { headers: requestHeaders(headers) },
    );
    return data;
  },

  async resetAdminMfa(usuarioId: number, headers: StepUpHeaders): Promise<ActivationDelivery> {
    const { data } = await api.post<ActivationDelivery>(
      `/platform/admins/${usuarioId}/mfa/reset`,
      {},
      { headers: requestHeaders(headers) },
    );
    return data;
  },

  async listAudit(filters: AuditFilters): Promise<PlatformPage<PlatformAuditEvent>> {
    const { data } = await api.get<PlatformPage<PlatformAuditEvent>>(
      `/platform/audit?${params(filters)}`,
    );
    return data;
  },

  async createStepUpChallenge(descriptor: StepUpDescriptor): Promise<StepUpChallenge> {
    const { data } = await api.post<StepUpChallenge>(
      "/platform/auth/step-up/challenges",
      descriptor,
    );
    return data;
  },

  async verifyStepUpChallenge(challengeId: string, code: string): Promise<StepUpProof> {
    const { data } = await api.post<StepUpProof>(
      `/platform/auth/step-up/challenges/${challengeId}/verify`,
      { code },
    );
    return data;
  },
};
