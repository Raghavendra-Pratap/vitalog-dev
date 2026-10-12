# bodyline — desktop / tablet (landscape) mockups

**Source of truth** for wide layout (desktop app + tablet horizontal).

Imported from:

`/Volumes/Mac-Extension/Product - UI/bodyline/bodyline - desktop mockup`

| Artboard | Folder | Notes |
|---|---|---|
| Overview | `overview/` | 1440×900 · 248px sidebar · 272px body column |
| Tests | `tests/` | Master–detail · 400px list |
| Records | `records/` | Master–detail · 440px timeline |
| Report review | `report-review/` | PDF + values side by side |
| Health profile | `health-profile/` | Section grid |
| Family | `family/` | Profile switcher |
| Settings | `settings/` | Groups + danger zone |

## Layout rules (locked)

- Frame: **1440 × 900** reference
- Sidebar: **248px**, `#FBF9F4`, border `#E2DDD2`
- Main padding: **28×32**, gap **20**
- Nav: Home · Tests · Records · Health profile · Settings (settings pinned bottom)
- Type: Fraunces display · Manrope UI
- Paper `#F6F4EF` · surface `#FFFDF8` · teal `#0E6B63` · ink `#1C2230`

## App mapping

- Flutter `useWideShell(context)`: desktop OS **or** width ≥ **900** (tablet landscape / large).
- Phone and tablet portrait keep the mobile bottom-nav shell.
- Implement these artboards — do not invent a third layout.

## Viewing

Live React render needs `vendor/` from the Mac-Extension export. Inline `style=` values on the `.dc.html` files are the design tokens to replicate.


## Flutter screens

| Artboard | Implementation |
|---|---|
| Overview | `HomeScreen(desktop: true)` + `DesktopShell` |
| Tests | `TestsScreen(desktop: true)` master–detail |
| Records | `RecordsScreen(desktop: true)` master–detail |
| Report review | `ReportReviewScreen` (Add report → Review PDF) |
| Health profile | `ProfileScreen(desktop: true)` 2-col sections |
| Family | `FamilyScreen` (sidebar profile switcher) |
| Settings | `SettingsScreen(desktop: true)` |
