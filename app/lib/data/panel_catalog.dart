/// Panel/param types + offline seed fallback.
/// Source of truth: `assets/catalog/catalog.db` via [LocalStore.catalogPanels]
/// (catalogue v2.1 → ~202 params / 21 panels; seed below is offline fallback).
class PanelDef {
  const PanelDef(this.code, this.name, this.parameters);
  final String code;
  final String name;
  final List<ParamDef> parameters;
}

class ParamDef {
  const ParamDef(this.code, this.name, this.unit, {this.shortName});
  final String code;
  /// Full catalogue name (e.g. Haemoglobin) — use in UI titles.
  final String name;
  final String unit;
  /// Abbreviation when present (e.g. HB) — subtitle only, never the title.
  final String? shortName;

  String get subtitleCode {
    final s = shortName?.trim();
    if (s != null && s.isNotEmpty) return s;
    return code;
  }
}

const seededPanels = <PanelDef>[
  PanelDef('lipid', 'Lipid Profile', [
    ParamDef('tc', 'Total Cholesterol', 'mg/dL'),
    ParamDef('ldl', 'LDL Cholesterol', 'mg/dL'),
    ParamDef('hdl', 'HDL Cholesterol', 'mg/dL'),
    ParamDef('vldl', 'VLDL Cholesterol', 'mg/dL'),
    ParamDef('tg', 'Triglycerides', 'mg/dL'),
    ParamDef('non_hdl', 'Non-HDL Cholesterol', 'mg/dL'),
  ]),
  PanelDef('cbc', 'Complete Blood Count', [
    ParamDef('hb', 'Haemoglobin', shortName: 'HB', 'g/dL'),
    ParamDef('rbc', 'Red blood cell count', shortName: 'RBC', '10^6/µL'),
    ParamDef('wbc', 'Total leucocyte count', shortName: 'WBC', '10^3/µL'),
    ParamDef('plt', 'Platelets', '10^3/µL'),
    ParamDef('hct', 'Haematocrit (PCV)', shortName: 'HCT', '%'),
  ]),
  PanelDef('diabetes', 'Diabetes Panel', [
    ParamDef('glu_f', 'Glucose Fasting', 'mg/dL'),
    ParamDef('glu_pp', 'Glucose Postprandial', 'mg/dL'),
    ParamDef('hba1c', 'Glycated haemoglobin', shortName: 'HbA1c', '%'),
  ]),
  PanelDef('thyroid', 'Thyroid Profile', [
    ParamDef('tsh', 'Thyroid-stimulating hormone', shortName: 'TSH', 'µIU/mL'),
    ParamDef('ft4', 'Thyroxine (free)', shortName: 'Free T4', 'ng/dL'),
    ParamDef('ft3', 'Triiodothyronine (free)', shortName: 'Free T3', 'pg/mL'),
  ]),
  PanelDef('lft', 'Liver Function Test', [
    ParamDef('alt', 'Alanine aminotransferase', shortName: 'ALT', 'U/L'),
    ParamDef('ast', 'Aspartate aminotransferase', shortName: 'AST', 'U/L'),
    ParamDef('bil_t', 'Bilirubin Total', 'mg/dL'),
    ParamDef('alp', 'Alkaline Phosphatase', 'U/L'),
  ]),
  PanelDef('kft', 'Kidney Function Test', [
    ParamDef('creat', 'Creatinine', 'mg/dL'),
    ParamDef('urea', 'Urea', 'mg/dL'),
    ParamDef('egfr', 'eGFR', 'mL/min/1.73m²'),
    ParamDef('uric', 'Uric Acid', 'mg/dL'),
  ]),
  PanelDef('vitamins', 'Vitamins', [
    ParamDef('vitd', 'Vitamin D (25-OH)', 'ng/mL'),
    ParamDef('b12', 'Vitamin B12', 'pg/mL'),
    ParamDef('folate', 'Folate', 'ng/mL'),
  ]),
  PanelDef('iron', 'Iron Studies', [
    ParamDef('iron', 'Serum Iron', 'µg/dL'),
    ParamDef('ferritin', 'Ferritin', 'ng/mL'),
    ParamDef('tibc', 'TIBC', 'µg/dL'),
  ]),
  PanelDef('electrolytes', 'Electrolytes', [
    ParamDef('na', 'Sodium', 'mmol/L'),
    ParamDef('k', 'Potassium', 'mmol/L'),
    ParamDef('cl', 'Chloride', 'mmol/L'),
  ]),
];
