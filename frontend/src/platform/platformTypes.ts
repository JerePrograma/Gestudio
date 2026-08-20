import type { Page } from "../types/types";

export type PlatformTenantStatus = "ACTIVE" | "SUSPENDED" | "ARCHIVED";
export type MembershipStatus = "ACTIVE" | "SUSPENDED" | "REVOKED";
export type PlatformAdminStatus = "ACTIVE" | "REVOKED";
export type AuditResult = "SUCCESS" | "DENIED" | "FAILED";
export type IdentityMode = "EXISTING" | "NEW";

export type PlatformPage<T> = Page<T>;

export interface PlatformTenantSummary {
  id: string;
  code: string;
  name: string;
  status: PlatformTenantStatus;
  version: number;
  createdAt?: string;
  membershipCount?: number;
}

export interface PlatformTenantDetail extends PlatformTenantSummary {
  updatedAt?: string;
  activeMembershipCount?: number;
  roleCount?: number;
}

export interface InitialAdminRequest {
  mode: IdentityMode;
  usuarioId?: number;
  nombreUsuario?: string;
}

export interface CreateTenantRequest {
  code: string;
  name: string;
  initialAdmin: InitialAdminRequest;
}

export interface ActivationDelivery {
  token: string;
  expiresAt: string;
}

export interface ProvisionedTenantResponse {
  tenant: PlatformTenantDetail;
  initialAdmin: PlatformMembership;
  activation?: ActivationDelivery;
  replayed: boolean;
}

export interface PlatformMembership {
  id: string;
  tenantId: string;
  usuarioId: number;
  nombreUsuario: string;
  status: MembershipStatus;
  roles: string[];
  validFrom: string;
  validUntil?: string | null;
  version: number;
}

export interface CreateMembershipRequest {
  identity: InitialAdminRequest;
  roles: string[];
  validUntil?: string | null;
}

export interface ProvisionedMembershipResponse {
  membership: PlatformMembership;
  activation?: ActivationDelivery | null;
  replayed: boolean;
}

export interface PlatformRole {
  code: string;
  name: string;
  active: boolean;
}

export interface PlatformIdentity {
  id: number;
  nombreUsuario: string;
  active: boolean;
}

export interface PlatformAdmin {
  usuarioId: number;
  nombreUsuario: string;
  status: PlatformAdminStatus;
  mfaEnabled: boolean;
  createdAt?: string;
  revokedAt?: string | null;
  version: number;
}

export interface ProvisionedPlatformAdminResponse {
  admin: PlatformAdmin;
  activation?: ActivationDelivery | null;
}

export interface PlatformActivationRequest {
  token: string;
  password?: string;
  totpSecret?: string;
  totpCode?: string;
}

export interface PlatformActivationResponse {
  recoveryCodes: string[];
}

export interface PlatformAuditEvent {
  id: string;
  occurredAt: string;
  actorId?: number | null;
  actorUsername?: string | null;
  action: string;
  result: AuditResult;
  targetType?: string | null;
  targetId?: string | null;
  tenantId?: string | null;
  correlationId: string;
  detail?: string | null;
}

export interface PageFilters {
  page: number;
  size: number;
}

export interface TenantFilters extends PageFilters {
  q?: string;
  status?: PlatformTenantStatus | "";
}

export interface MembershipFilters extends PageFilters {
  q?: string;
  status?: MembershipStatus | "";
}

export interface AdminFilters extends PageFilters {
  q?: string;
  status?: PlatformAdminStatus | "";
}

export interface AuditFilters extends PageFilters {
  tenantId?: string;
  actor?: string;
  action?: string;
  result?: AuditResult | "";
  from?: string;
  to?: string;
  correlationId?: string;
}

export interface StepUpDescriptor {
  action: string;
  targetType: string;
  targetId: string;
  idempotencyKey: string;
}

export interface StepUpChallenge {
  challengeId: string;
  expiresAt: string;
}

export interface StepUpProof {
  stepUpToken: string;
  expiresAt: string;
}

export interface StepUpHeaders {
  "Idempotency-Key": string;
  "X-Step-Up-Token"?: string;
}
