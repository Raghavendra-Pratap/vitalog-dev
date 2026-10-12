-- =====================================================================
-- BODYLINE — DATA MODEL v0.2  (v0.2: tiered reference bands)
-- Two SQLite databases:
--   catalog.db : shipped with the app, read-only, replaceable on update,
--                unencrypted (contains no user data)
--   user.db    : SQLCipher-encrypted, all personal data, synced
-- User data references catalog entries by stable TEXT codes, never by FK,
-- so the catalog can be swapped without touching user.db.
-- =====================================================================


-- =====================================================================
-- PART 1: catalog.db
-- =====================================================================

CREATE TABLE catalog_meta (
  key   TEXT PRIMARY KEY,          -- 'version', 'released_at'
  value TEXT NOT NULL
);

-- Organs / glands / systems. Drives the body map and grouping.
CREATE TABLE body_system (
  code        TEXT PRIMARY KEY,    -- 'thyroid', 'liver', 'kidney', 'blood'
  name        TEXT NOT NULL,
  parent_code TEXT REFERENCES body_system(code),  -- 'thyroid' -> 'endocrine'
  map_region  TEXT,                -- SVG region id on the body map
  sort_order  INTEGER
);

CREATE TABLE parameter (
  code           TEXT PRIMARY KEY, -- stable slug: 'alt', 'glucose_fasting', 'tsh'
  name           TEXT NOT NULL,    -- 'Alanine Aminotransferase'
  short_name     TEXT,             -- 'ALT'
  loinc          TEXT,             -- optional interoperability code
  specimen       TEXT,             -- 'serum', 'whole_blood', 'urine'
  kind           TEXT NOT NULL DEFAULT 'lab'
                 CHECK (kind IN ('lab', 'vital', 'score')),
  value_type     TEXT NOT NULL
                 CHECK (value_type IN ('numeric', 'text', 'ordinal', 'boolean')),
  canonical_unit TEXT,             -- unit all trends are charted in
  decimals       INTEGER NOT NULL DEFAULT 2,
  summary        TEXT              -- one-line explainer shown on trend screen
);

-- OCR / manual-entry matching. alias_norm = lowercased, punctuation-stripped.
-- Same alias may map to several parameters ('glucose'); resolve using
-- surrounding report context or ask the user in the review step.
CREATE TABLE parameter_alias (
  alias_norm     TEXT NOT NULL,
  parameter_code TEXT NOT NULL REFERENCES parameter(code),
  PRIMARY KEY (alias_norm, parameter_code)
);

CREATE TABLE parameter_system (
  parameter_code TEXT NOT NULL REFERENCES parameter(code),
  system_code    TEXT NOT NULL REFERENCES body_system(code),
  relevance      INTEGER NOT NULL DEFAULT 1,  -- 1 primary, 2 secondary
  PRIMARY KEY (parameter_code, system_code)
);

CREATE TABLE unit_alias (
  alias_norm TEXT PRIMARY KEY,     -- 'mg/dl', 'mg / dl', 'mgdl'
  unit_code  TEXT NOT NULL         -- 'mg/dL'
);

-- parameter_code = '*' for generic conversions (g/L -> mg/dL).
-- Parameter-specific rows win over generic ones (glucose mg/dL -> mmol/L).
-- canonical = value * factor + offset
CREATE TABLE unit_conversion (
  parameter_code TEXT NOT NULL,
  from_unit      TEXT NOT NULL,
  to_unit        TEXT NOT NULL,
  factor         REAL NOT NULL,
  offset         REAL NOT NULL DEFAULT 0,
  PRIMARY KEY (parameter_code, from_unit, to_unit)
);

-- Fallback only. The lab's own printed range always takes precedence.
CREATE TABLE default_ref_range (
  id             INTEGER PRIMARY KEY,
  parameter_code TEXT NOT NULL REFERENCES parameter(code),
  sex            TEXT NOT NULL DEFAULT 'any' CHECK (sex IN ('M', 'F', 'any')),
  age_min_days   INTEGER NOT NULL DEFAULT 0,
  age_max_days   INTEGER,          -- NULL = no upper bound
  low            REAL,
  high           REAL,
  unit           TEXT NOT NULL,
  note           TEXT
);

