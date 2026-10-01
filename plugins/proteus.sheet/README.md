# Sheet

A spreadsheet with formulas, formats, charts and several sheets per workbook. Install the **Sheet** profile from the marketplace to run it as an app of its own.

## What it does

- **Workbooks.** Each workbook is a file in `data/proteus.sheet/`, listed in the Workbooks view. Before 0.3.0 they lived in `data/sheets/`, and Proteus moves them on its first start.
- **Formulas.** Over 180 functions, such as `SUM`, `VLOOKUP`, `XLOOKUP`, `IF` and `TEXT`, with references between sheets. A change recalculates only the cells that depend on it.
- **Formats.** Number formats, fonts, colours, borders, alignment, merged cells and conditional formats.
- **Data.** Sort, filter, find and replace, data validation, and frozen or hidden rows and columns.
- **Charts.** Column, bar, line, area, pie, doughnut and scatter charts, drawn from a range.
- **Files.** Import and export CSV and Excel (`.xlsx`) files.

The parts live in their own modules: `sheet_formula` holds the formula language, `sheet_book`, `sheet_model` and `sheet_ops` the workbook, `sheet_xlsx` the Excel format, `sheet_chart` the charts, and the `sheet_grid*` and `sheet_panel*` modules the screen. Their tests are in `tests/`.

## Permissions

| Permission | Why |
|------------|-----|
| `files` | Import and Export read and write CSV and Excel files anywhere on disk, picked in the system's dialogs. |
| `clipboard` | Paste reads cells from the clipboard. |

It writes workbooks only in its own `data/proteus.sheet/` folder.
