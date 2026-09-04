# Supabase backend reference

This file describes the server contract implemented under `supabase/`. Use [the implementation guide](implementation-guide.md) for the complete beginner setup and [the repository audit](repository-audit.md) for execution evidence.

## Backend files

| File | Purpose |
| --- | --- |
| `supabase/config.toml` | Local ports, Auth redirects, 25 MiB Storage limit, and function JWT verification |
| `supabase/migrations/20260828000100_peerstudy_corrected_master.sql` | Schema, constraints, triggers, functions, policies, Storage, and Realtime |
| `supabase/migrations/20260830000100_community_attachments.sql` | Private post/comment attachment metadata, policies, and Storage bucket |
| `supabase/seed.sql` | Corrected academic reference rows only |
| `supabase/functions/generate-quiz/index.ts` | Protected PDF-to-quiz request |
| `supabase/functions/submit-quiz/index.ts` | Protected scoring and attempt storage |
| `supabase/functions/finalize-community-attachment/index.ts` | Real-byte validation and trusted attachment finalization |
| `supabase/functions/cleanup-community-attachments/index.ts` | Authorized cleanup of already-hidden attachment bytes |
| `supabase/functions/_shared/` | Request, profile, catalog, AI, and validation helpers |
| `supabase/scripts/bootstrap-admin.ts` | Trusted operator bootstrap for the requested test Admin |
| `supabase.example.json` | Flutter-safe public connection template |

The seed contains no accounts, materials, community content, reports, or quiz attempts.

## Profile and catalog states

- `profiles.role`: `student` or `admin`
- `profiles.status`: `active` or `restricted`
- catalog `status`: `active` or `inactive`
- material `status`: `uploading`, `approved`, or `removed`
- content `status`: `active` or `removed`
- attachment `status`: `uploading`, `ready`, or `removed`
- report `status`: `pending`, `dismissed`, `content_removed`, or `account_restricted`

Public Auth signup accepts only `@limu.edu.ly`, normalizes the identity, and creates an active Student profile. Role and account state are controlled on the server.

## Main tables

```text
profiles
schools
academic_areas
departments
subjects
communities
subject_materials
community_posts
community_comments
community_attachments
quizzes
quiz_attempts
reports
admin_audit_log
```

Every client-facing table has Row Level Security. Students see active catalog data, approved materials, active community content, their own attempts, and their own reports. Admins receive the management access required by their use cases. The private quiz answer key is not directly readable by a Student.

## Stable database functions

Student operations:

```text
update_my_full_name(p_full_name)
create_community_post(p_subject_id, p_body, p_idempotency_key)
update_community_post(p_post_id, p_expected_version, p_body)
delete_community_post(p_post_id, p_expected_version, p_reason)
create_community_comment(p_subject_id, p_post_id, p_body, p_idempotency_key)
update_community_comment(p_comment_id, p_expected_version, p_body)
delete_community_comment(p_comment_id, p_expected_version, p_reason)
reserve_community_attachment(p_subject_id, p_target_type, p_target_id,
                             p_file_name, p_mime_type, p_size_bytes,
                             p_idempotency_key)
remove_community_attachment(p_attachment_id, p_reason)
create_content_report(p_subject_id, p_target_type, p_target_id,
                      p_parent_id, p_reason, p_details)
```

Admin operations:

```text
admin_resolve_report(p_report_id, p_action, p_resolution_note)
admin_set_user_status(p_profile_id, p_status, p_reason)
admin_create_subject_with_community(
  p_department_id, p_name, p_code, p_description,
  p_study_level, p_semester, p_display_order, p_status)
```

Report action is `dismiss`, `remove`, or `restrict`. Account status is `active` or `restricted`. Subject creation and Community creation occur in one transaction.

`complete_community_attachment` is intentionally absent from the Student API.
Only the service-role Edge verifier receives permission to call it after real
byte validation.

## Material contract

PDF bytes live in the private `subject-materials` bucket. A material is limited to 26,214,400 bytes, records its SHA-256 checksum, and becomes Student-readable only after approval. Replacement advances its version. Removal first closes database access and then attempts to remove the private object, so a Storage failure cannot leave an approved row accessible.

## Community attachment contract

