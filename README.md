# bodyline

Local-first family lab tracker. Spec + app live here.

| Path | Role |
|------|------|
| `app/` | Flutter application (Android first) |
| `core/` | Pure Dart domain (flags, units, parsing) |
| `catalog/` | CSV seeds + `build_catalog.py` → `catalog.db` |
| `bodyline-handoff/` | Design tokens, logos, original schema |
| `docs/` | Copied schema + tokens for the monorepo |

**Product packet:** `/Users/raghavendra_pratap/Developer/product-dev/projects/bodyline/`

## Quick start

```bash
# Catalogue
python3 catalog/build_catalog.py

# Core tests (needs Dart SDK)
cd core && dart pub get && dart test

# App (needs Flutter)
cd app && flutter pub get && flutter run
```

## Principles

- Nothing on our servers (user data on device).
- Track, don’t diagnose.
- Lab printed range wins.
- Manual panel entry first; OCR later.

## Dev remote

`origin` → `git@github.com:Raghavendra-Pratap/vitalog-dev.git`
