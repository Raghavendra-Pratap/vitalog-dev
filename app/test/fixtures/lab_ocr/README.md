# Lab OCR / paste corpus (M2)

Sample report snippets for `normalizeOcrLabText`, `lab_parse_quality`, and (later) full `parseLabText` with catalog.db.

Keep samples short, anonymized, and representative of Indian lab layouts.
Do not commit real patient reports.

| File | Covers |
|------|--------|
| `lipid_messy_ocr.txt` | Spaced units, Cholestrol misspelling, stacked lipid rows |
| `thyroid_spaced_ocr.txt` | TSH / HbA1c OCR splits |
| `redcliffe_lft_interpretation.txt` | LFT table + H* flags + accession IDs + Interpretation glossary |
| `redcliffe_lft_prose_first.txt` | Glossary before table (OCR reading-order failure) |
| `redcliffe_lft_vision_macos.txt` | Real Apple Vision dump (bbox-sorted) from Redcliffe LFT photo |
| `redcliffe_lft_ag_ratio.txt` | Redcliffe A/G `Albumin :Globulin Ratio` + unit `-` → expect 1.92 |
| `redcliffe_lft_mlkit_typos.txt` | Mobile OCR typos (SUggest/darmage) + GGT caret + Globulin IDs |
| `redcliffe_lft_vision_unsorted.txt` | Unsorted Vision shape: GGT adjacent to Bilirubin 0.7 |
| `redcliffe_lft_dual_labels.txt` | Consecutive SGOT/SGPT labels then two value groups |

## redcliffe_lft_android_partial.txt

Approximates Android photo OCR that matched only **4** LFT rows in 0.1.10:
good same-line ALT/Albumin/Bili-total/Total-protein, plus orphans and
slash→I units (`UIL`, `mgIdL`, `gIdL`) and `up to N` ranges. Used to
drive unit-repair + orphan-label attach toward ≥10 matches.

| `agilus_thyroid_footer_only.txt` | Android photo OCR of Agilus footer only (0 matches) |
| `agilus_thyroid_table.txt` | Agilus thyroid T3/T4/TSH + multi-line pregnancy refs |
| `redcliffe_lft_android_six_plus.txt` | Device-like 6 same-line hits + 6 harder stacked/orphan rows |
| `agilus_thyroid_inline_pregnant.txt` | Device OCR: same-line value + Non-Pregnant Women + unit (Pg/pIU) |
