#!/usr/bin/env python3
"""Convert vitalog_catalogue_csv_v1 → catalog/csv seeds + rebuild catalog.db."""
from __future__ import annotations

import csv
import re
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent
V1 = ROOT.parent / "vitalog_catalogue_csv_v1"
CSV_OUT = ROOT / "csv"
OUT_DB = ROOT / "catalog.db"
APP_DB = ROOT.parent / "app" / "assets" / "catalog" / "catalog.db"

# Map vitalog body_system → catalog body_system (map_region must match SVG ids).
SYSTEM_MAP = {
    "blood": ("blood", "Blood", None, "blood", 10),
    "heart": ("heart", "Heart", None, "heart", 20),
    "liver": ("liver", "Liver", None, "liver", 30),
    "kidney": ("kidney", "Kidney", None, "kidney", 40),
    "pancreas": ("metabolic", "Metabolic", None, "metabolic", 60),
    "thyroid": ("thyroid", "Thyroid", "endocrine", "thyroid", 51),
    "parathyroid": ("thyroid", "Thyroid", "endocrine", "thyroid", 51),
    "bones": ("metabolic", "Metabolic", None, "metabolic", 60),
    "pituitary": ("endocrine", "Endocrine", None, "endocrine", 50),
    "adrenal": ("endocrine", "Endocrine", None, "endocrine", 50),
    "reproductive": ("endocrine", "Endocrine", None, "endocrine", 50),
    "prostate": ("endocrine", "Endocrine", None, "endocrine", 50),
    "immune": ("blood", "Blood", None, "blood", 10),
    "lungs": ("metabolic", "Metabolic", None, "metabolic", 60),
    "general": ("metabolic", "Metabolic", None, "metabolic", 60),
}

# Old app codes → new catalogue codes (aliases + optional dual lookup).
LEGACY_CODE_ALIASES: dict[str, str] = {
    "haemoglobin": "hb",
    "hemoglobin": "hb",
    "platelets": "plt",
    "total_cholesterol": "tc",
    "triglycerides": "tg",
    "glucose_fasting": "glu_f",
    "glucose_pp": "glu_pp",
    "glucose_random": "glu_r",
    "bilirubin_total": "bil_t",
    "bilirubin_direct": "bil_d",
    "bilirubin_indirect": "bil_i",
    "creatinine": "creat",
    "uric_acid": "uric",
    "vitamin_d": "vitd",
    "vitamin_b12": "b12",
    "serum_iron": "iron",
    "sodium": "na",
    "potassium": "k",
    "chloride": "cl",
    "calcium": "ca",
    "phosphorus": "phos",
    "magnesium": "mg",
    "albumin": "alb",
    "total_protein": "tp",
    "globulin": "glob",
    "ag_ratio": "ag_ratio",
    "neutrophils": "neut_pct",
    "lymphocytes": "lymph_pct",
    "monocytes": "mono_pct",
    "eosinophils": "eos_pct",
    "basophils": "baso_pct",
    "absolute_neutrophil": "anc",
    "absolute_lymphocyte": "alc",
    "hematocrit": "hct",
    "haematocrit": "hct",
    "pcv": "hct",
    "mean_platelet_volume": "mpv",
    "rdw": "rdw_cv",
    "egfr": "egfr",
    "hba1c": "hba1c",
    "tsh": "tsh",
    "ft3": "ft3",
    "ft4": "ft4",
    "t3": "t3",
    "t4": "t4",
    "alt": "alt",
    "ast": "ast",
    "alp": "alp",
    "ggt": "ggt",
    "ldl": "ldl",
    "hdl": "hdl",
    "vldl": "vldl",
    "ferritin": "ferritin",
    "tibc": "tibc",
    "transferrin_saturation": "tsat",
    "crp": "crp",
    "hscrp": "hscrp",
    "homocysteine": "homocys",
    "cortisol": "cortisol",
    "testosterone": "testo",
    "free_testosterone": "ftesto",
    "estradiol": "e2",
    "progesterone": "prog",
    "prolactin": "prl",
    "fsh": "fsh",
    "lh": "lh",
    "amh": "amh",
    "psa": "psa",
    "free_psa": "fpsa",
    "cea": "cea",
    "ca125": "ca125",
    "ca19_9": "ca199",
    "ca15_3": "ca153",
    "afp": "afp",
    "beta_hcg": "bhcg",
    "pth": "pth",
    "insulin": "ins_f",
    "c_peptide": "cpep",
    "troponin_i": "trop_i",
    "troponin_t": "trop_t",
    "ck": "cpk",
    "ck_mb": "ckmb",
    "nt_probnp": "ntprobnp",
    "bnp": "bnp",
    "ldh": "ldh",
    "pt": "pt",
    "inr": "inr",
    "aptt": "aptt",
    "d_dimer": "ddimer",
    "fibrinogen": "fibrinogen",
    "rf": "ra",
    "aso": "aso",
    "ige": "ige",
    "hbsag": "hbsag",
    "anti_hcv": "anti_hcv",
    "hiv": "hiv",
    "vdrl": "vdrl",
    "blood_group": "blood_group",
    "abo_group": "blood_group",
    "bp_systolic": "bp_sys",
    "bp_diastolic": "bp_dia",
    "zinc": "zinc",
    "folate": "folate",
    "amylase": "amylase",
    "lipase": "lipase",
    "urea": "urea",
    "bun": "bun",
    "non_hdl": "non_hdl",
    "apo_a1": "apoa1",
    "apo_b": "apob",
    "lp_a": "lpa",
    "procalcitonin": "procalcitonin",
    "plateletcrit": "plateletcrit",
    "acr": "uacr",
}

