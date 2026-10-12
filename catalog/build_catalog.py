#!/usr/bin/env python3
"""Build a read-only catalog.db from CSV seeds (no user data)."""
from __future__ import annotations

import csv
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parent
CSV = ROOT / "csv"
OUT = ROOT / "catalog.db"


def load(conn: sqlite3.Connection, table: str, path: Path) -> None:
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


def main() -> None:
    schema = ROOT.parent / "docs" / "schema.sql"
    text = schema.read_text(encoding="utf-8")
    # Only apply catalog.db DDL (stop before user.db section).
    catalog_ddl = text.split("PART 2: user.db")[0]
    if OUT.exists():
        OUT.unlink()
    conn = sqlite3.connect(OUT)
    conn.executescript(catalog_ddl)
    conn.execute(
        "INSERT INTO catalog_meta(key, value) VALUES ('version', ?), ('released_at', ?)",
        ("0.1.0-seed", "2026-09-26"),
    )
    load(conn, "body_system", CSV / "body_system.csv")
    load(conn, "parameter", CSV / "parameter.csv")
    load(conn, "parameter_alias", CSV / "parameter_alias.csv")
    load(conn, "parameter_system", CSV / "parameter_system.csv")
    load(conn, "panel", CSV / "panel.csv")
    load(conn, "panel_parameter", CSV / "panel_parameter.csv")
    conn.commit()
    n = conn.execute("SELECT COUNT(*) FROM parameter").fetchone()[0]
    p = conn.execute("SELECT COUNT(*) FROM panel").fetchone()[0]
    conn.close()
    print(f"Wrote {OUT} ({n} parameters, {p} panels)")


if __name__ == "__main__":
    main()
