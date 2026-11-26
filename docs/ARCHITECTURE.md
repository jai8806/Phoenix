# Architecture

```
Flutter app (Android · iOS · web)
  ├─ Cadet app          bottom-tab shell
  ├─ Command Center     side rail (wide) / drawer (phone)
  └─ Riverpod state ──► repositories ──► Supabase (Postgres + Auth + Storage, India region)
                                          ├─ row-level security per unit
                                          ├─ pgvector + full-text for Ustaad
                                          └─ Edge Functions: RAG answers, ingestion, AI briefs (Phase 1–2)
```

## App (`app/`)

| Path | What lives there |
| --- | --- |
| `lib/main.dart` | Boot: loads preferences, picks demo or Supabase auth, restores the session |
| `lib/app.dart` | `MaterialApp.router` with light/dark themes |
| `lib/core/theme/` | Design tokens and `ThemeData` (NCC palette, Barlow Condensed headings, Inter body) |
| `lib/core/router/` | go_router routes, role-based redirects |
| `lib/core/config/env.dart` | `--dart-define` settings; demo mode when no backend is configured |
| `lib/data/models/` | Plain Dart models: users, comms, tests, diary, roster |
| `lib/data/providers.dart` | Riverpod providers and controllers (state lives here) |
| `lib/data/auth_repository.dart` | Demo and Supabase sign-in behind one interface |
| `lib/data/demo/` | Sample data and a provisional syllabus list |
| `lib/domain/` | Pure logic with unit tests: eligibility, diary stats (test marking lives in `models/test.dart`) |
| `lib/features/` | Screens: `auth`, `cadet`, `command`, `shared` |

Notes:

- **Material import.** In Flutter 3.50 Material moved out of the framework into
  the `material_ui` package, so screens import `package:material_ui/material_ui.dart`.
- **Demo mode.** Without `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`, sign-in
  offers a role picker and every controller seeds from `lib/data/demo/`. In
  Phase 1 the controllers switch to Supabase repositories with a local Drift
  cache for offline use.
- **Time.** `clockProvider` is injectable so tests run against a fixed date.
- **Fonts** are bundled (OFL licences in `app/assets/fonts/`), so the app looks
  right offline.

## Database (`supabase/`)

Multi-tenant: `institutions → units → profiles`. Every unit-scoped table is
guarded by RLS using three helpers: `my_unit_id()`, `my_role()`,
`is_unit_admin()`.

- Cadets read their unit's announcements, calendar, tests and approved questions.
- Senior cadets and the ANO write unit content.
- Only the ANO changes roles, ranks or unit membership.
- New sign-ups get a cadet profile automatically and join a unit with the
  unit's `join_code` through `join_unit()`.
- Diary entries are private; the ANO reads only entries marked `shared_with_unit`.
- `document_chunks` holds passages with a 1024-dim embedding and a full-text
  index for hybrid retrieval.

`supabase/tests/rls_check.sql` exercises these rules (see `supabase/README.md`).
