# PeerStudy project brief

## Purpose

PeerStudy gives LIMU Students one subject-based place to read approved course materials, test their understanding, and discuss the Subject with classmates. It gives Admins a controlled way to maintain that environment.

## Actors

### Student

A Student can:

- register with a full `@limu.edu.ly` email and password;
- sign in, recover a password, update a display name, and sign out;
- browse School, Academic Area, Department, and Subject;
- view approved PDFs inside the app;
- select one approved PDF and explicitly start a ten-question quiz;
- save answers during the attempt, confirm before leaving, submit once, and review score and corrections;
- create, edit, and remove their own posts and comments, with up to three
  private validated attachments on each;
- privately report exactly one post or comment; and
- use app settings stored only on the device.

### Admin

An Admin can:

- sign in with a pre-created active account;
- select the fixed Engineering or IT Academic Area and manage its Departments and Subjects;
- create a Subject and its Community in one operation;
- upload, replace, approve, edit, and remove Subject PDFs;
- review pending and resolved reports, including ready target attachments;
- dismiss a report, remove reported content, or restrict the responsible Student; and
- activate or restrict Student access with an audit record.

## Functional rules

1. Public signup always creates an active Student, never an Admin.
2. Only complete LIMU email addresses are accepted.
3. A restricted profile cannot use protected data.
4. Each Subject has one Community.
5. Students see only active catalog paths and approved materials.
6. Each generated quiz comes from one selected approved material.
7. Each quiz has exactly ten questions and four options per question.
8. Scoring happens on the server; the phone does not receive the answer key before submission.
9. Community counts and timestamps come from the database.
10. Reports remain private to the reporting Student and Admins.
11. Community attachment bytes stay private, have short-lived access, and
    become readable only after server-side type, size, and checksum validation.

## Reference academic content

The initial hierarchy is:

- School of Technology and Engineering
  - Information Technology
    - Software Engineering
    - Network
    - Telecommunications
    - Health Informatics
    - Artificial Intelligence (AI)
  - Engineering
    - Architectural and Structural Engineering
    - Mechatronics
    - Interior Design

The reference Subject is **Software Engineering Fundamentals** under Software Engineering. More reviewed Subjects are Admin-managed data, not hard-coded screens.

## Quality goals

- Beginner-readable Flutter source with plain names and explanatory comments.
- Fail-closed access when configuration or profile data is invalid.
- Short, helpful errors without leaking sensitive information.
- Idempotent writes for unstable phone networks.
- Transactional Admin actions for related records.
- Responsive phone screens and bounded database queries.
- A repeatable APK build and a recorded end-to-end phone test.

## Out of scope

- Public Admin registration.
- A third application role.
- Student-uploaded official learning materials; Community attachments remain
  peer content and are never presented as Admin-approved course material.
- A permanent PDF library on the phone.
- Client-side quiz scoring.
- Placeholder questions when the external AI service is not configured.

## Completion definition

The project is ready for a supervised production-like test only when all of the following have evidence:

- migrations and seed applied to the intended Supabase project;
- all quiz and attachment Edge Functions deployed with JWT verification;
- fresh Student registration and sign-in;
- pre-created Admin sign-in and role routing;
- material upload, view, quiz generation, submission, and corrections;
- post/comment attachment upload, retry, open, removal, private report, and
  each Admin report action;
- account restriction immediately denying protected access;
- `flutter analyze` and the full test suite passing; and
- a successfully installed APK tested on a physical phone.

The Supabase backend and APK are deployed/built and have recorded automated
evidence, including one real Gemini-generated ten-question quiz and trusted
server submission. Final supervised acceptance still includes the physical-phone
walk-through and university password-recovery e-mail delivery.