Community bytes live in the separate private `community-attachments` bucket.
One post or comment can have up to three files of at most 10 MiB each. Accepted
types are JPG/JPEG, PNG, WebP, PDF, and valid UTF-8 plain text.
Each Student is limited to ten new reservations per minute and 100 MiB of
ready/in-progress/not-yet-cleaned bytes. Before a normal upload, the app asks
protected cleanup to sweep that Student's removed and expired reservations so
interrupted attempts do not permanently consume the quota.

The phone reserves an opaque owner-bound path and uploads without upsert.
`finalize-community-attachment` authenticates the active Student, rechecks target
ownership and the active Subject hierarchy, downloads the real object, compares
its stored MIME and exact size, validates format bytes, computes SHA-256, and
only then makes the row readable. A missing object remains retryable; invalid
bytes are hidden and deleted. `cleanup-community-attachments` deletes only
uploading/removed objects after owner or Admin authorization. Signed download
URLs last 60 seconds and object cache lifetime is disabled.

## Quiz API

`generate-quiz` accepts:

```json
{
  "subject_id": "UUID",
  "material_id": "UUID",
  "idempotency_key": "UUID"
}
```

It authenticates one active Student, verifies the active catalog path and approved PDF, validates its bytes and checksum, calls the configured AI provider, and stores exactly ten questions. The phone receives prompts, four options per question, and source pages without the correct option indexes.

`submit-quiz` accepts:

```json
{
  "quiz_id": "UUID",
  "answers": [0, 1, 2, 3, 0, 1, 2, 3, 0, 1],
  "idempotency_key": "UUID"
}
```

It scores exactly ten answers, saves one idempotent attempt, and then returns the score and corrections.

## AI server configuration

The protected function requires:

```text
AI_API_KEY=YOUR_REAL_PROVIDER_KEY
AI_MODEL=gemini-3.5-flash-lite
AI_FALLBACK_MODELS=gemini-3.1-flash-lite,gemini-3.5-flash
AI_TIMEOUT_MS=80000
AI_ATTEMPT_TIMEOUT_MS=32000
```

The default endpoint shape is Gemini-compatible. `AI_FALLBACK_MODELS` is a comma-separated failover chain; the singular fallback name remains supported for older deployments. `AI_API_BASE_URL`, `AI_TIMEOUT_MS`, `AI_ATTEMPT_TIMEOUT_MS`, `QUIZ_GENERATION_PER_MINUTE`, and `ALLOWED_ORIGIN` are optional operator settings. Each provider attempt has its own timeout inside the overall deadline so one stalled model cannot prevent failover.

Keep values in an ignored environment file and upload them through the CLI:

```powershell
npx.cmd --yes supabase@2.116.0 secrets set `
  --env-file supabase/functions/.env `
  --project-ref xihsvhhkbaaypmjjtzxa
```

Never put these values in Flutter, an APK, command output, or Git.

## Hosted deployment commands

```powershell
npx.cmd --yes supabase@2.116.0 login
npx.cmd --yes supabase@2.116.0 link --project-ref xihsvhhkbaaypmjjtzxa
npx.cmd --yes supabase@2.116.0 db push --linked --include-seed --dry-run
npx.cmd --yes supabase@2.116.0 db push --linked --include-seed
npx.cmd --yes supabase@2.116.0 functions deploy generate-quiz submit-quiz finalize-community-attachment cleanup-community-attachments `
  --project-ref xihsvhhkbaaypmjjtzxa `
  --use-api
```

Confirm the project reference and review the dry run before the write. JWT verification is required; do not disable it.

## Requested test Admin

The trusted operator script can bootstrap the requested account without saving the service-role key in this repository. Supply its required values from a protected operator environment, run it once, then verify the profile is active with role `admin`.

The Flutter login accepts the requested alias while Supabase keeps an email identity:

```text
Login name: admin
Underlying Auth email: admin@limu.edu.ly
Password: 123456
```

This published six-character password is only for the requested supervised phone test. Change it and remove the credential from documentation before a real deployment.

## Required verification

After deployment, verify permitted and denied paths. A fresh Student must complete the main catalog, PDF, quiz, Community text/attachment, and reporting flow. The Admin must complete catalog, material, attachment inspection, report, and account-state actions. Also verify that non-LIMU signup, unauthenticated protected reads, unapproved material access, direct answer-key reads, cross-user edits, direct attachment finalization, unsafe attachment bytes, and repeated quiz submission are denied.

Record results in [repository audit](repository-audit.md); the presence of these files is not hosted-deployment evidence.
