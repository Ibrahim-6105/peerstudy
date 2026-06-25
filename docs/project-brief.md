# PeerStudy Project Brief

Last reviewed: 2026-06-25

Source document: `C:\Users\betoe\Downloads\PeerStudy_Project_Document.pdf`

## Executive Summary

PeerStudy is planned as a mobile learning platform for LIMU students. It is meant
to combine structured access to study material with peer-to-peer academic
interaction so students can ask questions, answer each other, share explanations,
and study inside subject-focused spaces.

The project brief positions PeerStudy as a supplement to official university
systems. It is not intended to replace registrar systems, formal grading, or
official university announcements.

## Problem Statement

Existing university learning systems focus heavily on content delivery and
automated assessment. Students still need explanation, discussion, and peer
feedback, especially when they study outside classroom hours. Informal messaging
groups provide interaction, but they are usually disorganized, difficult to
moderate, and weak at preserving academic structure.

PeerStudy addresses this gap by organizing collaboration around academic context:
major, department or year, subject, concept, learning resources, quizzes, and peer
discussion.

## Target Users

- Students: undergraduate LIMU students who consume learning material, ask
  questions, answer peers, comment, and upload explanations.
- Academic moderators: trusted users who manage official lecture material and
  guide academic discussion.
- Admins: system-level users who review reports, remove violating content, and
  block users when necessary.

## Core User Journey

1. A student registers or logs in with a university email address.
2. The student selects their academic major.
3. The system routes technical majors through departments and medical or similar
   majors through academic years.
4. The student selects a subject, then a concept.
5. The concept view exposes lecture material, AI quiz practice, and peer
   community tools.
6. Students can ask questions, answer peers, comment on posts, and upload short
   educational explanations.
7. Admins and moderators maintain safety, academic relevance, and content quality.

## Functional Requirements

### Authentication

- Register students with full name, university email, and password.
- Validate `@limu.edu.ly` email addresses.
- Log in students, admins, and moderators.
- Restrict student registration to verified university identities.
- Support email password reset for students.
- Block disabled accounts from accessing the app.
- Allow secure sign out.

### Academic Navigation

- Display LIMU majors.
- Route IT and Engineering majors through departments.
- Route Medicine, Law, Pharmacy, and Dentistry through academic years.
- Display only subjects relevant to the selected path.
- Break each subject into focused concepts.

### Lecture Materials

- Display official lecture notes, PDFs, and reference material.
- Cache selected files when appropriate.
- Show clear errors for missing or broken files.
- Allow readable page navigation, scrolling, and zooming in PDF content.

### AI Quizzes

- Generate 10-question quizzes for a selected concept.
- Limit AI context to official study material for the selected concept.
- Provide immediate score and correction feedback.
- Handle AI timeout or generation failure gracefully.
- Record quiz results when required by the product design.

### Peer Community

- Provide a concept-specific discussion area.
- Store chat messages chronologically.
- Allow students to upload posts and peer explanations.
- Allow comments on peer posts.
- Validate empty comments and failed uploads.
- Keep history available for later review.

### Moderation and Administration

- Let students report inappropriate, misleading, or violating content.
- Let admins review reports and report details.
- Allow admins to remove content, dismiss reports, and update report status.
- Allow admins to review chat history where required for safety.
- Allow admins to block users who violate the code of conduct.
- Let moderators upload and maintain official lecture materials.

## Non-Functional Requirements

- Scalability: support at least 1,000 concurrent students.
- Responsiveness: deliver chat messages within approximately 1 second.
- Media performance: start video playback within approximately 2 seconds on
  standard mobile networks.
- Availability: target high availability through Firebase-managed services.
- Security: use HTTPS, role-based access, and database rules that protect user
  data and ownership.
- Reliability: avoid saving corrupted or partial media uploads.
- Maintainability: separate user interface, business logic, data access, and
  service integrations.

## Constraints and Limitations

- Initial usage is scoped to LIMU University.
- Stable internet connectivity is required for real-time features.
- Full offline access is outside the first release scope.
- Gamification is deferred to a future version.
- Content accuracy depends on moderation and verified official material.
- The source document mentions both local SQLite caching and MySQL. This should
  be clarified before backend implementation.

## Recommended Initial MVP

1. Student authentication with university email validation.
2. Academic navigation from major to concept.
3. Static lecture PDF listing and viewer.
4. Concept-level discussion posts and comments.
5. Basic report workflow for admin review.
6. AI quiz prototype constrained to uploaded concept material.

The current repository has not implemented these features yet.
