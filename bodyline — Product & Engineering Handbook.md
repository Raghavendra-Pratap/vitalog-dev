# bodyline — Product & Engineering Handbook

Sep 26, 2026 · @Raghav

## 1. Overview

bodyline is a local-first app that turns a family's scattered lab reports into one living health profile: every result trended over time, the full medical history in one place, and reminders for what's due. All data stays on the user's devices and their own cloud; nothing is stored on our servers.

Prototype (mobile + desktop): [bodyline – App Design](https://claude.ai/artifact/Y32nv6GJCiyTUi9Tk5LepQ)

### The problem

- Lab reports live as PDFs in WhatsApp, email and paper folders. Nobody can answer "how has my father's HbA1c moved over three years?" without digging.
- Each lab prints different names, units and ranges for the same test, so reports are hard to compare.
- Existing apps are either lab-owned (only their own reports), or cloud platforms whose business is selling tests, consultations or subscriptions.
- Families managing a parent's chronic condition carry the burden on paper, and doctors see only the latest report.

### Who it's for

| User | Need | What bodyline gives them |
| --- | --- | --- |
| The family health manager (primary) | Tracks parents', partner's and children's health | Family profiles, reminders across everyone, doctor-ready summaries |
| The self-tracker | Regular tests, wants to see improvement or drift | Trends with lab bands, flags, medication markers |
| The chronic-condition patient | Quarterly tests, several medications | Condition-linked meds and trends, recurring test reminders |
| The privacy-conscious user | Won't hand medical data to a company | No account, no server, encrypted sync to their own cloud |

### Vision

The single place a family's health history lives, owned entirely by the family, readable at a glance, and useful to any doctor in two minutes.

### Product principles

1. **Nothing on our servers.** Data lives on device; sync goes only to the user's own cloud, encrypted before upload.
2. **Track, don't diagnose.** We show values against the lab's range. We never say what a result means medically.
3. **The lab's printed range wins.** Our catalogue defaults are only a fallback.
4. **Entry must be near-effortless.** Upload a report, confirm, done. Manual entry is the fallback.
5. **Calm, not alarming.** Orange and blue, never red and green; plain words; no scores or health grades.

### Positioning

| Competitor | Model | Where bodyline differs |
| --- | --- | --- |
| Eka Care | Cloud PHR, ABHA-linked, subscription | No account or server; deeper catalogue; body map |
| Lab apps (Redcliffe, Thyrocare, Max Lab) | Own-lab reports, sells tests | Any lab, no upsell |
| Medicyn | On-device vault, iOS, one-time price | Trends with lab bands, body map, Android + desktop |
| Lab Tracker, Laboratory Test Tracker, Labsi | iOS lab-number trackers | Complete medical profile, family reminders, cross-platform |
| BloodTrends | On-device, \~50 biomarkers | 150+ parameters with Indian-lab aliases |

### Success metrics (first 6 months after public launch)

| Metric | Target |
| --- | --- |
| Reports added per active user | 5+ in the first month |
| OCR values accepted without edits | 80%+ |
| Users with 2+ family profiles | 40%+ |
| 90-day retention | 35%+ |
| Crash-free sessions | 99.5%+ |

As a local-first app we have no server analytics. These are measured through opt-in, anonymous, aggregate counters only (see section 6).

### Non-goals

- Diagnosis, symptom checkers, risk scores or AI medical advice.
- Booking lab tests, teleconsultation or pharmacy ordering.
- Social features or community.
- ABDM/ABHA integration (needs a server-side PHR registration, which contradicts our model).
- Storing any user data on bodyline infrastructure.

## 2. Product requirements

v1 ships the Must-haves plus the Should-haves marked for M2–M5; Good-to-haves wait for post-v1. Each feature lists the milestone it lands in (section 3).

### Must have

| Feature | User story | Acceptance criteria | Milestone |
| --- | --- | --- | --- |
| Profiles & family | As a family manager, I keep a separate profile for each person | Add, edit, switch, delete profiles; each has name, relation, sex, DOB; switching changes every screen | M1 |
| Manual entry by panel | As a user, I enter a CBC or lipid panel without hunting for each test | Panel templates prefill parameters; units and lab range editable per value; saves as one report | M1 |
| Parameter catalogue | As a user, the same test from different labs is recognised as one | \~150 parameters, aliases, unit conversions; custom parameters allowed | M0–M1 |
| Trends | As a user, I see how a value moved over time | Chart with lab-tiered bands, flags, highest/lowest/count, 1Y/3Y/All, history rows open the report | M1 |
| Report vault | As a user, the original report is always kept | PDF/image stored encrypted, attached to the report, viewable anytime | M1 |
| Medical profile | As a user, I have conditions, allergies, surgeries, vaccinations, family history, emergency contacts | CRUD for each section; shown on Health profile screen | M3 |
| Reminders | As a user, I'm reminded when a test or visit is due | One-off and recurring (RRULE); local notifications; shown on Home | M3 |
| Privacy basics | As a user, my data is protected on my device | Encrypted DB, app lock (PIN/biometric), full export, delete all | M1 (lock M3) |

### Should have

| Feature | User story | Acceptance criteria | Milestone |
| --- | --- | --- | --- |
| Report extraction (OCR) | As a user, I photograph or upload a report instead of typing | On-device OCR; values matched to catalogue; review screen handles ambiguous, suspicious and unknown values; ≥80% accepted without edits on the test corpus | M2 |
| Body map home | As a user, I see at a glance which areas were tested and which need attention | Organs coloured by latest status; untested shown faint; tap opens organ detail | M3 |
| Organ detail | As a user, I see everything linked to one organ | Linked tests, related meds, doctors, family history, suggested next test | M3 |
| Doctor visits | As a user, I log visits with diagnosis and prescription | Visit linked to reports, conditions, meds; prescription photo attached | M3 |
| Encrypted sync | As a user with two devices, my data follows me | Sync via user's Google Drive; recovery key; new-device restore | M4 |
| Medications | As a user, I track meds and get dose reminders | Schedules, taken/skipped log, linked to condition; start markers on trend charts | M5 |
| Vitals | As a user, BP, sugar and weight from my phone flow in | Manual entry + Health Connect / HealthKit import, deduped | M5 |
| Doctor summary | As a user, I hand my doctor a one-page summary | PDF: profile, current meds, allergies, key trends, flagged values | M5 |
| Privacy screen | As a user, I can hide content from screenshots | Toggle, off by default | M4 |

### Good to have (post-v1)

- Short knowledge snippets per parameter and organ (reviewed content).
- Caregiver sharing via an encrypted export or a shared cloud folder.
- Emergency medical card (lock screen / QR).
- Cross-data insights ("LDL down 22% since starting medication").
- Hindi and regional-language UI.
- Bills and insurance documents on visits.
- Bring-your-own AI key for hard-to-read reports.

### Key user flows

1. **First run:** create own profile → optional passphrase and recovery key → add first report → land on Home.
2. **Add a report:** + → camera / file → OCR → review (resolve flagged rows) → save → trends update.
3. **Check a trend:** Home → organ or Needs attention → Trend → history row → original report.
4. **Family:** tap name → Family → pick profile → everything switches.
5. **Doctor visit:** Health profile → Doctor summary PDF → share.

## 3. Roadmap

v1 is about 22 weeks of work for a team of two Flutter developers, landing a private beta around week 16 and public Android launch around week 22. Each milestone ends at a checkpoint where the exit test must pass before the next starts.

| Milestone | Weeks | Scope | Exit test |
| --- | --- | --- | --- |
| M0 – Foundations | 1–2 | Flutter project, CI, adapter interfaces, SQLCipher, catalogue v1 (\~150 params + Indian-lab aliases), report corpus of 15–20 real reports | Catalogue matches every parameter in the corpus (manual check) |
| M1 – Usable core | 3–6 | Profiles, panel-based manual entry, trends with tiered bands, report vault, export/delete | All corpus reports entered and charted by hand |
| M2 – Low-friction entry | 7–10 | On-device OCR, catalogue matcher, review screen, per-lab templates | ≥80% of values accepted without edits on the corpus |
| M3 – Complete profile | 11–14 | Medical profile sections, visits, reminders, body map, organ detail, app lock | Full profile of one family entered; reminders fire on time |
| M4 – Multi-device | 15–17 | Encrypted Drive sync, recovery key, new-device restore, privacy screen; **private beta** | Two devices converge after offline edits on both; restore on a fresh phone |
| M5 – Extended | 18–22 | Medications, Health Connect vitals, doctor PDF, desktop build, store listing; **public Android launch** | Beta feedback triaged; crash-free ≥99.5% for 2 weeks |

The week counts assume two developers and no major scope change; they are estimates to plan against, not commitments.

### After v1

| Phase | Focus |
| --- | --- |
| v1.1 | iOS release (iCloud sync adapter, HealthKit) |
| v1.2 | Desktop public release (Windows, macOS), bulk import of old reports |
| v1.3 | Knowledge snippets, emergency card, Hindi UI |
| v2 | Caregiver sharing, insights, bring-your-own AI key, web app |

### Dependencies and risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| OCR accuracy on phone photos is low | Users fall back to manual entry and churn | Per-lab templates; review screen; corpus benchmark gate at M2 |
| Catalogue quality | Wrong matches, wrong flags | Build from real reports; custom parameters; review before public launch |
| Sync conflicts / data loss | Loss of trust | Append-only logs, tombstones, HLC; test suite of conflict scenarios in M4 |
| Lost passphrase | Backup unrecoverable | Recovery key at setup with clear warnings |
| Body-map illustration not ready | Home looks unfinished | Ship prototype silhouette in beta; commission illustration during M2–M3 |
| Name/trademark conflict ("bodyline") | Rebrand late | Trademark and store-name check in M0 |

## 4. Architecture & technical spec

One Flutter codebase with a pure-Dart core and thin platform adapters; no backend services at all.

### Layers

| Layer | Responsibility | Platform code? |
| --- | --- | --- |
| UI (Flutter widgets) | Screens, navigation, theming from design tokens | No |
| Application | Use cases: add report, review, compute flags, schedule reminders | No |
| Core domain (pure Dart) | Catalogue matching, unit conversion, range and band logic, HLC, sync merge | No |
| Adapters | Storage, OCR, cloud sync, health data, notifications, file picking | Yes |

The core must be unit-testable with no device. Every adapter is an interface with a fake for tests.

### Platform adapters

| Adapter | Android | iOS | Desktop | Web |
| --- | --- | --- | --- | --- |
| Storage | SQLCipher (drift) | SQLCipher (drift) | SQLCipher (drift) | Encrypted IndexedDB (TBD) |
| OCR | ML Kit text recognition | Vision | OS OCR, Tesseract fallback | Not supported |
| Sync | Google Drive appDataFolder | iCloud / CloudKit private DB | Google Drive | Google Drive |
| Health data | Health Connect | HealthKit | None | None |
| Notifications | flutter\_local\_notifications | same | OS native | Browser (limited) |

### Storage and encryption

- `catalog.db`: shipped read-only, unencrypted (no user data), replaced on catalogue updates.
- `user.db`: SQLCipher, key derived from a device secret in Android Keystore / iOS Keychain.
- Attachments: encrypted files at `blobs/<sha256>.enc`, never inside the database.
- Optional user passphrase derives the **sync key** (Argon2id). A **recovery key** (random, 24 words) is shown and printable at setup.

### Sync protocol

1. Every synced row carries `id` (UUIDv7), `hlc`, `deleted` (tombstone).
2. Each device appends its local changes to its own encrypted change-log file in the user's cloud folder (`devices/<device_id>/log-<n>.enc`). No two devices ever write the same file.
3. On sync, a device downloads other devices' logs past its `sync_cursor`, merges in one transaction with deferred foreign keys, resolving conflicts row-level last-writer-wins by HLC.
4. Attachments upload once by hash; immutable, so conflict-free.
5. Periodic snapshot compaction: a device writes a full encrypted snapshot; logs before it can be pruned.
6. New device: enter passphrase or recovery key → download latest snapshot + later logs → rebuild.

### OCR pipeline

1. Capture (camera with edge detection) or import PDF/image.
2. PDF with text layer → extract text directly; otherwise on-device OCR per page.
3. Line grouping into rows: name, value, unit, range.
4. Match name against `parameter_alias` (normalised); disambiguate by panel context and unit.
5. Parse value (comparators like "<0.01"), unit (`unit_alias`), range and tiered bands.
6. Sanity checks: value far outside plausible range, unit mismatch, decimal slips → flag for review.
7. Review screen; nothing is saved until the user confirms.

### Flag logic

Lab range → catalogue default range (by sex and age) → none. Tiered bands are shown as printed. Flags are computed, never interpreted: "above lab range", never a condition name.

### Notifications

Reminders sync as data; each device schedules its own OS notifications. Notification ids are device state and never sync.

### Repository conventions

- Monorepo: `app/` (Flutter), `core/` (pure Dart package), `catalog/` (source CSVs + build script producing `catalog.db`), `docs/`.
- State management and routing: pick one in M0 and record it in the decisions log.
- CI on every PR: format, analyse, unit tests for `core`, widget tests, build Android.

## 5. Data model

The full DDL is `data/schema.sql` (v0.2) in the handoff package; this section explains its shape and the rules around it.

### catalog.db (shipped, read-only)

| Table | Holds |
| --- | --- |
| `parameter` | Every test: stable code (`ldl`, `tsh`), name, LOINC, kind (lab / vital / score), canonical unit |
| `parameter_alias` | Normalised names as labs print them, for matching |
| `body_system` | Organs and systems; `map_region` ties to the body-map layer id |
| `parameter_system` | Which parameters belong to which organ |
| `unit_alias`, `unit_conversion` | Unit normalisation and conversion factors |
| `default_ref_range`, `default_ref_band` | Fallback ranges and tiers by sex and age |
| `panel`, `panel_parameter` | Entry templates (CBC, lipid, LFT, KFT, thyroid) |

### user.db (encrypted, synced)

| Table | Holds |
| --- | --- |
| `profile`, `emergency_contact` | People and their contacts |
| `report`, `attachment` | A lab report event and its files |
| `observation` | Every lab value and vital, exactly as printed plus canonical |
| `custom_parameter` | User-defined tests (`custom:<id>`) |
| `condition`, `allergy`, `procedure`, `immunization`, `family_history` | Medical profile |
| `provider`, `lab`, `visit` | Doctors, labs and visits |
| `medication`, `medication_schedule`, `medication_log` | Medications and adherence |
| `reminder` | Tests, panels, visits |
| `local_device`, `sync_cursor`, `scheduled_notification` | Device-only state, never synced |

### Rules

1. User rows reference the catalogue by text code, never by foreign key, so catalogue updates never touch user data.
2. Every synced row has `id` (UUIDv7), `created_at`, `updated_at`, `hlc`, `deleted`. Never hard-delete synced rows.
3. `observation` stores `value_reported`, `unit_reported`, lab range and `ref_bands_json` untouched; `value_canonical` is derived and recomputed on catalogue updates.
4. A vital is an `observation` with `report_id = NULL`. BP systolic and diastolic share a `group_id`.
5. Dates without time are `TEXT 'YYYY-MM-DD'`; timestamps are epoch ms UTC.
6. Schema changes ship as numbered migrations; a device must be able to merge logs written by the previous schema version.

## 6. Privacy, security & compliance

The promise is simple and must stay literally true: no user health data ever reaches bodyline infrastructure. Every item below exists to keep that promise.

### Hard rules

1. No backend stores or processes user data. The only thing we host is the public catalogue file and the website.
2. No third-party SDK that can see health data: no ad SDKs, no session replay, no default analytics.
3. Crash reports are opt-in, stripped of screen contents, values and names before sending.
4. Usage metrics, if any, are opt-in, anonymous counters (e.g. "reports added: 5"), never values.
5. No cloud AI calls through our keys. A future bring-your-own-key option sends data to the user's own provider account.
6. **Android auto-backup disabled** (`allowBackup=false`, data-extraction rules); otherwise the database is copied to Google backup outside our encryption.
7. All data encrypted at rest (SQLCipher + encrypted blobs) and before upload to the user's cloud.

### User controls

| Control | Default |
| --- | --- |
| App lock (PIN / biometric) | On |
| Privacy screen (screenshots, app switcher) | Off |
| Cloud sync | Off until the user connects their Drive |
| Crash reports | Off |
| Full export (encrypted archive, or CSV + PDFs) | Always available |
| Delete all data (device + cloud backup) | Always available |

### Threat model (v1)

| Threat | Mitigation |
| --- | --- |
| Lost or stolen phone | App lock, encrypted DB with key in Keystore/Keychain |
| Someone else using the unlocked phone | App lock on open and after timeout |
| Cloud account compromise | Files are encrypted with the user's passphrase-derived key |
| Screenshots or screen sharing | Optional privacy screen |
| Our own mistake leaking data | No server to leak to; dependency review for network access |

### Compliance posture (India)

- Under the DPDP Act, 2023, bodyline aims not to act as a data fiduciary for health data because it never receives it. Get a legal opinion before public launch.
- Wording avoids diagnosis to stay outside software-as-a-medical-device scope; any future interpretation feature needs a regulatory review first.
- The privacy policy states in plain words what is stored where, and that we cannot recover lost data.
- Store listings: complete Google Play Data safety and Apple privacy labels as "no data collected" only if every rule above holds.

## 7. Design & UX guidelines

The prototype is the source of truth for layout; `design-tokens.json` is the source of truth for colour, type and spacing.

### Screens

| Mobile | Desktop | Notes |
| --- | --- | --- |
| Home (body map) | Overview | Desktop adds tabbed trend and family reminders |
| Tests | Tests (master–detail) |  |
| Trend | (inside Tests) | Lab-tiered bands, medication markers |
| Organ detail | (from body map) |  |
| Records | Records (list + preview) |  |
| Review | Report review (side by side) | Desktop links rows on both sides |
| Health profile | Health profile (grid) | Doctors section on desktop; add to mobile |
| Family | Family | Opened from the profile switcher |
| Settings | Settings |  |

Mobile bottom nav: Home · Tests · Records · Profile. Desktop: 248 px sidebar with the same items plus Settings.

### Visual language

- Colours: deep teal `#0E6B63` (primary, in range), pulse orange `#B8561B` (high), blue `#2A5CA0` (low), ink `#1C2230`, paper `#F6F4EF`.
- Type: Fraunces SemiBold for titles, big numbers and the lowercase wordmark; Manrope for everything else.
- Radii: 8 pills, 12 inputs, 14–18 cards.

### Rules

1. Never red/green for status; always pair colour with a text label ("High", "Low", "In range").
2. Minimum touch target 44 × 44 px.
3. Text contrast ≥ 4.5:1; status text uses the darker tint colours from the tokens.
4. Every chart shows the lab's bands and labels them; no unlabeled lines.
5. Support system font scaling up to 200% on mobile without clipping.
6. Dark mode in v1.1; tokens already include dark icon variants.

### Copy guidelines

| Write | Don't write |
| --- | --- |
| Above the lab's range | You have high cholesterol |
| Low in 3 of the last 4 tests | Your vitamin D is dangerously low |
| Talk to your doctor about this result | You should start medication |
| Read as 18 — check the decimal | Invalid value |
| Not tested yet | Missing data |

Tone: calm, plain, short. No exclamation marks, no emoji, no health scores or grades.

### Body map brief (production illustration)

- Style B, soft silhouette: natural proportions, warm fill `#EDE3D8`, no face.
- One named layer per organ, id matching `body_system.code` / `map_region`.
- Variants: male, female, child; front and back views.
- States per organ: in range (teal), high (orange + halo), low (blue + halo), untested (faint/dashed).
- Deliver as SVG with clean, flat layers; the app recolours layers at runtime.

## 8. Parameter catalogue & content

The catalogue is the product's core asset: catalogue v1 ships about 150 parameters covering the panels Indian labs run most, with the aliases those labs actually print.

### v1 coverage

| Panel | Example parameters |
| --- | --- |
| CBC | Haemoglobin, RBC, WBC, platelets, differential counts, MCV, MCH, MCHC, RDW, ESR |
| Lipid profile | Total cholesterol, LDL, HDL, VLDL, triglycerides, ratios |
| Liver (LFT) | ALT/SGPT, AST/SGOT, ALP, GGT, bilirubin (total/direct), albumin, total protein |
| Kidney (KFT) | Creatinine, urea, BUN, uric acid, eGFR, sodium, potassium, chloride |
| Diabetes | Fasting glucose, post-meal glucose, random glucose, HbA1c, fasting insulin |
| Thyroid | TSH, T3, T4, free T3, free T4 |
| Vitamins & minerals | Vitamin D (25-OH), B12, folate, iron, ferritin, TIBC, calcium, magnesium |
| Urine routine | Colour, pH, specific gravity, protein, glucose, ketones, pus cells, RBC |
| Cardiac & inflammation | hs-CRP, CRP, homocysteine, lipoprotein(a) |
| Vitals | BP systolic/diastolic, pulse, weight, BMI, SpO₂, temperature |

### How it's built

1. Collect the report corpus (15–20 real reports from different labs: Lal PathLabs, SRL, Thyrocare, Metropolis, local labs, hospital labs).
2. For each parameter: code, name, LOINC where available, canonical unit, organ mapping, panel membership.
3. Record every alias exactly as seen, then normalise (lowercase, strip punctuation).
4. Unit conversions per parameter (e.g. glucose mg/dL ↔ mmol/L) plus generic ones.
5. Default ranges and tiered bands by sex and age from standard references, used only when a report has none.
6. Source lives as CSVs in `catalog/`; a build script produces `catalog.db` with a version number.

### Content rules

- Parameter explainers are one or two sentences: what it measures and which organ it relates to. No interpretation of individual results.
- Every explainer and default range cites a reference in the source CSV.
- A domain expert reviews ranges, organ mappings and explainers before public launch.
- Catalogue updates ship as a public, signed JSON/DB file; the app verifies the signature before replacing.

## 9. QA, testing & release

Three things get the heaviest testing because failures there break trust: extraction accuracy, flag correctness and sync.

### Test layers

| Layer | What | Target |
| --- | --- | --- |
| Unit (core) | Matching, unit conversion, flags, bands, HLC, merge | ≥90% coverage of `core/` |
| Golden files | Known report → expected extracted values | Every corpus report |
| Widget | Key screens render with sample data, font scaling | All screens |
| Integration | Add report → review → trend; reminders fire | Main flows |
| Sync scenarios | Offline edits on 2–3 devices, deletes vs edits, schema upgrade mid-sync | Scripted suite, runs in CI |
| Manual | Real phone photos of real reports, low light, folded paper | Before each release |

### Benchmarks

- OCR: ≥80% of values accepted without edits on the corpus; zero silent mis-saves (every wrong read must be caught by review or sanity checks).
- Flags: 100% agreement with the lab's own printed flags on the corpus.
- Performance: Home opens in < 1 s with 5 years of data for 4 profiles; trend renders in < 300 ms.

### Device matrix (Android first)

| Tier | Example | Why |
| --- | --- | --- |
| Low-end | 3–4 GB RAM, Android 10–11 | Parents' phones |
| Mid | Samsung A-series, Android 13–14 | Most users |
| High | Recent flagship, Android 15+ | Camera and OCR best case |

### Release process

1. Internal track → closed beta (friends and family, 20–50 users) → open beta → production.
2. Staged rollout: 10% → 50% → 100% over a week, watching opt-in crash reports.
3. Release checklist: migrations tested on previous version's data, backup-disabled check, Data safety form, privacy policy, catalogue version bumped if changed, changelog.

## 10. Team workflow, decisions & open questions

Work runs in two-week sprints inside each milestone, with a demo and checkpoint review at every milestone exit.

### Workflow

- Trunk-based: short-lived branches, PRs reviewed by one other developer, CI green before merge.
- Every PR that touches `core/` adds or updates unit tests; every schema change adds a migration and a sync-scenario test.
- Architecture or product changes get a line in the decisions log below before code is written.
- Real health data never goes into the repo, issue tracker or screenshots; use the synthetic sample family.

### Definition of done

1. Meets the acceptance criteria in section 2.
2. Tests added and passing in CI.
3. Works at 200% font scale and on a low-end device.
4. Copy follows section 7; no red/green, no diagnosis.
5. No new network access or SDK without a privacy review.
6. Demoed on a real device.

### Decisions log

| Date | Decision | Why |
| --- | --- | --- |
| 26 Sep 2026 | Name **bodyline**, heart-and-pulse mark | Heart = body, pulse = line; logo explains the name |
| 26 Sep 2026 | Body map style B (soft silhouette) | Human and calm; not cartoonish |
| 26 Sep 2026 | Flutter, Android first | One codebase for mobile, desktop and web |
| 26 Sep 2026 | Local-first; sync only to the user's own cloud | Privacy promise; no data-fiduciary burden |
| 26 Sep 2026 | On-device OCR, no cloud AI through our keys | Keeps the privacy promise |
| 26 Sep 2026 | Lab-printed range first, tiered bands stored as printed | Labs differ; tiers matter (Vitamin D, LDL, HbA1c) |
| 26 Sep 2026 | Screenshot blocking is a user toggle, off by default | User choice over enforced friction |
| 26 Sep 2026 | No ABDM/ABHA integration | Needs a server; contradicts local-first |

### Open questions

- [ ] State management and routing libraries (decide in M0).
- [ ] Web storage approach for encrypted data.
- [ ] Business model: free, one-time purchase, or paid sync/features.
- [ ] Trademark, domain and store-name clearance for "bodyline".
- [ ] Who illustrates the production body map, and by when.
- [ ] Legal review of the DPDP posture before public launch.
- [ ] Domain expert for catalogue and explainer review.
