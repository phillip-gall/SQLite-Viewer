# Plan 08d: Inspect storage categories

## Goal

Make every category in the storage distribution bar selectable. Selection expands that category to the full bar width and shows where its bytes come from.

## Planning

Read [the architecture](00-architecture.md), [Plan 06](06-storage-analysis.md), `StorageReport`, `StorageWorkspaceModel`, and `StorageWorkspaceView`. Check `git status` and recent commits. Confirm how the current table detail and report refresh work before adding category selection.

## Implementation

1. Give the five existing categories stable identities: table data, indexes, other B-trees, free pages, and overhead. Build category breakdowns from the current `StorageReport`. Table data uses each table's own B-tree. Indexes sums each table's indexes. Other uses the reported unassigned B-trees by name and description. Free pages and overhead each have one `Unassigned` item because neither has a defensible table owner. Check each breakdown sums to its category total; reject or label inconsistent data instead of inventing a remainder.
2. Make each nonzero bar segment and every legend row a selectable control. The legend must also select zero-byte categories, whose segment has no tappable width. Give thin segments a usable touch target without changing their proportional display. Expose category name, bytes, percentage of logical total, and selected state to VoiceOver.
3. On selection, replace the overview bar with a full-width bar divided by that category's contributors in proportion to the category total. Keep the category label and its share of the whole database visible. Below it, list contributor names, bytes, and percentages of the selected category in a deterministic order. For a zero-byte category, show an empty full-width track and `No pages in this category`. For free pages and overhead, show a single full-width `Unassigned` segment with an explanation. Provide a clear Back to overview action; selecting another legend category changes the breakdown directly.
4. Keep category selection independent of the existing per-table detail. On refresh after SQL, rebuild the breakdown from the new report, retain a still-valid selected category, and recompute its contributors. WAL stays outside the logical bar and has no category selection.

## Testing

Use fixtures with several tables and indexes, unassigned SQLite or shadow B-trees, free pages, overhead, and a WAL sidecar. Assert contributor sums match category totals and percentages use the selected category as denominator. Add UI tests for tapping a thin segment or its legend, full-width expansion, switching categories, Back to overview, zero-byte selection, and refresh after CREATE INDEX or DROP TABLE. Run affected unit and UI tests on an available simulator.

## Review

Inspect reconciliation, table ownership claims, zero denominators, color and text contrast, small touch targets, accessibility, selection after refresh, and separation of WAL bytes. Run `git diff --check` and inspect `git status`.

## Commit

Stage only this plan's changes and commit as `Add storage category drilldowns`. In the body state how unassigned bytes appear and list the tests run. Complete the final checks in [Plan 08](08-product-improvements.md) before committing.

## Done when

Every category can be selected, fills the bar on selection, and shows a breakdown that reconciles with the existing storage total without attributing free pages or overhead to a table.
