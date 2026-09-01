// Shared, small HTTP/authentication helpers for PeerStudy Edge Functions.
// Service-role and AI secrets are read only inside Supabase's server runtime.

import {
  createClient,
  type SupabaseClient,
  type User,
} from "npm:@supabase/supabase-js@2";

// ApiError carries a safe message that may be returned to the signed-in app.
export class ApiError extends Error {
  constructor(
    public readonly status: number,
    message: string,
    public readonly code: string,
  ) {
    super(message);
    this.name = "ApiError";
  }
}

// Each request has one correlation ID without exposing provider internals.
export function requestId(request: Request): string {
  const supplied = request.headers.get("x-request-id")?.trim() ?? "";
  return supplied.length >= 8 && supplied.length <= 100
    ? supplied
    : crypto.randomUUID();
}

// Browser clients need CORS; native Flutter clients safely ignore it.
export function responseHeaders(request: Request): HeadersInit {
  const configuredOrigin = Deno.env.get("ALLOWED_ORIGIN")?.trim() || "*";
  const requestOrigin = request.headers.get("origin")?.trim() || "";
  const allowedOrigin = configuredOrigin === "*"
    ? "*"
    : requestOrigin === configuredOrigin
    ? configuredOrigin
    : configuredOrigin;
  return {
    "access-control-allow-origin": allowedOrigin,
    "access-control-allow-headers":
      "authorization, apikey, content-type, x-client-info, x-request-id",
    "access-control-allow-methods": "POST, OPTIONS",
    "cache-control": "no-store",
    "content-type": "application/json; charset=utf-8",
    "vary": "Origin",
    "x-content-type-options": "nosniff",
  };
}

// Preflight requests finish before authentication or database work.
export function preflightResponse(request: Request): Response | null {
  if (request.method !== "OPTIONS") return null;
  return new Response(null, { status: 204, headers: responseHeaders(request) });
}

// All successful and failed payloads use the same JSON response shape rules.
export function jsonResponse(
  request: Request,
  body: unknown,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: responseHeaders(request),
  });
}

// Unexpected errors are logged with correlation only; secrets and PDF bytes
// are never included in a client response or application log.
export function errorResponse(
  request: Request,
  error: unknown,
  correlationId: string,
): Response {
  if (error instanceof ApiError) {
    return jsonResponse(
      request,
      { error: error.message, code: error.code, request_id: correlationId },
      error.status,
    );
  }
  const errorName = error instanceof Error ? error.name : "UnknownError";
  console.error(
    JSON.stringify({ request_id: correlationId, error: errorName }),
  );
  return jsonResponse(
    request,
    {
      error: "The server could not complete this request. Please retry.",
      code: "internal-error",
      request_id: correlationId,
    },
    500,
  );
}

// Read a required server variable without ever returning its value.
export function requiredEnv(name: string): string {
  const value = Deno.env.get(name)?.trim() ?? "";
  if (!value) {
    throw new ApiError(
      503,
      "A required server service is not configured.",
      "server-config",
    );
  }
  return value;
}

// The service client bypasses RLS only inside these reviewed functions. Every
// call authenticates and authorizes the requesting Student before using it.
export function serviceClient(): SupabaseClient {
  return createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    {
      auth: {
        autoRefreshToken: false,
        detectSessionInUrl: false,
        persistSession: false,
      },
    },
  );
}

export interface AuthenticatedRequest {
  service: SupabaseClient;
  user: User;
}

// Gateway JWT checking remains enabled, and this explicit verification avoids
// trusting a decoded-but-unverified user ID inside application logic.
export async function authenticate(
  request: Request,
): Promise<AuthenticatedRequest> {
  const authorization = request.headers.get("authorization")?.trim() ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(authorization);
  if (!match || match[1].length > 4096) {
    throw new ApiError(
      401,
      "Sign in before using this feature.",
      "not-authenticated",
    );
  }

  const service = serviceClient();
  const { data, error } = await service.auth.getUser(match[1]);
  if (error || !data.user) {
    throw new ApiError(
      401,
      "Your session is invalid or expired.",
      "invalid-session",
    );
  }
  return { service, user: data.user };
}

