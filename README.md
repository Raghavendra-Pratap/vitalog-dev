# Vitalog

Local-first family lab tracker. The desktop and phone apps keep the health record on the device.

Documentation: [docs/README.md](docs/README.md)

| Path | Role |
|------|------|
| `app/` | Flutter application. Display name Vitalog |
| `core/` | Pure Dart domain (flags, units, parsing) |
| `catalog/` | Seed script. The shipped catalogue is `app/assets/catalog/catalog.db` |
| `docs/` | Current product, privacy, desktop delivery, and development |
| `bodyline-handoff/` | Design tokens, logos, original schema |

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

- The health record stays on the device.
- Track, don’t diagnose.
- The lab’s printed range wins.
- A photo or PDF is read on the device, and nothing is saved until the person confirms it.

## Dev remote

`origin` → `git@github.com:Raghavendra-Pratap/vitalog-dev.git`