# Short LOINC hints from research (confirmed ✓ where known).
LOINC: dict[str, str] = {
    "hb": "718-7",
    "rbc": "789-8",
    "hct": "4544-3",
    "mcv": "787-2",
    "mch": "785-6",
    "mchc": "786-4",
    "rdw_cv": "788-0",
    "wbc": "6690-2",
    "lymph_pct": "736-9",
    "mono_pct": "5905-5",
    "amc": "742-7",
    "plt": "777-3",
    "plateletcrit": "51637-7",
    "plcr": "48386-7",
    "ldl": "18262-6",
    "vldl": "13458-5",
    "non_hdl": "43396-1",
    "tc_hdl": "9830-1",
    "ldl_hdl": "11054-4",
    "apoa1": "1869-7",
    "apob": "1884-6",
    "lpa": "10835-7",
    "bil_t": "1975-2",
    "bil_d": "1968-7",
    "bil_i": "1971-1",
    "ast": "1920-8",
    "alt": "1742-6",
    "alp": "6768-6",
    "ggt": "2324-2",
    "alb": "1751-7",
    "glob": "10834-0",
    "ag_ratio": "1759-0",
    "creat": "2160-0",
    "bun": "3094-0",
    "egfr": "98979-8",
    "u_malb": "14957-5",
    "uacr": "9318-7",
    "u_creat": "2161-8",
    "na": "2951-2",
    "k": "2823-3",
    "cl": "2075-0",
    "hco3": "1963-8",
    "ca": "17861-6",
    "ica": "1994-3",
    "phos": "2777-1",
    "mg": "19123-9",
    "glu_f": "1558-6",
    "glu_pp": "1521-4",
    "glu_r": "2345-7",
    "hba1c": "4548-4",
    "eag": "27353-2",
    "ins_f": "20448-7",
    "homa_ir": "47214-2",
    "cpep": "1986-9",
    "fruct": "15069-8",
    "amylase": "1798-8",
    "lipase": "3040-3",
    "tsh": "3016-3",
    "t3": "3053-6",
    "t4": "3026-2",
    "ft3": "3051-0",
    "ft4": "3024-7",
    "thyroglobulin": "3013-0",
    "rt3": "3052-8",
    "vitd": "62292-8",
    "vitd_125": "62290-2",
    "b12": "2132-9",
    "folate": "2284-8",
    "iron": "2498-4",
    "tibc": "2500-7",
    "uibc": "2501-5",
    "tsat": "2502-3",
    "ferritin": "2276-4",
    "transferrin": "3034-6",
    "hscrp": "30522-7",
    "crp": "1988-5",
    "homocys": "13965-9",
    "trop_i": "10839-9",
    "trop_t": "67151-1",
    "ckmb": "13969-1",
    "cpk": "2157-6",
    "ntprobnp": "33762-6",
    "bnp": "30934-4",
    "ldh": "2532-0",
    "ddimer": "48065-7",
    "cortisol": "2143-6",
    "prl": "2842-3",
    "fsh": "15067-2",
    "lh": "10501-5",
    "e2": "2243-4",
    "testo": "2986-8",
    "ftesto": "2991-8",
    "dheas": "2191-5",
    "shbg": "13967-5",
    "amh": "38476-8",
    "bhcg": "21198-7",
    "pth": "2731-8",
    "psa": "2857-1",
    "fpsa": "10886-0",
    "cea": "2039-6",
    "ca125": "10334-1",
    "ca199": "24108-3",
    "ca153": "6875-9",
    "ra": "11572-5",
    "anti_ccp": "32218-0",
    "aso": "5370-2",
    "ige": "19113-0",
    "hbsag": "5196-1",
    "anti_hcv": "16128-1",
    "hiv": "56888-1",
    "vdrl": "5292-8",
    "dengue_ns1": "75377-2",
    "procalcitonin": "33959-8",
    "blood_group": "882-1",
    "u_pus": "5821-4",
    "stool_ob": "2335-8",
    "tc": "2093-3",
    "tg": "2571-8",
    "hdl": "2085-9",
}