export interface StudentProfile {
  id: string;
  full_name: string;
  role: "student";
  status: "active";
}

// Restricted accounts fail here even if an older access token is still valid.
export async function requireActiveStudent(
  service: SupabaseClient,
  userId: string,
): Promise<StudentProfile> {
  const { data, error } = await service
    .from("profiles")
    .select("id, full_name, role, status")
    .eq("id", userId)
    .maybeSingle();
  if (error) {
    throw new ApiError(
      503,
      "The account could not be verified.",
      "profile-check-failed",
    );
  }
  if (!data || data.role !== "student" || data.status !== "active") {
    throw new ApiError(
      403,
      "This Student account cannot use this feature.",
      "account-restricted",
    );
  }
  return data as StudentProfile;
}

export interface ActiveSubject {
  id: string;
  name: string;
  department_id: string;
  status: "active";
}

// Validate the complete School -> Area -> Department -> Subject path. A child
// cannot remain usable when an Admin has made any parent inactive.
export async function requireActiveSubject(
  service: SupabaseClient,
  subjectId: string,
): Promise<ActiveSubject> {
  const { data: subject, error: subjectError } = await service
    .from("subjects")
    .select("id, name, department_id, status")
    .eq("id", subjectId)
    .maybeSingle();
  if (subjectError) {
    throw new ApiError(
      503,
      "The Subject could not be verified.",
      "subject-check-failed",
    );
  }
  if (!subject || subject.status !== "active") {
    throw new ApiError(
      404,
      "The selected Subject is unavailable.",
      "subject-unavailable",
    );
  }

  const { data: department, error: departmentError } = await service
    .from("departments")
    .select("id, area_id, status")
    .eq("id", subject.department_id)
    .maybeSingle();
  if (departmentError || !department || department.status !== "active") {
    throw new ApiError(
      404,
      "The selected Subject is unavailable.",
      "subject-unavailable",
    );
  }

  const { data: area, error: areaError } = await service
    .from("academic_areas")
    .select("id, school_id, status")
    .eq("id", department.area_id)
    .maybeSingle();
  if (areaError || !area || area.status !== "active") {
    throw new ApiError(
      404,
      "The selected Subject is unavailable.",
      "subject-unavailable",
    );
  }

  const { data: school, error: schoolError } = await service
    .from("schools")
    .select("id, status")
    .eq("id", area.school_id)
    .maybeSingle();
  if (schoolError || !school || school.status !== "active") {
    throw new ApiError(
      404,
      "The selected Subject is unavailable.",
      "subject-unavailable",
    );
  }
  return subject as ActiveSubject;
}

// Edge payloads are intentionally small. PDF bytes are read from private
// Storage, never accepted in a public JSON request.
export async function readJsonObject(
  request: Request,
): Promise<Record<string, unknown>> {
  if (request.method !== "POST") {
    throw new ApiError(405, "Only POST is supported.", "method-not-allowed");
  }
  const contentType = request.headers.get("content-type")?.toLowerCase() ?? "";
  if (!contentType.includes("application/json")) {
    throw new ApiError(
      415,
      "Send an application/json request.",
      "invalid-content-type",
    );
  }
  const declaredLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(declaredLength) && declaredLength > 32768) {
    throw new ApiError(413, "The request is too large.", "request-too-large");
  }
  const text = await request.text();
  if (text.length === 0 || text.length > 32768) {
    throw new ApiError(400, "A small JSON object is required.", "invalid-json");
  }
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new ApiError(400, "The request JSON is invalid.", "invalid-json");
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new ApiError(400, "A JSON object is required.", "invalid-json");
  }
  return value as Record<string, unknown>;
}

// PostgreSQL UUID parsing is strict; validate before issuing a query.
export function requireUuid(value: unknown, field: string): string {
  const text = typeof value === "string" ? value.trim().toLowerCase() : "";
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
      .test(text)
  ) {
    throw new ApiError(
      400,
      `${field} must be a valid UUID.`,
      "invalid-argument",
    );
  }
  return text;
}
