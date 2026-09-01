# Hosted Supabase acceptance evidence

Run date: 2026-08-30  
Project reference: `xihsvhhkbaaypmjjtzxa`  
Runner: `supabase/scripts/hosted-smoke.ts`

## Result

- 21 checks passed.
- 0 checks failed.
- 0 checks are blocked.

## Verified against the hosted project

- `admin@limu.edu.ly` / `123456` authenticated and mapped to one active Admin profile.
- Public Auth rejected a non-`@limu.edu.ly` signup.
- Real LIMU Student signup returned an immediate session and active Student profile.
- Student RLS exposed a usable School, Academic Area, Department, and Subject hierarchy while preserving owner-added catalog entries.
- The seeded Subject owned exactly one Community whose id matched the Subject id.
- Student Post and Comment create, versioned edit, and author deletion RPCs worked.
- A real Post PDF and Comment TXT attachment completed the private reservation,
  upload, server byte/MIME/size/SHA-256 validation, eligible Student download,
  metadata removal, and physical cleanup flow.
- A Student could not reserve, remove, or clean another Student's attachment,
  and could not invoke the service-role-only completion function directly.
- A forged PNG MIME/extension with text bytes was rejected, terminally hidden,
  and physically deleted instead of becoming readable.
- Removing a parent Comment immediately hid its attachment and protected target
  cleanup removed the private object.
- A second Student created a private report; it was hidden from the content author and visible to the reporter and Admin.
- Admin read and atomically dismissed the pending report.
- Admin restriction immediately removed protected catalog access from an already-issued Student token.
- Admin reactivation restored access to that same session.
- Anonymous access to protected catalog and quiz data was denied.
- A Student could neither directly read nor directly insert private answer-key rows.
- A real temporary PDF exercised private Storage and Material metadata states: unapproved denied, approved downloadable with matching SHA-256, removed denied, then object deleted.
- The protected Edge Function sent a temporary approved PDF to the real Gemini provider and returned exactly ten questions without exposing answers.
- The protected submission function scored ten answers on the server and returned ten corrections.
- The primary model is `gemini-3.5-flash`; `gemini-3.1-flash-lite` is the configured fallback for transient demand or model availability failures.

## Cleanup evidence

The runner's `finally` block removed every temporary Auth identity, Profile,
Post, Comment, Community Attachment, Report, Material row, Storage object,
Quiz/Attempt, and related temporary audit row. It then verified:

- all attempted temporary Auth identities and Profiles were absent;
- every temporary Material, Community Attachment, Storage object, Post,
  Comment, Report, Quiz, Attempt, and related audit row was absent;
- existing owner accounts, catalog entries, and application data were preserved.

No API key, access token, password payload, or temporary identity was printed by the runner.