-- Tiered fallback bands (Vitamin D: deficient / insufficient / sufficient;
-- LDL: optimal / near optimal / borderline / high; HbA1c: normal / prediabetes / diabetes)
CREATE TABLE default_ref_band (
  id             INTEGER PRIMARY KEY,
  parameter_code TEXT NOT NULL REFERENCES parameter(code),
  sex            TEXT NOT NULL DEFAULT 'any' CHECK (sex IN ('M', 'F', 'any')),
  age_min_days   INTEGER NOT NULL DEFAULT 0,
  age_max_days   INTEGER,
  label          TEXT NOT NULL,
  low            REAL,             -- NULL = open-ended
  high           REAL,
  unit           TEXT NOT NULL,
  severity       TEXT NOT NULL CHECK (severity IN ('optimal', 'normal', 'watch', 'high', 'low', 'critical')),
  sort_order     INTEGER NOT NULL
);

-- Test panels as entry templates: 'lipid_profile', 'cbc', 'lft', 'kft'
CREATE TABLE panel (
  code TEXT PRIMARY KEY,
  name TEXT NOT NULL
);

CREATE TABLE panel_parameter (
  panel_code     TEXT NOT NULL REFERENCES panel(code),
  parameter_code TEXT NOT NULL REFERENCES parameter(code),
  position       INTEGER NOT NULL,
  PRIMARY KEY (panel_code, parameter_code)
);


-- =====================================================================
-- PART 2: user.db (SQLCipher)
--
-- Every SYNCED table carries these columns:
--   id         TEXT PRIMARY KEY  -- UUIDv7 (time-ordered, generated on device)
--   created_at INTEGER NOT NULL  -- epoch ms UTC
--   updated_at INTEGER NOT NULL  -- epoch ms UTC (display only)
--   hlc        TEXT NOT NULL     -- hybrid logical clock; conflict ordering
--   deleted    INTEGER NOT NULL DEFAULT 0  -- tombstone, never hard-delete
--
-- Conflict rule: row-level last-writer-wins by hlc.
-- FKs are declared; sync merges run with PRAGMA defer_foreign_keys = ON
-- inside one transaction so out-of-order rows don't fail.
-- Date-only fields are TEXT 'YYYY-MM-DD'.
-- =====================================================================