def norm_alias(s: str) -> str:
    n = s.lower()
    n = n.replace("µ", "u").replace("μ", "u").replace("β", "beta")
    n = re.sub(r"[^a-z0-9]", "", n)
    n = n.replace("hemoglobin", "haemoglobin")
    n = n.replace("hematocrit", "haematocrit")
    return n


def write_csv(path: Path, fieldnames: list[str], rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        w.writeheader()
        for r in rows:
            w.writerow({k: r.get(k, "") if r.get(k) is not None else "" for k in fieldnames})


def main() -> None:
    with (V1 / "parameters.csv").open(encoding="utf-8") as f:
        v_params = list(csv.DictReader(f))
    with (V1 / "parameter_aliases.csv").open(encoding="utf-8") as f:
        v_aliases = list(csv.DictReader(f))
    with (V1 / "panels.csv").open(encoding="utf-8") as f:
        v_panels = list(csv.DictReader(f))
    with (V1 / "unit_aliases.csv").open(encoding="utf-8") as f:
        v_units = list(csv.DictReader(f))
    with (V1 / "unit_conversions.csv").open(encoding="utf-8") as f:
        v_conv = list(csv.DictReader(f))

    # --- body_system (stable map regions for body map) ---
    systems: dict[str, dict] = {}
    for code, name, parent, region, order in {
        ("blood", "Blood", None, "blood", 10),
        ("heart", "Heart", None, "heart", 20),
        ("liver", "Liver", None, "liver", 30),
        ("kidney", "Kidney", None, "kidney", 40),
        ("endocrine", "Endocrine", None, "endocrine", 50),
        ("thyroid", "Thyroid", "endocrine", "thyroid", 51),
        ("metabolic", "Metabolic", None, "metabolic", 60),
    }:
        systems[code] = {
            "code": code,
            "name": name,
            "parent_code": parent or "",
            "map_region": region,
            "sort_order": order,
        }

    # --- parameters ---
    param_rows = []
    param_system_rows = []
    seen_ps: set[tuple[str, str]] = set()
    for p in v_params:
        code = p["code"].strip()
        body = p["body_system"].strip()
        mapped = SYSTEM_MAP.get(body, ("metabolic", "Metabolic", None, "metabolic", 60))
        sys_code = mapped[0]
        specimen = (p.get("specimen") or "").strip()
        # Normalize specimen tokens for schema (free text ok)
        specimen_norm = specimen.replace(" ", "_").lower() if specimen else ""
        if "whole blood" in specimen.lower():
            specimen_norm = "whole_blood"
        elif "urine" in specimen.lower():
            specimen_norm = "urine"
        elif "plasma" in specimen.lower():
            specimen_norm = "plasma"
        elif "serum" in specimen.lower():
            specimen_norm = "serum"
        elif "stool" in specimen.lower():
            specimen_norm = "stool"

        kind = (p.get("kind") or "lab").strip()
        if kind not in ("lab", "vital", "score"):
            kind = "lab"
        value_type = (p.get("value_type") or "numeric").strip()
        if value_type not in ("numeric", "text", "ordinal", "boolean"):
            value_type = "numeric"

        short = code.upper() if len(code) <= 6 else code
        # Prefer a readable short from name initials for long codes
        name = p["name"].strip()
        param_rows.append(
            {
                "code": code,
                "name": name,
                "short_name": short,
                "loinc": LOINC.get(code, ""),
                "specimen": specimen_norm,
                "kind": kind,
                "value_type": value_type,
                "canonical_unit": (p.get("canonical_unit") or "").strip(),
                "decimals": p.get("decimals") or "2",
                "summary": (p.get("notes") or "").strip()[:200],
            }
        )
        key = (code, sys_code)
        if key not in seen_ps:
            seen_ps.add(key)
            param_system_rows.append(
                {"parameter_code": code, "system_code": sys_code, "relevance": 1}
            )

    codes = {r["code"] for r in param_rows}

    # --- aliases ---
    alias_rows: list[dict] = []
    seen_alias: set[tuple[str, str]] = set()

    def add_alias(alias_norm: str, parameter_code: str) -> None:
        if not alias_norm or len(alias_norm) < 2:
            return
        if parameter_code not in codes:
            return
        key = (alias_norm, parameter_code)
        if key in seen_alias:
            return
        seen_alias.add(key)
        alias_rows.append({"alias_norm": alias_norm, "parameter_code": parameter_code})

    for a in v_aliases:
        pc = a["parameter_code"].strip()
        printed = (a.get("alias_as_printed") or "").strip()
        pre_norm = (a.get("alias_norm") or "").strip()
        add_alias(norm_alias(printed), pc)
        if pre_norm:
            add_alias(norm_alias(pre_norm), pc)
            add_alias(pre_norm.replace(" ", ""), pc)

    # Fix PCT: bare "pct" must map to BOTH plateletcrit and procalcitonin
    add_alias("pct", "plateletcrit")
    add_alias("pct", "procalcitonin")
    add_alias("plateletcrit", "plateletcrit")
    add_alias("procalcitonin", "procalcitonin")

    # Legacy codes as aliases → new codes
    for old, new in LEGACY_CODE_ALIASES.items():
        add_alias(norm_alias(old), new)
        add_alias(old.replace("_", ""), new)

    # Code and name themselves
    for p in param_rows:
        add_alias(norm_alias(p["code"]), p["code"])
        add_alias(norm_alias(p["name"]), p["code"])
        if p["short_name"]:
            add_alias(norm_alias(p["short_name"]), p["code"])

    # --- panels ---
    panel_rows = []
    panel_param_rows = []
    for pan in v_panels:
        pcode = pan["code"].strip()
        panel_rows.append({"code": pcode, "name": pan["name"].strip()})
        pos = 1
        for pc in pan["parameter_codes"].split(";"):
            pc = pc.strip()
            if not pc or pc not in codes:
                continue
            panel_param_rows.append(
                {"panel_code": pcode, "parameter_code": pc, "position": pos}
            )
            pos += 1

    # --- unit aliases ---
    unit_alias_rows = []
    seen_ua: set[str] = set()
    for row in v_units:
        canon = row["unit"].strip()
        for printed in row["printed_as"].split(";"):
            printed = printed.strip()
            if not printed:
                continue
            an = norm_alias(printed)
            if not an or an in seen_ua:
                continue
            seen_ua.add(an)
            unit_alias_rows.append({"alias_norm": an, "unit_code": canon})
        # also canon itself
        cn = norm_alias(canon)
        if cn and cn not in seen_ua:
            seen_ua.add(cn)
            unit_alias_rows.append({"alias_norm": cn, "unit_code": canon})

    # Extra Indian / research tokens
    for printed, canon in [
        ("mlln/cu.mm", "10^6/µL"),
        ("mllncumm", "10^6/µL"),
        ("mcu/ml", "µIU/mL"),
        ("mcU/mL", "µIU/mL"),
        ("u/l at 37c", "U/L"),
    ]:
        an = norm_alias(printed)
        if an and an not in seen_ua:
            seen_ua.add(an)
            unit_alias_rows.append({"alias_norm": an, "unit_code": canon})

    # --- unit conversions ---
    conv_rows = []
    seen_c: set[tuple[str, str, str]] = set()
    for row in v_conv:
        pc = (row.get("parameter_code") or "*").strip() or "*"
        fu = row["from_unit"].strip()
        tu = row["to_unit"].strip()
        key = (pc, fu, tu)
        if key in seen_c:
            continue
        seen_c.add(key)
        conv_rows.append(
            {
                "parameter_code": pc,
                "from_unit": fu,
                "to_unit": tu,
                "factor": row["factor"],
                "offset": row.get("offset") or "0",
            }
        )

    write_csv(
        CSV_OUT / "body_system.csv",
        ["code", "name", "parent_code", "map_region", "sort_order"],
        list(systems.values()),
    )
    write_csv(
        CSV_OUT / "parameter.csv",
        [
            "code",
            "name",
            "short_name",
            "loinc",
            "specimen",
            "kind",
            "value_type",
            "canonical_unit",
            "decimals",
            "summary",
        ],
        param_rows,
    )
    write_csv(
        CSV_OUT / "parameter_alias.csv",
        ["alias_norm", "parameter_code"],
        alias_rows,
    )
    write_csv(
        CSV_OUT / "parameter_system.csv",
        ["parameter_code", "system_code", "relevance"],
        param_system_rows,
    )
    write_csv(CSV_OUT / "panel.csv", ["code", "name"], panel_rows)
    write_csv(
        CSV_OUT / "panel_parameter.csv",
        ["panel_code", "parameter_code", "position"],
        panel_param_rows,
    )
    write_csv(
        CSV_OUT / "unit_alias.csv",
        ["alias_norm", "unit_code"],
        unit_alias_rows,
    )
    write_csv(
        CSV_OUT / "unit_conversion.csv",
        ["parameter_code", "from_unit", "to_unit", "factor", "offset"],
        conv_rows,
    )

    # Rebuild DB (extend build_catalog to include units)
    schema = ROOT.parent / "docs" / "schema.sql"
    text = schema.read_text(encoding="utf-8")
    catalog_ddl = text.split("PART 2: user.db")[0]
    if OUT_DB.exists():
        OUT_DB.unlink()
    conn = sqlite3.connect(OUT_DB)
    conn.executescript(catalog_ddl)
    conn.execute(
        "INSERT INTO catalog_meta(key, value) VALUES ('version', ?), ('released_at', ?)",
        ("0.2.0-vitalog-v1", "2026-09-28"),
    )

    def load(table: str, path: Path) -> None:
        with path.open(newline="", encoding="utf-8") as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            if not rows:
                return
            cols = list(rows[0].keys())
            placeholders = ",".join("?" for _ in cols)
            col_sql = ",".join(cols)
            conn.executemany(
                f"INSERT INTO {table} ({col_sql}) VALUES ({placeholders})",
                [tuple(r[c] if r[c] != "" else None for c in cols) for r in rows],
            )

    load("body_system", CSV_OUT / "body_system.csv")
    load("parameter", CSV_OUT / "parameter.csv")
    load("parameter_alias", CSV_OUT / "parameter_alias.csv")
    load("parameter_system", CSV_OUT / "parameter_system.csv")
    load("panel", CSV_OUT / "panel.csv")
    load("panel_parameter", CSV_OUT / "panel_parameter.csv")
    load("unit_alias", CSV_OUT / "unit_alias.csv")
    load("unit_conversion", CSV_OUT / "unit_conversion.csv")
    conn.commit()
    n = conn.execute("SELECT COUNT(*) FROM parameter").fetchone()[0]
    a = conn.execute("SELECT COUNT(*) FROM parameter_alias").fetchone()[0]
    p = conn.execute("SELECT COUNT(*) FROM panel").fetchone()[0]
    # PCT sanity
    pct = conn.execute(
        "SELECT parameter_code FROM parameter_alias WHERE alias_norm='pct' ORDER BY 1"
    ).fetchall()
    conn.close()

    APP_DB.parent.mkdir(parents=True, exist_ok=True)
    APP_DB.write_bytes(OUT_DB.read_bytes())
    print(
        f"Wrote {OUT_DB} + {APP_DB}: {n} parameters, {a} aliases, {p} panels; pct→{[r[0] for r in pct]}"
    )


if __name__ == "__main__":
    main()
