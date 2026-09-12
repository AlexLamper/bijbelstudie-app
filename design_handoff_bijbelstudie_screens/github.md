repo: AlexLamper/bijbelstudie-app
branch: main
path: bijbelstudie_mobile/lib

## Last sync
date: 2026-09-11T17:58:41Z

### Updated in this project
- Read `features/profile/present/` (profile_screen.dart, profile_menu_sheet.dart); the 1:1 recreations of Profiel, Instellingen and het profielmenu use the real `Icons.*` set (settings_outlined, local_fire_department_outlined, edit_note_outlined, local_library_outlined, auto_stories_outlined).
- Read design tokens from `core/theme/app_theme.dart` (teal #0D9488, paper #F3F4F6, Inter/Lora, r16 cards) and applied them 1:1.
- Read `features/studies/present/studies_screen.dart` to ground the Studies redesign in the real section order.
- Read `core/ui/app_widgets.dart`, `studies/present/study_banner.dart` and `levensboom/present/mini_tree.dart`; study art now uses the real StudyBanner fallback (teal → #0F172A) and the Levensboom/verse scenes are honest TreeView placeholders.
- Read `features/bible/present/read_screen.dart` and `features/commentary/present/commentary_pane.dart`; the reader toolbar in the final screens now matches the app’s real control set and order.
- Read `core/data/bible_books.dart`; the “Boekenrek” option now uses the app’s real canonical Dutch book names and order.
- `BijbelStudie Screens.dc.html` now holds three rounds: two full directions across six screens, plus six extra Studies · Ontdek concepts.

## Screen map
| Project screen | Repo files |
| --- | --- |
| Studies (Ontdek) — A1 / B1 | features/studies/present/studies_screen.dart, features/studies/present/study_banner.dart |
| Studie-detail — A2 / B2 | features/studies/present/study_detail_screen.dart |
| Les afgerond — A3 / B3 | features/levensboom/present/, features/study/present/ |
| Start — A4 / B4 | features/dashboard/present/ |
| Bijbel + Studie — A5 / B5 / 4e / 4f | features/bible/present/read_screen.dart (tool order: zoeken, weergave, vertaling, offline), features/bible/present/reader_settings_sheet.dart, source_picker_sheet.dart, features/commentary/present/commentary_pane.dart (bronregel met “Wissel”) |
| Notities — A6 / B6 | features/notes/present/ |
| Bestaand — 7a/7b/7c/7d/7e (1:1) | features/profile/present/profile_screen.dart, profile_menu_sheet.dart, features/dashboard/present/, features/levensboom/present/ |
| All screens (tokens) | core/theme/app_theme.dart, core/ui/app_widgets.dart |
