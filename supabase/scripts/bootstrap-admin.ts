// Explicit operator script for the test Admin requested by the FYP owner.
// Run only after migrations; never place the service-role key in source control.

import { createClient } from "npm:@supabase/supabase-js@2";

// A confirmation flag prevents an accidental account/password reset.
if (Deno.env.get("CONFIRM_BOOTSTRAP_ADMIN") !== "YES") {
  throw new Error("Set CONFIRM_BOOTSTRAP_ADMIN=YES to bootstrap the test Admin.");
}

// Supabase Auth signs in with email; Flutter maps the requested name `admin`
// to this LIMU-domain identity without exposing the mapping on Student signup.
const adminEmail = "admin@limu.edu.ly";
const adminName = "admin";
const adminPassword = Deno.env.get("PEERSTUDY_ADMIN_PASSWORD")?.trim() || "123456";
const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim() || "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim() || "";

// Fail before a network request when required operator secrets are absent.
if (!supabaseUrl || !serviceRoleKey) {
  throw new Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.");
}
if (adminPassword.length < 6) {
  throw new Error("PEERSTUDY_ADMIN_PASSWORD must contain at least 6 characters.");
}

// This privileged client exists only in the operator process running the file.
const supabase = createClient(supabaseUrl, serviceRoleKey, {
  auth: {
    autoRefreshToken: false,
    detectSessionInUrl: false,
    persistSession: false,
  },
});

// Locate an existing bootstrap identity without printing any private user data.
let adminUserId = "";
for (let page = 1; page <= 100 && !adminUserId; page += 1) {
  const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 100 });
  if (error) throw new Error(`Admin lookup failed: ${error.message}`);
  const existing = data.users.find((user) => user.email?.toLowerCase() === adminEmail);
  if (existing) adminUserId = existing.id;
  if (data.users.length < 100) break;
}

// Create a fresh Auth user or reset only this explicitly named test identity.
if (!adminUserId) {
  const { data, error } = await supabase.auth.admin.createUser({
    email: adminEmail,
    password: adminPassword,
    email_confirm: true,
    user_metadata: { full_name: adminName },
  });
  if (error || !data.user) {
    throw new Error(`Admin creation failed: ${error?.message ?? "missing user"}`);
  }
  adminUserId = data.user.id;
} else {
  const { error } = await supabase.auth.admin.updateUserById(adminUserId, {
    password: adminPassword,
    email_confirm: true,
    user_metadata: { full_name: adminName },
  });
  if (error) throw new Error(`Admin credential reset failed: ${error.message}`);
}

// Public signup always creates a Student; only this service-side operator step
// promotes the reviewed bootstrap identity to the Admin role.
const { error: profileError } = await supabase
  .from("profiles")
  .update({
    full_name: adminName,
    role: "admin",
    status: "active",
    restricted_at: null,
    restricted_by: null,
    restriction_reason: null,
  })
  .eq("id", adminUserId);
if (profileError) throw new Error(`Admin profile promotion failed: ${profileError.message}`);

// Never print the password or service-role key into shell history/log output.
console.log("PeerStudy test Admin is ready. Sign in with username: admin");
