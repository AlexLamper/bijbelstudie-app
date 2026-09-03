# BijbelStudie — Flutter iOS/Android app

Flutter client for www.bijbelstudie.io. The Flutter project is
`bijbelstudie_mobile/`; the repo root only holds docs, screenshots and CI.
The Next.js backend it talks to is a **separate repo** at `C:\Projects\bijbelstudie`
— it is not here, so don't go looking for `/api/v1` handlers in this tree.

## Layout

Feature-first clean architecture under `bijbelstudie_mobile/lib/`:

- `core/` — `api/api_client.dart` (Dio + bearer refresh), `config/app_config.dart`
  (base URLs, dart-defines), `router/app_router.dart` (go_router, all routes),
  `theme/app_theme.dart`, `ui/` (shared widgets), `db/content_cache.dart` (sqflite
  chapter cache), `data/bible_books.dart`, `notifications/`, `preview/`.
- `features/<name>/` — each with `data/` (repositories, models, local storage),
  `domain/` (entities), `present/` (screens + Riverpod providers).
  Features: `ai auth bible commentary dashboard feedback groups notes onboarding
  premium profile resources search settings studies study`.
- `test/` — 16 test files plus `screenshot_fixtures.dart`.

Screen ↔ file mapping is 1:1 by feature name: the Start tab is
`features/dashboard/present/dashboard_screen.dart`, the split reader is
`features/study/present/study_screen.dart`, the reader is
`features/bible/present/read_screen.dart`.

## Stack

Riverpod 3 (state) · go_router 17 (routing) · Dio + http (network) ·
sqflite + shared_preferences + flutter_secure_storage (persistence) ·
purchases_flutter / RevenueCat (subscriptions) · google_sign_in +
sign_in_with_apple (auth).

## Conventions

- UI strings are **Dutch**. Code, comments and identifiers are English.
- Providers live beside their screens in `present/`, named `<thing>Provider`.
- Repositories take the `ApiClient`; screens never call Dio directly.
- Auth is `Authorization: Bearer <jwt>` against `/api/v1/*`; the website's
  cookie auth is a different client and irrelevant here.
- Release/signing work is documented in `docs/ios-release-setup.md` and
  `docs/handoff-manual-steps.md` — read those before touching iOS signing,
  and don't re-derive it from the Xcode project.

## Commands

Run from `bijbelstudie_mobile/`, through the **Bash tool** (a PreToolUse hook
trims Flutter output there; the PowerShell tool gets the untrimmed version):

```bash
flutter test                 # full suite
flutter test test/x_test.dart   # one file — prefer this
flutter analyze
flutter pub get
```

## Keep context small

This repo has cheap ways to waste a lot of tokens. Avoid them:

- **Never read whole large files.** `test/screenshot_fixtures.dart` (66 KB),
  `dashboard_screen.dart`, `app_theme.dart` and `app_widgets.dart` are 20–30 KB
  each. Grep for the symbol, then read the surrounding lines with an offset.
- **Never read `screenshots/`.** Those are 0.5–1.2 MB PNG/JPGs; each one costs
  more than a whole source file. Denied in `.claude/settings.json`.
- **Never traverse `build/` (2.8 GB) or `.dart_tool/` (113 MB)** with `find`,
  `ls -R` or `du`. Scope every search to `lib/` or `test/`.
- **Run one test file, not the suite,** while iterating. The suite includes
  widget-render and screenshot tests.
- `bijbelstudie-ios-build-prompt.md` (26 KB) is a historical one-shot prompt.
  It is not current documentation — don't read it unless asked.
- Prefer `gh` over fetching GitHub pages, and `git log -n 5 --oneline` over
  unbounded log output.

# Compact instructions

When compacting, keep: the current file paths and symbols under edit, test
failures verbatim, and any App Store / signing constraint already established.
Drop: file listings, passing test output, and superseded approaches.