CREATE TABLE profile (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  relation    TEXT NOT NULL DEFAULT 'self'
              CHECK (relation IN ('self', 'spouse', 'parent', 'child',
                                  'sibling', 'grandparent', 'other')),
  sex         TEXT CHECK (sex IN ('M', 'F', 'other')),  -- for ref-range selection
  dob         TEXT,
  blood_group TEXT,
  color       TEXT,               -- avatar / family screen accent
  is_primary  INTEGER NOT NULL DEFAULT 0,
  notes       TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE emergency_contact (
  id         TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profile(id),
  name       TEXT NOT NULL,
  relation   TEXT,
  phone      TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE provider (             -- doctors / clinics
  id        TEXT PRIMARY KEY,
  name      TEXT NOT NULL,
  specialty TEXT,
  facility  TEXT,
  phone     TEXT,
  address   TEXT,
  notes     TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE lab (                  -- enables per-lab OCR templates later
  id        TEXT PRIMARY KEY,
  name      TEXT NOT NULL,
  city      TEXT,
  template  TEXT,                   -- optional parser hint / template id
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE visit (
  id             TEXT PRIMARY KEY,
  profile_id     TEXT NOT NULL REFERENCES profile(id),
  provider_id    TEXT REFERENCES provider(id),
  visited_at     INTEGER NOT NULL,
  reason         TEXT,
  diagnosis      TEXT,
  notes          TEXT,
  follow_up_date TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

-- One lab report / document event. Observations hang off it.
CREATE TABLE report (
  id           TEXT PRIMARY KEY,
  profile_id   TEXT NOT NULL REFERENCES profile(id),
  lab_id       TEXT REFERENCES lab(id),
  visit_id     TEXT REFERENCES visit(id),   -- ordered during this visit
  title        TEXT,
  collected_at INTEGER NOT NULL,            -- sample collection time
  reported_at  INTEGER,
  source       TEXT NOT NULL CHECK (source IN ('manual', 'ocr', 'import')),
  status       TEXT NOT NULL DEFAULT 'draft'
               CHECK (status IN ('draft', 'verified')),
  notes        TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

-- Files live outside the DB as blobs/<sha256>.enc (encrypted, immutable,
-- content-addressed => deduped and conflict-free during sync).
CREATE TABLE attachment (
  id          TEXT PRIMARY KEY,
  owner_type  TEXT NOT NULL
              CHECK (owner_type IN ('report', 'visit', 'medication',
                                    'condition', 'profile', 'procedure')),
  owner_id    TEXT NOT NULL,
  sha256      TEXT NOT NULL,
  mime        TEXT NOT NULL,
  byte_size   INTEGER NOT NULL,
  page_count  INTEGER,
  file_name   TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_attachment_owner ON attachment(owner_type, owner_id);

-- Parameters not in the catalog. Referenced as code 'custom:<id>'.
CREATE TABLE custom_parameter (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  unit        TEXT,
  value_type  TEXT NOT NULL DEFAULT 'numeric'
              CHECK (value_type IN ('numeric', 'text', 'ordinal', 'boolean')),
  system_code TEXT,                          -- body map placement
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

-- Single table for lab values AND vitals. A vital is an observation
-- with report_id = NULL. Everything trends the same way.
CREATE TABLE observation (
  id              TEXT PRIMARY KEY,
  profile_id      TEXT NOT NULL REFERENCES profile(id),
  report_id       TEXT REFERENCES report(id),
  parameter_code  TEXT NOT NULL,             -- catalog code or 'custom:<id>'
  observed_at     INTEGER NOT NULL,          -- = report.collected_at for labs

  -- exactly as printed (source of truth)
  value_reported  TEXT NOT NULL,             -- '<0.01', '12.4', 'Positive'
  unit_reported   TEXT,
  comparator      TEXT CHECK (comparator IN ('<', '<=', '>', '>=')),
  value_num       REAL,                      -- parsed numeric part
  value_text      TEXT,                      -- for text / ordinal results

  -- derived, recomputed when catalog changes
  value_canonical REAL,
  unit_canonical  TEXT,

  -- reference range: lab's printed range preferred
  ref_low         REAL,
  ref_high        REAL,
  ref_text        TEXT,                      -- non-numeric ranges, e.g. 'Negative'
  ref_bands_json  TEXT,                      -- tiers as printed, e.g.
                                             -- [{"label":"Sufficient","low":30,"high":100}, ...]
  ref_source      TEXT NOT NULL DEFAULT 'none'
                  CHECK (ref_source IN ('lab', 'default', 'none')),

  flag            TEXT CHECK (flag IN ('normal', 'low', 'high', 'abnormal',
                                       'critical_low', 'critical_high')),
  flag_source     TEXT CHECK (flag_source IN ('lab', 'computed')),

  source          TEXT NOT NULL
                  CHECK (source IN ('manual', 'ocr', 'health_connect',
                                    'healthkit', 'import')),
  external_id     TEXT,                      -- dedupe for health platform imports
  ocr_confidence  REAL,
  verified        INTEGER NOT NULL DEFAULT 0,
  group_id        TEXT,                      -- ties BP systolic + diastolic
  note            TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_obs_trend  ON observation(profile_id, parameter_code, observed_at);
CREATE INDEX idx_obs_report ON observation(report_id);
CREATE UNIQUE INDEX idx_obs_external
  ON observation(source, external_id) WHERE external_id IS NOT NULL;

-- ---------- Medical profile ----------

CREATE TABLE condition (
  id            TEXT PRIMARY KEY,
  profile_id    TEXT NOT NULL REFERENCES profile(id),
  name          TEXT NOT NULL,
  status        TEXT NOT NULL DEFAULT 'active'
                CHECK (status IN ('active', 'resolved', 'monitoring')),
  onset_date    TEXT,
  resolved_date TEXT,
  visit_id      TEXT REFERENCES visit(id),   -- where it was diagnosed
  notes         TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE allergy (
  id         TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profile(id),
  substance  TEXT NOT NULL,
  category   TEXT CHECK (category IN ('drug', 'food', 'environment', 'other')),
  reaction   TEXT,
  severity   TEXT CHECK (severity IN ('mild', 'moderate', 'severe')),
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE procedure (             -- surgeries, major procedures
  id         TEXT PRIMARY KEY,
  profile_id TEXT NOT NULL REFERENCES profile(id),
  name       TEXT NOT NULL,
  performed_on TEXT,
  facility   TEXT,
  notes      TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE immunization (
  id          TEXT PRIMARY KEY,
  profile_id  TEXT NOT NULL REFERENCES profile(id),
  vaccine     TEXT NOT NULL,
  dose_number INTEGER,
  given_on    TEXT,
  next_due_on TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE family_history (
  id           TEXT PRIMARY KEY,
  profile_id   TEXT NOT NULL REFERENCES profile(id),
  relation     TEXT NOT NULL,          -- 'father', 'maternal grandmother'
  condition    TEXT NOT NULL,
  age_at_onset INTEGER,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

-- ---------- Medications ----------

CREATE TABLE medication (
  id           TEXT PRIMARY KEY,
  profile_id   TEXT NOT NULL REFERENCES profile(id),
  name         TEXT NOT NULL,
  strength     TEXT,                    -- '500 mg'
  form         TEXT,                    -- tablet, syrup, injection
  route        TEXT,
  condition_id TEXT REFERENCES condition(id),
  visit_id     TEXT REFERENCES visit(id),   -- prescribed at
  start_date   TEXT,
  end_date     TEXT,                    -- NULL = ongoing
  instructions TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE medication_schedule (
  id            TEXT PRIMARY KEY,
  medication_id TEXT NOT NULL REFERENCES medication(id),
  rrule         TEXT NOT NULL,          -- RFC 5545: 'FREQ=DAILY'
  times_json    TEXT NOT NULL,          -- '["08:00","20:00"]' local time
  dose_amount   REAL,
  dose_unit     TEXT,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE medication_log (
  id            TEXT PRIMARY KEY,
  medication_id TEXT NOT NULL REFERENCES medication(id),
  scheduled_for INTEGER NOT NULL,
  status        TEXT NOT NULL CHECK (status IN ('taken', 'skipped', 'missed')),
  acted_at      INTEGER,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);
-- two devices logging the same dose collapse to one row
CREATE UNIQUE INDEX idx_medlog_dose ON medication_log(medication_id, scheduled_for);

-- ---------- Reminders ----------

CREATE TABLE reminder (
  id           TEXT PRIMARY KEY,
  profile_id   TEXT NOT NULL REFERENCES profile(id),
  kind         TEXT NOT NULL
               CHECK (kind IN ('test', 'panel', 'visit', 'custom')),
  title        TEXT NOT NULL,
  target_code  TEXT,                  -- parameter or panel code
  provider_id  TEXT REFERENCES provider(id),
  rrule        TEXT,                  -- NULL = one-off
  due_at       INTEGER NOT NULL,      -- next occurrence
  lead_minutes INTEGER NOT NULL DEFAULT 1440,
  active       INTEGER NOT NULL DEFAULT 1,
  last_done_at INTEGER,
  created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL,
  hlc TEXT NOT NULL, deleted INTEGER NOT NULL DEFAULT 0
);
-- Medication reminders are derived from medication_schedule, not stored here.


-- =====================================================================
-- PART 3: LOCAL-ONLY tables in user.db (never synced)
-- =====================================================================

CREATE TABLE local_device (
  device_id   TEXT PRIMARY KEY,       -- generated once per install
  hlc_last    TEXT NOT NULL           -- last HLC issued on this device
);

-- Per remote device: how far we have merged its change log.
CREATE TABLE sync_cursor (
  remote_device_id TEXT PRIMARY KEY,
  last_hlc         TEXT NOT NULL,
  last_synced_at   INTEGER NOT NULL
);

-- OS notification ids are device state, not user data.
CREATE TABLE scheduled_notification (
  source_type   TEXT NOT NULL CHECK (source_type IN ('reminder', 'medication')),
  source_id     TEXT NOT NULL,
  fire_at       INTEGER NOT NULL,
  os_notif_id   TEXT NOT NULL,
  PRIMARY KEY (source_type, source_id, fire_at)
);
