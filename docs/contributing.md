# Contributing Guide

Last updated: 2026-06-25

## Development Setup

Install Flutter, then prepare the project:

```powershell
flutter pub get
```

Run the app:

```powershell
flutter run
```

## Quality Gate

Run these before committing:

```powershell
dart format --set-exit-if-changed .
flutter analyze
flutter test
```

## Branching

Use short, task-focused branches:

```text
feature/auth-shell
feature/academic-navigation
fix/email-validation
docs/project-brief
```

## Commit Style

Use concise Conventional Commit messages:

```text
chore: initialize Flutter project
docs: document project scope
ci: add Flutter quality workflow
feat: add student login form
fix: validate LIMU email domain
test: cover academic path routing
```

Keep each commit focused on one task. Avoid mixing feature work, formatting,
documentation, and dependency changes in the same commit unless they are directly
related.

## Code Standards

- Prefer small feature folders with clear ownership.
- Keep widgets focused and reusable.
- Keep Firebase and AI code behind repository or service interfaces.
- Put validation rules in `utils/` when they are small and shared.
- Handle loading, empty, error, and success states explicitly.
- Add tests with every feature that changes user-visible behavior.

## Pull Request Checklist

- The change has a clear purpose.
- The implementation matches the project brief or an approved update.
- Formatting, analysis, and tests pass.
- New behavior has tests.
- Security-sensitive behavior has been reviewed.
- Documentation is updated when product behavior or setup changes.

## Documentation Standards

Update docs whenever a feature changes:

- Product scope or requirements: `docs/project-brief.md`
- Technical structure or integrations: `docs/architecture.md`
- Planned work and status: `docs/roadmap.md`
- Repository setup or workflow: `docs/contributing.md`
- Current repo state and risks: `docs/repository-audit.md`
