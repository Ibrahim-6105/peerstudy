// PeerStudy hosted Supabase acceptance test.
//
// Run this only against the dedicated PeerStudy test project. The script uses
// real Auth, PostgREST, Storage, RPC, and Edge Function HTTP endpoints. It
// creates two short-lived Students because a private report cannot target the
// reporter's own content. Every temporary row, object, and Auth identity is
// removed in `finally`, even when a test fails.

// Describe the small result format printed at the end of the run.
type ResultStatus = "PASS" | "FAIL" | "BLOCKED";

// Keep result details free of tokens, passwords, e-mail addresses, and UUIDs.
type TestResult = {
  name: string;
  status: ResultStatus;
  detail: string;
};

// Describe the parsed response returned by the safe HTTP helper.
type ApiResponse = {
  status: number;
  ok: boolean;
  data: unknown;
  headers: Headers;
};

// Read the hosted project URL without embedding any credential in source.
const supabaseUrl = (process.env.SUPABASE_URL ?? "").trim().replace(/\/$/, "");

// Accept either Supabase's legacy anon key name or its new publishable name.
const publicKey = (
  process.env.SUPABASE_ANON_KEY ??
    process.env.SUPABASE_PUBLISHABLE_KEY ??
    ""
).trim();

// Read the privileged key only from this operator process environment.
const serviceRoleKey = (process.env.SUPABASE_SERVICE_ROLE_KEY ?? "").trim();

// Use the exact test Admin identity requested by the project owner.
const adminEmail = "admin@limu.edu.ly";

// Allow an operator override while retaining the requested phone-test password.
const adminPassword = process.env.PEERSTUDY_ADMIN_PASSWORD ?? "123456";

// Fail before a network request when the secure wrapper omitted a requirement.
if (!supabaseUrl || !publicKey || !serviceRoleKey) {
  throw new Error(
    "SUPABASE_URL, SUPABASE_ANON_KEY (or SUPABASE_PUBLISHABLE_KEY), and " +
      "SUPABASE_SERVICE_ROLE_KEY are required.",
  );
}

// Store concise test evidence without ever logging request headers or bodies.
const results: TestResult[] = [];

// Track temporary resources so cleanup remains safe after a partial failure.
const cleanup = {
  studentUserIds: [] as string[],
  attemptedEmails: [] as string[],
  postIds: [] as string[],
  commentIds: [] as string[],
  reportIds: [] as string[],
  quizIds: [] as string[],
  attemptIds: [] as string[],
  materialIds: [] as string[],
  storagePaths: [] as string[],
  attachmentIds: [] as string[],
  communityStoragePaths: [] as string[],
  auditEntityIds: [] as string[],
};

// Remember whether the main flow failed while still allowing cleanup to run.
let mainFailure: Error | null = null;

// Convert an unknown caught value into a short, non-sensitive message.
function safeError(error: unknown): string {
  const message = error instanceof Error ? error.message : "Unknown test error";
  return message.replace(/[\r\n]+/g, " ").slice(0, 240);
}

// Add one successful acceptance result.
function pass(name: string, detail: string): void {
  results.push({ name, status: "PASS", detail });
}

// Add one intentionally blocked external-integration result.
function blocked(name: string, detail: string): void {
  results.push({ name, status: "BLOCKED", detail });
}

// Add one failed result.
function fail(name: string, detail: string): void {
  results.push({ name, status: "FAIL", detail });
}

// Stop the current flow when an invariant is false.
function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

// Narrow an unknown JSON value to a plain record.
function asRecord(value: unknown): Record<string, unknown> {
  assert(
    typeof value === "object" && value !== null && !Array.isArray(value),
    "The server returned an unexpected object shape.",
  );
  return value as Record<string, unknown>;
}

// Narrow an unknown JSON value to an array.
function asArray(value: unknown): unknown[] {
  assert(Array.isArray(value), "The server returned an unexpected list shape.");
  return value;
}

// PostgREST may represent one composite RPC row as an object or one-item list.
function asSingleRow(value: unknown): Record<string, unknown> {
  if (Array.isArray(value)) {
    assert(value.length === 1, "The server did not return exactly one row.");
    return asRecord(value[0]);
  }
  return asRecord(value);
}

// Extract only a public API error label, never the whole response payload.
function apiMessage(value: unknown): string {
  if (typeof value === "string") return value.slice(0, 160);
  if (typeof value !== "object" || value === null) {
    return "no public error detail";
  }
  const record = value as Record<string, unknown>;
  for (const key of ["code", "message", "msg", "error_description", "error"]) {
    if (typeof record[key] === "string") {
      return String(record[key]).slice(0, 160);
    }
  }
  return "no public error detail";
}

// Parse JSON when possible and otherwise retain only a short plain response.
async function parseResponse(response: Response): Promise<unknown> {
  const text = await response.text();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return text.slice(0, 160);
  }
}

