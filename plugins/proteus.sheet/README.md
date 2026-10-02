# Sheet

A spreadsheet with formulas, formats, charts and several sheets per workbook. Install the **Sheet** profile from the marketplace to run it as an app of its own. The profile runs the marketplace too, so more plugins install from inside the app: press **Ctrl+Shift+X**.

## What it does

- **Workbooks.** Each workbook is a file in `data/proteus.sheet/`, listed in the Workbooks view. Before 0.3.0 they lived in `data/sheets/`, and Proteus moves them on its first start.
- **Files on disk.** File > Open Excel or CSV file… opens an `.xlsx`, `.csv` or `.tsv` file in place, and Save (Ctrl+S) writes it back in the same format. The Code Editor's explorer opens these files here too. A file that opened with nothing left out saves by itself as a workbook does. One that lost something on the way in, such as a picture, saves only when you choose Save, and asks before you leave it with changes. CSV text with numbers such as `00123` asks whether to keep their zeros as text.
- **Formulas.** Close to 300 functions, such as `SUM`, `VLOOKUP`, `XLOOKUP`, `IF`, `TEXT`, `SUBTOTAL`, `NORM.DIST`, `XIRR` and `CONVERT`, with references between sheets. A change recalculates only the cells that depend on it, found through an index of the blocks each formula reads, and a formula with the wrong count of arguments says so as it goes in.
- **Big sheets.** The grid draws only the rows and columns near the view, and an edit writes again only the rows it changed. Rows grow for big fonts, line breaks and wrapped text as you type. Undo keeps an insert or a delete as the move itself, not a copy of the sheet.
- **Dynamic arrays.** A formula that gives a block, such as `=SORT(A2:C9)`, `=FILTER(...)`, `=UNIQUE(...)` or `=SEQUENCE(5)`, spills into the cells around it, and `A1#` reads the whole block. A block with no room shows `#SPILL!`. `LET` names values inside a formula, and `LAMBDA` makes functions for `MAP`, `REDUCE`, `SCAN`, `BYROW`, `BYCOL` and `MAKEARRAY`.
- **Names.** Data > Defined names gives a range, a value or a `LAMBDA` a name that any formula can use, such as `=SUM(Sales)` or `=Double(21)`. Names follow their cells, and Excel files bring and keep them.
- **Formats.** Number formats, fonts, colours, borders, alignment, merged cells and conditional formats.
- **Notes and links.** A note on any cell, and a link to a web or mail address or to a place in the book, such as `#Sheet2!A1` (Insert > Link, Ctrl+K). Ctrl+click follows a place in the book, and copies an address.
- **Data.** Sort, filter, find and replace, data validation, and frozen or hidden rows and columns.
- **Charts.** Column, bar, line, area, pie, doughnut and scatter charts, drawn from a range.
- **Files.** Import and export CSV and Excel (`.xlsx`) files. Excel files keep notes, links, conditional formats, validation, the filter, charts and defined names, both ways.

The parts live in their own modules: `sheet_formula` holds the formula language, the `sheet_fn_*` modules more of its functions, `sheet_calendar` the dates both typing and formulas read, `sheet_book`, `sheet_model` and `sheet_ops` the workbook, `sheet_xlsx` and `sheet_xlsx_parts` the Excel format, `sheet_chart` the charts, and the `sheet_grid*` and `sheet_panel*` modules the screen. Their tests are in `tests/`.

## Permissions

| Permission | Why |
|------------|-----|
| `files` | Import, Export and opening a file in place read and write CSV and Excel files anywhere on disk, picked in the system's dialogs or opened from the Code Editor's explorer. The Excel reader runs in Lua and needs the file itself, which a file grant, made for web views, does not give. |
| `clipboard` | Paste reads cells from the clipboard. |

It writes workbooks only in its own `data/proteus.sheet/` folder.
