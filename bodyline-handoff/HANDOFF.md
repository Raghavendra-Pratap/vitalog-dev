# bodyline — design handoff

*Your body, over time.* A local-first health tracker for individuals and families: lab results with trends, a complete medical profile, reminders, and a body map that shows what has been tested and what needs attention.

**Interactive prototype (mobile + desktop):** https://claude.ai/artifact/Y32nv6GJCiyTUi9Tk5LepQ
Press Play on any screen to click through. The "Explorations" row at the bottom is archive only and not part of the build.

## What's in this package

| Path | What it is |
|---|---|
| `HANDOFF.md` | This file |
| `design-tokens.json` | Colours, type, radii, spacing, layout sizes, chart rules |
| `logo/` | Mark, lockups (light/dark) and app icons as SVG |
| `data/schema.sql` | SQLite data model v0.2 (catalog.db + encrypted user.db) |
| `screens/` | Exported PNG/PDF of every screen (add after exporting from the canvas) |

The lockup SVGs use live text in Fraunces. Convert the text to outlines before using them outside the app, or ship the font.

## Product principles (non-negotiable)

1. **Nothing on our servers.** All data lives on the device (SQLCipher). Optional sync goes to the user's own cloud, encrypted on device before upload. No analytics or crash reporting that can capture health values.
2. **Track, don't diagnose.** Copy says "above the lab's range", never "you may have X".
3. **The lab's printed range wins.** Catalogue defaults are only a fallback. Store tiered bands exactly as printed.
4. **Never red/green.** High = orange, low = blue, in range = teal, always with a text label.
5. **44 px minimum touch targets.**

## Stack and architecture

- **Flutter**, Android first, then iOS, desktop (Windows/macOS/Linux) and web from the same codebase.
- The core (catalogue matching, unit conversion, flagging, sync merge) is pure Dart with no platform code.
- Platform adapters behind interfaces:

| Adapter | Android / iOS | Desktop | Web |
|---|---|---|---|
| Storage | SQLCipher | SQLCipher | encrypted IndexedDB (TBD) |
| OCR | ML Kit / Vision | OS OCR, Tesseract fallback | — |
| Sync | Google Drive appData / iCloud | Google Drive | Google Drive |
| Health data | Health Connect / HealthKit | — | — |

- **Sync:** each device writes its own append-only encrypted change log to the user's cloud folder. Conflicts resolve last-writer-wins per row by hybrid logical clock. Attachments are content-addressed (sha256), so they are immutable and dedupe themselves.
- **Recovery key** is shown and printable at setup. A lost passphrase means lost backup; say so plainly in the UI.
- **Disable Android auto-backup** (`allowBackup=false` plus data-extraction rules). Otherwise the database leaks to Google backup outside our encryption.
- **Privacy screen** is a user toggle, off by default: FLAG_SECURE on Android, app-switcher blur on iOS.

## Screens

### Mobile (390 × 844 reference)

| Screen | Purpose | Key interactions |
|---|---|---|
| Home | Body map + what needs attention | Tap name → Family; tap organ row → Organ detail; reminder strip; "+" → add report |
| Tests | Every parameter, grouped by body system | Search, filters (All / Flagged / Due), sparkline per row → Trend |
| Trend | One parameter over time | Lab-tiered bands shaded, medication markers, 1Y/3Y/All, history rows → report |
| Organ detail | Everything linked to one organ | Linked tests, related meds/doctors/family history, suggested next test |
| Records | Timeline of reports and visits | Filter chips, "Add report" |
| Review | Confirm values after OCR | Ambiguous match (choice chips), suspicious value (editable), unrecognised (Match) |
| Health profile | The complete profile | Sections: conditions, meds, allergies, vaccinations, surgeries, family history, emergency contact; gear → Settings |
| Family | Switch between profiles | Cards with flags and next reminder, add member |
| Settings | Sync, security, data | Toggles: app lock, privacy screen, notifications |

Bottom nav: **Home · Tests · Records · Profile**. The profile switcher lives in the Home header.

### Desktop (1440 × 900 reference, 248 px sidebar)

| Screen | Purpose |
|---|---|
| Overview | Body map, trend of flagged values (tabbed), family-wide reminders, recent records |
| Tests | Master–detail: parameter list left, full trend + history right |
| Records | Timeline left, selected report with every value vs lab range right |
| Report review | Report page and extracted values side by side, row selection linked both ways |
| Health profile | Summary header + section grid, emergency card, doctor summary PDF |
| Family | Profile cards, click to switch |
| Settings | Sync & backup, security, catalogue, danger zone |

Desktop is expected to be where bulk entry of old reports happens. Treat the review screen as a priority.

## Body map

Chosen style: **B, soft silhouette**. Natural proportions, warm fill `#EDE3D8`, no face. Organs are smooth shapes coloured by status, with a soft halo when flagged. Untested organs are shown dashed or faint.

The prototype drawing is a placeholder. The production illustration needs:

- each organ on its own named layer whose id matches the catalogue `body_system.code` (`thyroid`, `heart`, `liver`, `kidney`, …);
- male, female and child variants, chosen from the profile's sex and age;
- front and back views (kidneys, spine);
- a neutral expression that never changes with results.

## Data model notes (v0.2)

- Two databases. `catalog.db` is shipped, read-only and replaceable. `user.db` is encrypted and synced. User rows reference the catalogue by stable text codes, not foreign keys.
- Lab values and vitals share the `observation` table. A vital is an observation with `report_id = NULL`.
- Every value is stored exactly as printed (`value_reported`, `unit_reported`, lab range, `comparator` for values like "<0.01") plus a derived canonical value.
- **New in v0.2:** `observation.ref_bands_json` and a `default_ref_band` table for tiered ranges (Vitamin D, LDL, HbA1c…). Trend charts shade every tier.

## Milestones

| | Scope | Exit test |
|---|---|---|
| M0 | Stack set up, catalogue v1 (~150 params with Indian-lab aliases), report corpus | Catalogue reviewed against 15–20 real reports |
| M1 | Profiles, manual entry by panel, trends, report vault | All past reports entered and charted |
| M2 | On-device OCR + review screen | ≥80% of values correct without edits on the corpus |
| M3 | Health profile, visits, reminders, body map | — |
| M4 | Encrypted sync, recovery key, new-device restore | Restore on a fresh device |
| M5 | Medications, Health Connect vitals, doctor PDF | — |

## Open items

- Production body-map illustration (brief above).
- Trademark, domain and store-name checks for "bodyline".
- Web storage approach.
- Desktop screens use sample data; values, labs and people in `[brackets]` are placeholders.