// Send one JSON API request without logging credentials, bodies, or raw output.
async function api(
  path: string,
  options: {
    method?: string;
    key?: string;
    token?: string;
    body?: unknown;
    prefer?: string;
    extraHeaders?: Record<string, string>;
  } = {},
): Promise<ApiResponse> {
  const key = options.key ?? publicKey;
  const headers: Record<string, string> = {
    apikey: key,
    accept: "application/json",
    ...options.extraHeaders,
  };
  if (options.token) headers.authorization = `Bearer ${options.token}`;
  if (options.body !== undefined) headers["content-type"] = "application/json";
  if (options.prefer) headers.prefer = options.prefer;
  const response = await fetch(`${supabaseUrl}${path}`, {
    method: options.method ?? "GET",
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  return {
    status: response.status,
    ok: response.ok,
    data: await parseResponse(response),
    headers: response.headers,
  };
}

// Require a successful response and expose only a safe error label on failure.
function requireOk(response: ApiResponse, operation: string): void {
  assert(
    response.ok,
    `${operation} failed with HTTP ${response.status} (${
      apiMessage(response.data)
    }).`,
  );
}

// Create an authenticated REST/RPC header pair for a normal phone session.
function studentRequest(
  path: string,
  token: string,
  options: Parameters<typeof api>[1] = {},
): Promise<ApiResponse> {
  return api(path, { ...options, key: publicKey, token });
}

// Create an authenticated REST/RPC header pair for the test Admin session.
function adminRequest(
  path: string,
  token: string,
  options: Parameters<typeof api>[1] = {},
): Promise<ApiResponse> {
  return api(path, { ...options, key: publicKey, token });
}

// Use service-role access only for setup verification and guaranteed cleanup.
function serviceRequest(
  path: string,
  options: Parameters<typeof api>[1] = {},
): Promise<ApiResponse> {
  return api(path, {
    ...options,
    key: serviceRoleKey,
    token: serviceRoleKey,
  });
}

// Sign in exactly as the phone does and return only the access token and user id.
async function passwordSignIn(
  email: string,
  password: string,
): Promise<{ accessToken: string; userId: string }> {
  const response = await api("/auth/v1/token?grant_type=password", {
    method: "POST",
    body: { email, password },
  });
  requireOk(response, "Password sign-in");
  const body = asRecord(response.data);
  assert(
    typeof body.access_token === "string",
    "Sign-in returned no access token.",
  );
  const user = asRecord(body.user);
  assert(typeof user.id === "string", "Sign-in returned no user id.");
  return { accessToken: body.access_token, userId: user.id };
}

// Register a real LIMU Student and require the immediate session needed by TC1.
async function signUpStudent(
  email: string,
  fullName: string,
  password: string,
): Promise<{ accessToken: string; userId: string }> {
  cleanup.attemptedEmails.push(email);
  const response = await api("/auth/v1/signup", {
    method: "POST",
    body: { email, password, data: { full_name: fullName } },
  });
  requireOk(response, "Student sign-up");
  const body = asRecord(response.data);
  assert(
    typeof body.access_token === "string",
    "Student sign-up returned no immediate session.",
  );
  const user = asRecord(body.user);
  assert(typeof user.id === "string", "Student sign-up returned no user id.");
  cleanup.studentUserIds.push(user.id);
  return { accessToken: body.access_token, userId: user.id };
}

// Build a small valid single-page PDF without downloading an external fixture.
function makePdf(): Uint8Array {
  // Give the real model enough factual content for ten grounded questions.
  // The previous four-word fixture correctly produced an invalid quiz because
  // ten distinct evidence-based questions could not be made from it.
  const factLines = [
    "PeerStudy is a study platform for university students.",
    "Students sign in using their LIMU university email address.",
    "Administrators choose a fixed academic area and manage departments.",
    "Each department contains one or more subjects.",
    "Each subject owns one matching student community.",
    "Students can create community posts and comments.",
    "Approved PDF materials are stored in private storage.",
    "A generated quiz contains exactly ten questions.",
    "Every quiz question contains exactly four answer options.",
    "Quiz answers are scored securely on the server.",
    "Students can report inappropriate community content.",
    "Dark mode is an optional display preference.",
  ];
  const stream = [
    "BT /F1 11 Tf 54 750 Td",
    ...factLines.flatMap((line, index) => [
      index === 0 ? `(${line}) Tj` : `0 -24 Td (${line}) Tj`,
    ]),
    "ET",
  ].join("\n");
  const encoder = new TextEncoder();
  const objects = [
    "<< /Type /Catalog /Pages 2 0 R >>",
    "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
    "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>",
    `<< /Length ${
      encoder.encode(stream).byteLength
    } >>\nstream\n${stream}\nendstream`,
    "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
  ];
  let source = "%PDF-1.4\n";
  const offsets = [0];
  for (let index = 0; index < objects.length; index += 1) {
    offsets.push(encoder.encode(source).byteLength);
    source += `${index + 1} 0 obj\n${objects[index]}\nendobj\n`;
  }
  const xrefOffset = encoder.encode(source).byteLength;
  source += `xref\n0 ${objects.length + 1}\n`;
  source += "0000000000 65535 f \n";
  for (const offset of offsets.slice(1)) {
    source += `${offset.toString().padStart(10, "0")} 00000 n \n`;
  }
  source += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n`;
  source += `startxref\n${xrefOffset}\n%%EOF\n`;
  return encoder.encode(source);
}

// Calculate the same lowercase SHA-256 representation stored by the app.
async function sha256Hex(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", Uint8Array.from(bytes));
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

// Upload bytes through the same private Storage object endpoint used by clients.
async function uploadPdf(
  path: string,
  bytes: Uint8Array,
  adminToken: string,
): Promise<void> {
  const response = await fetch(
    `${supabaseUrl}/storage/v1/object/subject-materials/${path}`,
    {
      method: "POST",
      headers: {
        apikey: publicKey,
        authorization: `Bearer ${adminToken}`,
        "content-type": "application/pdf",
        "x-upsert": "false",
      },
      body: Uint8Array.from(bytes),
    },
  );
  const responseData = await parseResponse(response);
  assert(
    response.ok,
    `Private PDF upload failed with HTTP ${response.status} (${
      apiMessage(responseData)
    }).`,
  );
}

// Download one private object and retain only status and bytes in memory.
async function downloadPdf(
  path: string,
  token: string,
): Promise<{ status: number; ok: boolean; bytes: Uint8Array }> {
  const response = await fetch(
    `${supabaseUrl}/storage/v1/object/subject-materials/${path}?acceptance_nonce=${crypto.randomUUID()}`,
    {
      headers: {
        apikey: publicKey,
        authorization: `Bearer ${token}`,
        "cache-control": "no-cache",
      },
    },
  );
  const bytes = response.ok
    ? new Uint8Array(await response.arrayBuffer())
    : new Uint8Array();
  return { status: response.status, ok: response.ok, bytes };
}

// Remove one private object with the documented bulk-prefix Storage endpoint.
async function removePdf(path: string, token: string): Promise<void> {
  const response = await api("/storage/v1/object/subject-materials", {
    method: "DELETE",
    token,
    body: { prefixes: [path] },
  });
  requireOk(response, "Private PDF removal");
}

// Upload one Community fixture through the same private insert-only endpoint.
async function uploadCommunityAttachment(
  path: string,
  bytes: Uint8Array,
  mimeType: string,
  token: string,
): Promise<void> {
  const response = await fetch(
    `${supabaseUrl}/storage/v1/object/community-attachments/${path}`,
    {
      method: "POST",
      headers: {
        apikey: publicKey,
        authorization: `Bearer ${token}`,
        "cache-control": "no-store",
        "content-type": mimeType,
        "x-upsert": "false",
      },
      body: Uint8Array.from(bytes),
    },
  );
  const responseData = await parseResponse(response);
  assert(
    response.ok,
    `Community attachment upload failed with HTTP ${response.status} (${
      apiMessage(responseData)
    }).`,
  );
}

// Download one authorized Community object without logging its private path.
async function downloadCommunityAttachment(
  path: string,
  token: string,
): Promise<{ status: number; ok: boolean; bytes: Uint8Array }> {
  const response = await fetch(
    `${supabaseUrl}/storage/v1/object/community-attachments/${path}`,
    {
      headers: {
        apikey: publicKey,
        authorization: `Bearer ${token}`,
        "cache-control": "no-store",
      },
    },
  );
  const bytes = response.ok
    ? new Uint8Array(await response.arrayBuffer())
    : new Uint8Array();
  return { status: response.status, ok: response.ok, bytes };
}

// Service-role existence checking distinguishes RLS denial from physical byte
// deletion without printing the private object or path.
async function communityObjectExistsAsService(path: string): Promise<boolean> {
  const response = await fetch(
    `${supabaseUrl}/storage/v1/object/community-attachments/${path}`,
    {
      headers: {
        apikey: serviceRoleKey,
        authorization: `Bearer ${serviceRoleKey}`,
        "cache-control": "no-store",
      },
    },
  );
  if (response.ok) {
    await response.arrayBuffer();
    return true;
  }
  assert(
    response.status === 400 || response.status === 404,
    `Service Storage check failed with HTTP ${response.status}.`,
  );
  return false;
}

// Call one protected attachment Edge Function as a normal signed-in phone.
function attachmentFunction(
  name: "finalize-community-attachment" | "cleanup-community-attachments",
  token: string,
  body: Record<string, unknown>,
): Promise<ApiResponse> {
  return studentRequest(`/functions/v1/${name}`, token, {
    method: "POST",
    body,
  });
}

// Read a table list through one authenticated Student token.
async function studentRows(path: string, token: string): Promise<unknown[]> {
  const response = await studentRequest(path, token);
  requireOk(response, "Student protected read");
  return asArray(response.data);
}

// Delete matching rows using the service role during the final cleanup pass.
async function cleanupDelete(path: string): Promise<void> {
  const response = await serviceRequest(path, {
    method: "DELETE",
    prefer: "return=minimal",
  });
  if (!response.ok) {
    throw new Error(`Cleanup delete failed with HTTP ${response.status}.`);
  }
}

// Find an Auth identity by e-mail without printing any returned account data.
async function findAuthUserId(email: string): Promise<string | null> {
  for (let page = 1; page <= 20; page += 1) {
    const response = await serviceRequest(
      `/auth/v1/admin/users?page=${page}&per_page=100`,
    );
    requireOk(response, "Auth cleanup lookup");
    const body = asRecord(response.data);
    const users = asArray(body.users);
    for (const value of users) {
      const user = asRecord(value);
      if (
        typeof user.email === "string" &&
        user.email.toLowerCase() === email.toLowerCase()
      ) {
        assert(
          typeof user.id === "string",
          "Auth lookup returned a user without an id.",
        );
        return user.id;
      }
    }
    if (users.length < 100) break;
  }
  return null;
}

// Delete one temporary Auth identity; its Profile is removed by the database FK.
async function deleteAuthUser(userId: string): Promise<void> {
  const response = await serviceRequest(`/auth/v1/admin/users/${userId}`, {
    method: "DELETE",
  });
  if (!response.ok && response.status !== 404) {
    throw new Error(`Auth cleanup failed with HTTP ${response.status}.`);
  }
}

// Run the real hosted acceptance flow inside one portable async entry point.
async function main(): Promise<void> {
  try {
    // Authenticate the pre-created Admin using the requested phone-test credentials.
    const admin = await passwordSignIn(adminEmail, adminPassword);
    const adminProfileResponse = await adminRequest(
      `/rest/v1/profiles?id=eq.${admin.userId}&select=id,role,status,full_name,email`,
      admin.accessToken,
    );
    requireOk(adminProfileResponse, "Admin profile read");
    const adminProfiles = asArray(adminProfileResponse.data);
    assert(adminProfiles.length === 1, "The Admin profile is missing.");
    const adminProfile = asRecord(adminProfiles[0]);
    assert(
      adminProfile.role === "admin",
      "The bootstrap identity is not an Admin.",
    );
    assert(
      adminProfile.status === "active",
      "The bootstrap Admin is not active.",
    );
    pass(
      "Admin authentication",
      "Requested credentials open one active Admin profile.",
    );

    // Prove that public Auth cannot create an account outside the LIMU domain.
    const invalidEmail = `peerstudy.smoke.${Date.now()}@example.com`;
    cleanup.attemptedEmails.push(invalidEmail);
    const rejectedSignup = await api("/auth/v1/signup", {
      method: "POST",
      body: {
        email: invalidEmail,
        password: `RejectA9!${crypto.randomUUID()}`,
        data: { full_name: "Rejected Student" },
      },
    });
    assert(!rejectedSignup.ok, "A non-LIMU public signup was accepted.");
    assert(
      !asRecord(rejectedSignup.data).access_token,
      "A non-LIMU signup unexpectedly received a session.",
    );
    pass(
      "LIMU domain enforcement",
      "Public signup rejects a non-@limu.edu.ly identity.",
    );

    // Create two real temporary Students so one may privately report the other.
    const runTag = `${Date.now()}.${crypto.randomUUID().slice(0, 8)}`;
    const authorEmail = `peerstudy.smoke.author.${runTag}@limu.edu.ly`;
    const reporterEmail = `peerstudy.smoke.reporter.${runTag}@limu.edu.ly`;
    const authorPassword = `AuthorA9!${crypto.randomUUID()}`;
    const reporterPassword = `ReporterA9!${crypto.randomUUID()}`;
    const author = await signUpStudent(
      authorEmail,
      "Hosted Smoke Author",
      authorPassword,
    );
    const reporter = await signUpStudent(
      reporterEmail,
      "Hosted Smoke Reporter",
      reporterPassword,
    );
    const authorProfileRows = await studentRows(
      `/rest/v1/profiles?id=eq.${author.userId}&select=id,role,status,full_name`,
      author.accessToken,
    );
    assert(
      authorProfileRows.length === 1,
      "Student profile creation did not complete.",
    );
    const authorProfile = asRecord(authorProfileRows[0]);
    assert(
      authorProfile.role === "student",
      "Public signup created a non-Student role.",
    );
    assert(
      authorProfile.status === "active",
      "Public signup created an inactive Student.",
    );
    pass(
      "Student authentication",
      "LIMU signup returns an immediate session and active Student profile.",
    );

    // Count the exact hierarchy exposed to a normal active Student through RLS.
    const schools = await studentRows(
      "/rest/v1/schools?select=id,name",
      author.accessToken,
    );
    const areas = await studentRows(
      "/rest/v1/academic_areas?select=id,school_id,code,name",
      author.accessToken,
    );
    const departments = await studentRows(
      "/rest/v1/departments?select=id,area_id,name",
      author.accessToken,
    );
    const subjects = await studentRows(
      "/rest/v1/subjects?select=id,department_id,name",
      author.accessToken,
    );
    // A real test project may contain catalog items added by the owner after
    // initial seeding. Require a usable hierarchy without assuming it is empty.
    assert(schools.length >= 1, "No active School is visible to Students.");
    assert(
      areas.length >= 1,
      "No active Academic Area is visible to Students.",
    );
    assert(
      departments.length >= 1,
      "No active Department is visible to Students.",
    );
    assert(subjects.length >= 1, "No active Subject is visible to Students.");
    const subject = asRecord(subjects[0]);
    assert(typeof subject.id === "string", "The seeded Subject has no id.");
    const subjectId = subject.id;
    pass(
      "Reference catalog",
      "Student RLS exposes a usable School, Area, Department, and Subject hierarchy.",
    );

    // Verify the database-created one-to-one Community for the seeded Subject.
    const communities = await studentRows(
      `/rest/v1/communities?subject_id=eq.${subjectId}&select=id,subject_id`,
      author.accessToken,
    );
    assert(
      communities.length === 1,
      "The Subject does not own exactly one Community.",
    );
    const community = asRecord(communities[0]);
    assert(
      community.id === subjectId,
      "Community id does not equal its Subject id.",
    );
    pass(
      "Subject Community",
      "The seeded Subject owns exactly one matching Community.",
    );

    // Create and edit a persistent post through the Student-only RPC.
    const postCreate = await studentRequest(
      "/rest/v1/rpc/create_community_post",
      author.accessToken,
      {
        method: "POST",
        body: {
          p_subject_id: subjectId,
          p_body: "Hosted acceptance post",
          p_idempotency_key: crypto.randomUUID(),
        },
      },
    );
    requireOk(postCreate, "Community post creation");
    const createdPost = asSingleRow(postCreate.data);
    assert(typeof createdPost.id === "string", "Created post has no id.");
    cleanup.postIds.push(createdPost.id);
    const postEdit = await studentRequest(
      "/rest/v1/rpc/update_community_post",
      author.accessToken,
      {
        method: "POST",
        body: {
          p_post_id: createdPost.id,
          p_expected_version: createdPost.version,
          p_body: "Hosted acceptance post edited",
        },
      },
    );
    requireOk(postEdit, "Community post edit");
    const editedPost = asSingleRow(postEdit.data);
    assert(
      editedPost.body === "Hosted acceptance post edited",
      "Post edit was not persisted.",
    );
    assert(
      editedPost.version === 2,
      "Post optimistic version did not advance.",
    );
    pass(
      "Community post create/edit",
      "The Student created and version-edited a persistent post.",
    );

    // Create and edit a comment under that post through the matching RPCs.
    const commentCreate = await studentRequest(
      "/rest/v1/rpc/create_community_comment",
      author.accessToken,
      {
        method: "POST",
        body: {
          p_subject_id: subjectId,
          p_post_id: createdPost.id,
          p_body: "Hosted acceptance comment",
          p_idempotency_key: crypto.randomUUID(),
        },
      },
    );
    requireOk(commentCreate, "Community comment creation");
    const createdComment = asSingleRow(commentCreate.data);
    assert(typeof createdComment.id === "string", "Created comment has no id.");
    cleanup.commentIds.push(createdComment.id);
    const commentEdit = await studentRequest(
      "/rest/v1/rpc/update_community_comment",
      author.accessToken,
      {
        method: "POST",
        body: {
          p_comment_id: createdComment.id,
          p_expected_version: createdComment.version,
          p_body: "Hosted acceptance comment edited",
        },
      },
    );
    requireOk(commentEdit, "Community comment edit");
    const editedComment = asSingleRow(commentEdit.data);
    assert(
      editedComment.body === "Hosted acceptance comment edited",
      "Comment edit was not persisted.",
    );
    assert(
      editedComment.version === 2,
      "Comment optimistic version did not advance.",
    );
    pass(
      "Community comment create/edit",
      "The Student created and version-edited a persistent comment.",
    );

    // Reserve, upload, server-verify, read, and remove a real Post attachment.
    const postAttachmentBytes = makePdf();
    const postAttachmentReserve = await studentRequest(
      "/rest/v1/rpc/reserve_community_attachment",
      author.accessToken,
      {
        method: "POST",
        body: {
          p_subject_id: subjectId,
          p_target_type: "post",
          p_target_id: createdPost.id,
          p_file_name: "hosted-post-note.pdf",
          p_mime_type: "application/pdf",
          p_size_bytes: postAttachmentBytes.byteLength,
          p_idempotency_key: crypto.randomUUID(),
        },
      },
    );
    requireOk(postAttachmentReserve, "Post attachment reservation");
    const postAttachment = asSingleRow(postAttachmentReserve.data);
    assert(
      typeof postAttachment.id === "string" &&
        typeof postAttachment.storage_path === "string" &&
        postAttachment.status === "uploading",
      "Post attachment reservation shape is invalid.",
    );
    cleanup.attachmentIds.push(postAttachment.id);
    cleanup.communityStoragePaths.push(postAttachment.storage_path);

    // A normal Student must not bypass byte validation through the server-only
    // SQL completion function.
    const directCompletion = await studentRequest(
      "/rest/v1/rpc/complete_community_attachment",
      author.accessToken,
      {
        method: "POST",
        body: {
          p_attachment_id: postAttachment.id,
          p_checksum: "0".repeat(64),
        },
      },
    );
    assert(
      !directCompletion.ok,
      "A Student directly executed the server-only completion RPC.",
    );

    await uploadCommunityAttachment(
      postAttachment.storage_path,
      postAttachmentBytes,
      "application/pdf",
      author.accessToken,
    );
    const postFinalize = await attachmentFunction(
      "finalize-community-attachment",
      author.accessToken,
      { attachment_id: postAttachment.id },
    );
    requireOk(postFinalize, "Post attachment finalization");
    const finalizedPostAttachment = asRecord(
      asRecord(postFinalize.data).attachment,
    );
    assert(
      finalizedPostAttachment.status === "ready" &&
        typeof finalizedPostAttachment.checksum === "string" &&
        finalizedPostAttachment.checksum.length === 64,
      "Post attachment was not byte-verified to ready.",
    );
    const reporterDownload = await downloadCommunityAttachment(
      postAttachment.storage_path,
      reporter.accessToken,
    );
    assert(
      reporterDownload.ok &&
        await sha256Hex(reporterDownload.bytes) ===
          await sha256Hex(postAttachmentBytes),
      "An eligible Student could not download the ready Post attachment.",
    );
    const postAttachmentRead = await studentRows(
      `/rest/v1/community_attachments?id=eq.${postAttachment.id}&status=eq.ready&select=id,status,file_name,checksum`,
      reporter.accessToken,
    );
    assert(
      postAttachmentRead.length === 1,
      "Ready Post attachment metadata is not visible to an eligible Student.",
    );

    const removePostAttachment = await studentRequest(
      "/rest/v1/rpc/remove_community_attachment",
      author.accessToken,
      {
        method: "POST",
        body: {
          p_attachment_id: postAttachment.id,
          p_reason: "Hosted acceptance attachment cleanup",
        },
      },
    );
    requireOk(removePostAttachment, "Post attachment soft removal");
    assert(
      asSingleRow(removePostAttachment.data).status === "removed",
      "Post attachment metadata was not removed.",
    );
    const postAttachmentCleanup = await attachmentFunction(
      "cleanup-community-attachments",
      author.accessToken,
      { attachment_id: postAttachment.id },
    );
    requireOk(postAttachmentCleanup, "Post attachment byte cleanup");
    const removedPostDownload = await downloadCommunityAttachment(
      postAttachment.storage_path,
      author.accessToken,
    );
    assert(
      !removedPostDownload.ok,
      "A removed Post attachment remained downloadable.",
    );
    cleanup.communityStoragePaths = cleanup.communityStoragePaths.filter(
      (value) => value !== postAttachment.storage_path,
    );
    pass(
      "Post attachment lifecycle",
      "Reservation, private upload, verified completion, read, removal, and cleanup passed.",
    );

    // Repeat the real upload/finalization path for a Comment attachment.  It is
    // intentionally retained until the parent Comment deletion test below.
    const commentAttachmentBytes = new TextEncoder().encode(
      "PeerStudy hosted Comment attachment\n",
    );
    const commentAttachmentReserve = await studentRequest(
      "/rest/v1/rpc/reserve_community_attachment",
      author.accessToken,
      {
        method: "POST",
        body: {
          p_subject_id: subjectId,
          p_target_type: "comment",
          p_target_id: createdComment.id,
          p_file_name: "hosted-comment-note.txt",
          p_mime_type: "text/plain",
          p_size_bytes: commentAttachmentBytes.byteLength,
          p_idempotency_key: crypto.randomUUID(),
        },
      },
    );
    requireOk(commentAttachmentReserve, "Comment attachment reservation");
    const commentAttachment = asSingleRow(commentAttachmentReserve.data);
    assert(
      typeof commentAttachment.id === "string" &&
        typeof commentAttachment.storage_path === "string",
      "Comment attachment reservation shape is invalid.",
    );
    cleanup.attachmentIds.push(commentAttachment.id);
    cleanup.communityStoragePaths.push(commentAttachment.storage_path);
    await uploadCommunityAttachment(
      commentAttachment.storage_path,
      commentAttachmentBytes,
      "text/plain",
      author.accessToken,
    );
    const commentFinalize = await attachmentFunction(
      "finalize-community-attachment",
      author.accessToken,
      { attachment_id: commentAttachment.id },
    );
    requireOk(commentFinalize, "Comment attachment finalization");
    assert(
      asRecord(asRecord(commentFinalize.data).attachment).status === "ready",
      "Comment attachment was not byte-verified to ready.",
    );
    const commentDownload = await downloadCommunityAttachment(
      commentAttachment.storage_path,
      reporter.accessToken,
    );
    assert(
      commentDownload.ok,
      "An eligible Student could not download the ready Comment attachment.",
    );
    pass(
      "Comment attachment upload",
      "A Comment attachment reached ready only through protected byte validation.",
    );

    // A different Student cannot attach to, remove from, or clean another
    // Student's active content.
    const crossUserReserve = await studentRequest(
      "/rest/v1/rpc/reserve_community_attachment",
      reporter.accessToken,
      {
        method: "POST",
        body: {
          p_subject_id: subjectId,
          p_target_type: "post",
          p_target_id: createdPost.id,
          p_file_name: "not-owned.txt",
          p_mime_type: "text/plain",
          p_size_bytes: 4,
          p_idempotency_key: crypto.randomUUID(),
        },
      },
    );
    assert(
      !crossUserReserve.ok,
      "A Student reserved an attachment on another author's Post.",
    );
    const crossUserRemove = await studentRequest(
      "/rest/v1/rpc/remove_community_attachment",
      reporter.accessToken,
      {
        method: "POST",
        body: {
          p_attachment_id: commentAttachment.id,
          p_reason: "Unauthorized hosted removal",
        },
      },
    );
    assert(
      !crossUserRemove.ok,
      "A Student removed another author's attachment.",
    );
    const crossUserCleanup = await attachmentFunction(
      "cleanup-community-attachments",
      reporter.accessToken,
      { attachment_id: commentAttachment.id },
    );
    assert(
      !crossUserCleanup.ok,
      "A Student cleaned another author's active attachment.",
    );
    pass(
      "Attachment ownership",
      "Cross-user reservation, removal, and cleanup were all denied.",
    );

    // MIME metadata alone cannot approve a file.  Upload text under a PNG label
    // and prove validation closes metadata and deletes the private object.
    const invalidBytes = new TextEncoder().encode("This is not a PNG file.");
    const invalidReserve = await studentRequest(
      "/rest/v1/rpc/reserve_community_attachment",
      author.accessToken,
      {
        method: "POST",
        body: {
          p_subject_id: subjectId,
          p_target_type: "post",
          p_target_id: createdPost.id,
          p_file_name: "invalid-signature.png",
          p_mime_type: "image/png",
          p_size_bytes: invalidBytes.byteLength,
          p_idempotency_key: crypto.randomUUID(),
        },
      },
    );
    requireOk(invalidReserve, "Invalid attachment reservation");
    const invalidAttachment = asSingleRow(invalidReserve.data);
    assert(
      typeof invalidAttachment.id === "string" &&
        typeof invalidAttachment.storage_path === "string",
      "Invalid attachment reservation shape is invalid.",
    );
    cleanup.attachmentIds.push(invalidAttachment.id);
    cleanup.communityStoragePaths.push(invalidAttachment.storage_path);
    await uploadCommunityAttachment(
      invalidAttachment.storage_path,
      invalidBytes,
      "image/png",
      author.accessToken,
    );
    const invalidFinalize = await attachmentFunction(
      "finalize-community-attachment",
      author.accessToken,
      { attachment_id: invalidAttachment.id },
    );
    assert(
      !invalidFinalize.ok &&
        apiMessage(invalidFinalize.data) === "attachment-integrity-failed",
      "Invalid attachment bytes were not rejected with the safe integrity code.",
    );
    const invalidMetadata = await serviceRequest(
      `/rest/v1/community_attachments?id=eq.${invalidAttachment.id}&select=status,storage_deleted_at`,
    );
    requireOk(invalidMetadata, "Invalid attachment audit read");
    const invalidRows = asArray(invalidMetadata.data);
    assert(
      invalidRows.length === 1,
      "Invalid attachment audit row is missing.",
    );
    const invalidRow = asRecord(invalidRows[0]);
    assert(
      invalidRow.status === "removed" &&
        typeof invalidRow.storage_deleted_at === "string",
      "Invalid attachment was not terminally removed and cleaned.",
    );
    assert(
      !(await communityObjectExistsAsService(invalidAttachment.storage_path)),
      "Invalid attachment bytes remain in private Storage.",
    );
    cleanup.communityStoragePaths = cleanup.communityStoragePaths.filter(
      (value) => value !== invalidAttachment.storage_path,
    );
    pass(
      "Attachment byte validation",
      "A forged PNG label failed magic validation and its bytes were deleted.",
    );

    // Have the second Student privately report the first Student's Comment.
    const reportCreate = await studentRequest(
      "/rest/v1/rpc/create_content_report",
      reporter.accessToken,
      {
        method: "POST",
        body: {
          p_subject_id: subjectId,
          p_target_type: "comment",
          p_target_id: createdComment.id,
          p_parent_id: createdPost.id,
          p_reason: "other",
          p_details:
            "Hosted acceptance report for privacy and workflow testing.",
        },
      },
    );
    requireOk(reportCreate, "Private report creation");
    const createdReport = asSingleRow(reportCreate.data);
    assert(typeof createdReport.id === "string", "Created report has no id.");
    cleanup.reportIds.push(createdReport.id);
    cleanup.auditEntityIds.push(createdReport.id);
    const reporterView = await studentRows(
      `/rest/v1/reports?id=eq.${createdReport.id}&select=id,status,reporter_id`,
      reporter.accessToken,
    );
    const authorView = await studentRows(
      `/rest/v1/reports?id=eq.${createdReport.id}&select=id,status,reporter_id`,
      author.accessToken,
    );
    assert(
      reporterView.length === 1,
      "The reporter cannot read their own private report.",
    );
    assert(
      authorView.length === 0,
      "A different Student can read a private report.",
    );
    pass(
      "Private Student report",
      "Only the reporter (and Admin) can read the pending report.",
    );

    // Confirm Admin queue visibility and resolve the report atomically.
    const adminPending = await adminRequest(
      `/rest/v1/reports?id=eq.${createdReport.id}&status=eq.pending&select=id,status,target_type,target_id`,
      admin.accessToken,
    );
    requireOk(adminPending, "Admin pending report read");
    assert(
      asArray(adminPending.data).length === 1,
      "Admin cannot see the pending report.",
    );
    const reportResolve = await adminRequest(
      "/rest/v1/rpc/admin_resolve_report",
      admin.accessToken,
      {
        method: "POST",
        body: {
          p_report_id: createdReport.id,
          p_action: "dismiss",
          p_resolution_note: "Hosted acceptance verified the report workflow.",
        },
      },
    );
    requireOk(reportResolve, "Admin report resolution");
    const resolvedReport = asSingleRow(reportResolve.data);
    assert(
      resolvedReport.status === "dismissed",
      "Admin resolution did not persist.",
    );
    pass(
      "Admin report resolution",
      "Admin viewed and dismissed one pending report atomically.",
    );

    // Soft-delete the edited comment and post through their author-owned RPCs.
    const commentDelete = await studentRequest(
      "/rest/v1/rpc/delete_community_comment",
      author.accessToken,
      {
        method: "POST",
        body: {
          p_comment_id: createdComment.id,
          p_expected_version: editedComment.version,
          p_reason: "Hosted acceptance cleanup",
        },
      },
    );
    requireOk(commentDelete, "Community comment deletion");
    assert(
      asSingleRow(commentDelete.data).status === "removed",
      "Comment was not soft-removed.",
    );
    const removedCommentAttachment = await serviceRequest(
      `/rest/v1/community_attachments?id=eq.${commentAttachment.id}&select=status`,
    );
    requireOk(removedCommentAttachment, "Comment attachment cascade read");
    assert(
      asRecord(asArray(removedCommentAttachment.data)[0]).status === "removed",
      "Comment removal did not hide its attachment metadata.",
    );
    const commentTargetCleanup = await attachmentFunction(
      "cleanup-community-attachments",
      author.accessToken,
      { target_type: "comment", target_id: createdComment.id },
    );
    requireOk(commentTargetCleanup, "Removed Comment attachment cleanup");
    assert(
      !(await communityObjectExistsAsService(commentAttachment.storage_path)),
      "Removed Comment bytes remain in private Storage.",
    );
    cleanup.communityStoragePaths = cleanup.communityStoragePaths.filter(
      (value) => value !== commentAttachment.storage_path,
    );
    const postDelete = await studentRequest(
      "/rest/v1/rpc/delete_community_post",
      author.accessToken,
      {
        method: "POST",
        body: {
          p_post_id: createdPost.id,
          p_expected_version: editedPost.version,
          p_reason: "Hosted acceptance cleanup",
        },
      },
    );
    requireOk(postDelete, "Community post deletion");
    assert(
      asSingleRow(postDelete.data).status === "removed",
      "Post was not soft-removed.",
    );
    pass(
      "Community delete",
      "Comment/Post removals hid attachments and protected cleanup deleted their bytes.",
    );

    // Restrict the first Student and prove their already-issued token loses data.
    cleanup.auditEntityIds.push(author.userId);
    const restrict = await adminRequest(
      "/rest/v1/rpc/admin_set_user_status",
      admin.accessToken,
      {
        method: "POST",
        body: {
          p_profile_id: author.userId,
          p_status: "restricted",
          p_reason: "Hosted acceptance restriction check",
        },
      },
    );
    requireOk(restrict, "Admin Student restriction");
    assert(
      asSingleRow(restrict.data).status === "restricted",
      "Student restriction was not persisted.",
    );
    const deniedCatalog = await studentRequest(
      "/rest/v1/schools?select=id",
      author.accessToken,
    );
    requireOk(deniedCatalog, "Restricted-token catalog request");
    assert(
      asArray(deniedCatalog.data).length === 0,
      "A restricted old token still sees protected catalog rows.",
    );
    pass(
      "Immediate account restriction",
      "The already-issued Student token immediately sees zero protected rows.",
    );

    // Reactivate the Student and prove the same session is governed by live state.
    const reactivate = await adminRequest(
      "/rest/v1/rpc/admin_set_user_status",
      admin.accessToken,
      {
        method: "POST",
        body: {
          p_profile_id: author.userId,
          p_status: "active",
          p_reason: "Hosted acceptance reactivation",
        },
      },
    );
    requireOk(reactivate, "Admin Student reactivation");
    assert(
      asSingleRow(reactivate.data).status === "active",
      "Student reactivation was not persisted.",
    );
    const restoredCatalog = await studentRows(
      "/rest/v1/schools?select=id",
      author.accessToken,
    );
    assert(
      restoredCatalog.length === 1,
      "Reactivated Student access was not restored.",
    );
    pass(
      "Account reactivation",
      "The same Student session regains access after Admin reactivation.",
    );

    // Prove anonymous calls cannot read protected catalog or private answer data.
    const anonymousCatalog = await api("/rest/v1/schools?select=id", {
      key: publicKey,
    });
    assert(
      !anonymousCatalog.ok,
      "An unauthenticated request read the protected catalog.",
    );
    const anonymousAnswers = await api("/rest/v1/quizzes?select=id,questions", {
      key: publicKey,
    });
    assert(
      !anonymousAnswers.ok,
      "An unauthenticated request read private quiz questions.",
    );
    const studentAnswers = await studentRequest(
      "/rest/v1/quizzes?select=id,questions",
      author.accessToken,
    );
    requireOk(studentAnswers, "Student private quiz table check");
    assert(
      asArray(studentAnswers.data).length === 0,
      "A Student directly read private quiz answer rows.",
    );
    const forbiddenQuizInsert = await studentRequest(
      "/rest/v1/quizzes",
      author.accessToken,
      {
        method: "POST",
        body: {
          subject_id: subjectId,
          material_id: crypto.randomUUID(),
          created_by: author.userId,
          title: "Forbidden direct quiz",
          questions: [],
          model_name: "forbidden",
          idempotency_key: crypto.randomUUID(),
        },
      },
    );
    assert(
      !forbiddenQuizInsert.ok,
      "A Student directly inserted a private quiz row.",
    );
    pass(
      "Protected quiz answers",
      "Anonymous and Student clients cannot directly read or write answer-key rows.",
    );

    // Upload one real PDF fixture and record its private Material lifecycle.
    const pdfBytes = makePdf();
    const storagePath = `${subjectId}/${crypto.randomUUID()}.pdf`;
    cleanup.storagePaths.push(storagePath);
    await uploadPdf(storagePath, pdfBytes, admin.accessToken);
    const checksum = await sha256Hex(pdfBytes);
    const materialInsert = await adminRequest(
      "/rest/v1/subject_materials",
      admin.accessToken,
      {
        method: "POST",
        prefer: "return=representation",
        body: {
          subject_id: subjectId,
          uploaded_by: admin.userId,
          title: "Hosted acceptance material",
          summary: "Temporary real PDF used only by the hosted acceptance run.",
          storage_path: storagePath,
          mime_type: "application/pdf",
          size_bytes: pdfBytes.byteLength,
          status: "uploading",
          version: 1,
          display_order: 999,
        },
      },
    );
    requireOk(materialInsert, "Material metadata creation");
    const material = asSingleRow(materialInsert.data);
    assert(typeof material.id === "string", "Material metadata has no id.");
    cleanup.materialIds.push(material.id);
    const preApprovalDownload = await downloadPdf(
      storagePath,
      author.accessToken,
    );
    assert(
      !preApprovalDownload.ok,
      "A Student downloaded an unapproved private Material.",
    );
    const materialApprove = await adminRequest(
      `/rest/v1/subject_materials?id=eq.${material.id}`,
      admin.accessToken,
      {
        method: "PATCH",
        prefer: "return=representation",
        body: {
          status: "approved",
          checksum,
          approved_by: admin.userId,
          approved_at: new Date().toISOString(),
        },
      },
    );
    requireOk(materialApprove, "Material approval");
    assert(
      asSingleRow(materialApprove.data).status === "approved",
      "Material approval did not persist.",
    );
    const approvedDownload = await downloadPdf(storagePath, author.accessToken);
    assert(
      approvedDownload.ok,
      "A Student cannot download an approved private Material.",
    );
    assert(
      approvedDownload.bytes.byteLength === pdfBytes.byteLength,
      "Downloaded PDF size changed.",
    );
    assert(
      (await sha256Hex(approvedDownload.bytes)) === checksum,
      "Downloaded PDF checksum changed.",
    );
    pass(
      "Private Material approval",
      "Unapproved download is denied; approved PDF bytes download intact.",
    );

    // Call the deployed AI function; absence of its real provider key is BLOCKED.
    const quizFunction = await studentRequest(
      "/functions/v1/generate-quiz",
      author.accessToken,
      {
        method: "POST",
        body: {
          subject_id: subjectId,
          material_id: material.id,
          idempotency_key: crypto.randomUUID(),
        },
      },
    );
    if (quizFunction.ok) {
      const quiz = asRecord(quizFunction.data);
      assert(
        typeof quiz.quiz_id === "string",
        "AI generation returned no quiz id.",
      );
      cleanup.quizIds.push(quiz.quiz_id);
      const questions = asArray(quiz.questions);
      assert(
        questions.length === 10,
        "AI generation did not return exactly 10 questions.",
      );
      for (const value of questions) {
        const question = asRecord(value);
        assert(
          question.correct_index === undefined,
          "Pre-submit AI payload exposed a correct answer.",
        );
        assert(
          question.explanation === undefined,
          "Pre-submit AI payload exposed an explanation.",
        );
      }
      const submit = await studentRequest(
        "/functions/v1/submit-quiz",
        author.accessToken,
        {
          method: "POST",
          body: {
            quiz_id: quiz.quiz_id,
            answers: Array.from({ length: 10 }, () => 0),
            idempotency_key: crypto.randomUUID(),
          },
        },
      );
      requireOk(submit, "AI quiz submission");
      const attempt = asRecord(submit.data);
      assert(
        typeof attempt.attempt_id === "string",
        "Quiz submission returned no attempt id.",
      );
      cleanup.attemptIds.push(attempt.attempt_id);
      assert(
        attempt.total === 10,
        "Quiz submission did not score exactly 10 answers.",
      );
      assert(
        asArray(attempt.corrections).length === 10,
        "Quiz corrections are incomplete.",
      );
      pass(
        "External AI quiz",
        "Real provider generation returned 10 safe questions and server scoring.",
      );
    } else {
      const functionBody = asRecord(quizFunction.data);
      const functionCode = typeof functionBody.code === "string"
        ? functionBody.code
        : "unknown-code";
      throw new Error(
        `AI generation failed with HTTP ${quizFunction.status} ` +
          `(${functionCode}: ${apiMessage(functionBody)}).`,
      );
    }

    // Remove metadata first so Student access stops before deleting the bytes.
    const materialRemove = await adminRequest(
      `/rest/v1/subject_materials?id=eq.${material.id}`,
      admin.accessToken,
      {
        method: "PATCH",
        prefer: "return=representation",
        body: {
          status: "removed",
          removal_reason: "Hosted acceptance cleanup",
          removed_at: new Date().toISOString(),
        },
      },
    );
    requireOk(materialRemove, "Material removal state");
    assert(
      asSingleRow(materialRemove.data).status === "removed",
      "Material removal did not persist.",
    );
    const removedDownload = await downloadPdf(storagePath, author.accessToken);
    assert(!removedDownload.ok, "A Student downloaded a removed Material.");
    await removePdf(storagePath, admin.accessToken);
    cleanup.storagePaths = cleanup.storagePaths.filter(
      (value) => value !== storagePath,
    );
    pass(
      "Private Material removal",
      "Metadata denial happened before the private Storage object was deleted.",
    );
  } catch (error) {
    mainFailure = error instanceof Error
      ? error
      : new Error("Unknown hosted acceptance failure");
    fail("Hosted acceptance flow", safeError(error));
  } finally {
    // Collect cleanup problems but continue through every independent resource.
    const cleanupErrors: string[] = [];
    const attemptCleanup = async (work: () => Promise<void>): Promise<void> => {
      try {
        await work();
      } catch (error) {
        cleanupErrors.push(safeError(error));
      }
    };

    // Delete quiz dependants before the private Material that they reference.
    for (const userId of cleanup.studentUserIds) {
      await attemptCleanup(() =>
        cleanupDelete(`/rest/v1/quiz_attempts?student_id=eq.${userId}`)
      );
      await attemptCleanup(() =>
        cleanupDelete(`/rest/v1/quizzes?created_by=eq.${userId}`)
      );
    }

    // Delete reports before their target Comments and Posts.
    for (const reportId of cleanup.reportIds) {
      await attemptCleanup(() =>
        cleanupDelete(`/rest/v1/reports?id=eq.${reportId}`)
      );
    }
    for (const userId of cleanup.studentUserIds) {
      await attemptCleanup(() =>
        cleanupDelete(`/rest/v1/reports?reporter_id=eq.${userId}`)
      );
    }

    // Delete any stranded Community bytes before their retained audit metadata.
    for (const storagePath of cleanup.communityStoragePaths) {
      await attemptCleanup(async () => {
        const response = await api("/storage/v1/object/community-attachments", {
          method: "DELETE",
          key: serviceRoleKey,
          token: serviceRoleKey,
          body: { prefixes: [storagePath] },
        });
        if (!response.ok) {
          throw new Error(
            `Community Storage cleanup failed with HTTP ${response.status}.`,
          );
        }
      });
    }
    for (const attachmentId of cleanup.attachmentIds) {
      await attemptCleanup(() =>
        cleanupDelete(
          `/rest/v1/community_attachments?id=eq.${attachmentId}`,
        )
      );
    }

    for (const commentId of cleanup.commentIds) {
      await attemptCleanup(() =>
        cleanupDelete(`/rest/v1/community_comments?id=eq.${commentId}`)
      );
    }
    for (const postId of cleanup.postIds) {
      await attemptCleanup(() =>
        cleanupDelete(`/rest/v1/community_posts?id=eq.${postId}`)
      );
    }

    // Remove any generated quiz rows by explicit id if the provider was enabled.
    for (const attemptId of cleanup.attemptIds) {
      await attemptCleanup(() =>
        cleanupDelete(`/rest/v1/quiz_attempts?id=eq.${attemptId}`)
      );
    }
    for (const quizId of cleanup.quizIds) {
      await attemptCleanup(() =>
        cleanupDelete(`/rest/v1/quizzes?id=eq.${quizId}`)
      );
    }

    // Delete remaining Storage fixtures, then their relational metadata.
    for (const storagePath of cleanup.storagePaths) {
      await attemptCleanup(async () => {
        const response = await api("/storage/v1/object/subject-materials", {
          method: "DELETE",
          key: serviceRoleKey,
          token: serviceRoleKey,
          body: { prefixes: [storagePath] },
        });
        if (!response.ok) {
          throw new Error(
            `Storage cleanup failed with HTTP ${response.status}.`,
          );
        }
      });
    }
    for (const materialId of cleanup.materialIds) {
      await attemptCleanup(() =>
        cleanupDelete(`/rest/v1/subject_materials?id=eq.${materialId}`)
      );
    }

    // Remove only audit rows created for the tracked temporary entities.
    const auditIds = new Set([
      ...cleanup.auditEntityIds,
      ...cleanup.reportIds,
      ...cleanup.studentUserIds,
    ]);
    for (const entityId of auditIds) {
      await attemptCleanup(() =>
        cleanupDelete(`/rest/v1/admin_audit_log?entity_id=eq.${entityId}`)
      );
    }

    // Delete both temporary Auth accounts after all profile references are gone.
    const userIds = new Set(cleanup.studentUserIds);
    for (const email of cleanup.attemptedEmails) {
      await attemptCleanup(async () => {
        const userId = await findAuthUserId(email);
        if (userId) userIds.add(userId);
      });
    }
    for (const userId of userIds) {
      await attemptCleanup(() => deleteAuthUser(userId));
    }

    // Prove all attempted temporary identities are absent after cleanup.
    for (const email of cleanup.attemptedEmails) {
      await attemptCleanup(async () => {
        const remaining = await findAuthUserId(email);
        assert(
          remaining === null,
          "A temporary Auth identity remains after cleanup.",
        );
      });
    }

    // Verify no tracked profile or content row survived the final cleanup.
    for (const userId of userIds) {
      await attemptCleanup(async () => {
        const response = await serviceRequest(
          `/rest/v1/profiles?id=eq.${userId}&select=id`,
        );
        requireOk(response, "Cleanup profile verification");
        assert(
          asArray(response.data).length === 0,
          "A temporary Profile remains after cleanup.",
        );
      });
    }

    // Record one cleanup result rather than printing any temporary identifiers.
    if (cleanupErrors.length === 0) {
      pass(
        "Cleanup evidence",
        "Tracked temporary Auth, data, and files are absent; existing owner data was preserved.",
      );
    } else {
      fail(
        "Cleanup evidence",
        `${cleanupErrors.length} cleanup verification operation(s) failed.`,
      );
    }
  }

  // Count each outcome for the final concise operator report.
  const passCount = results.filter((result) => result.status === "PASS").length;
  const failCount = results.filter((result) => result.status === "FAIL").length;
  const blockedCount = results.filter(
    (result) => result.status === "BLOCKED",
  ).length;

  // Print only named outcomes and safe summaries; credentials never leave memory.
  console.log(
    `Hosted smoke result: ${passCount} PASS, ${failCount} FAIL, ${blockedCount} BLOCKED`,
  );
  for (const result of results) {
    console.log(`${result.status.padEnd(7)} ${result.name}: ${result.detail}`);
  }

  // Return a failing process status for CI while preserving completed cleanup.
  if (mainFailure || failCount > 0) process.exitCode = 1;
}

// Surface an unexpected runner error without ever printing environment values.
void main().catch((error) => {
  console.error(`Hosted smoke runner failed: ${safeError(error)}`);
  process.exitCode = 1;
});
