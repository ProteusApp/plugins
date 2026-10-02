-- sheet_formula: the formula language of the Sheet app. A tokenizer and a parser turn the
-- text after "=" into a tree, and an evaluator walks the tree. Formula text never runs as Lua.
--
-- The same tokens drive the rewrites of formula text: moving the references of a copied
-- formula, fixing references after a row or a column is inserted or deleted, and following a
-- sheet that is renamed or deleted. The helpers at the end serve the formula bar while a
-- formula is typed: completion, the argument being typed, reference colours and F4.
--
-- This module puts the parts of the language together and holds the types they share.
-- sheet_formula_lex makes the module table and holds errors, addresses, text, numbers, dates
-- and the tokenizer. sheet_formula_parse, sheet_formula_eval, sheet_formula_kit, which loads
-- the function modules sheet_fn_*, and sheet_formula_edit each add their functions to it.

local lexer = require ('sheet_formula_lex') --[[@as Sheet.FormulaLex]]

require ('sheet_formula_parse')
require ('sheet_formula_eval')
require ('sheet_formula_kit')
require ('sheet_formula_edit')

---A spreadsheet error, such as `#DIV/0!`. Each code has one shared table, so two errors with
---the same code are equal.
---@class Sheet.Error
---@field code string

---A cell value. Nil is an empty cell.
---@alias Sheet.Value number|string|boolean|Sheet.Error|nil

---A list of values that may have holes, such as the arguments of a function.
---@alias Sheet.Values table<integer, Sheet.Value>

---One end of a reference. A whole column has no row, and a whole row has no column.
---@class Sheet.Ref
---@field row? integer
---@field col? integer
---@field row_abs boolean True when the row has a `$`.
---@field col_abs boolean True when the column has a `$`.
---@field sheet? string The sheet it names, without quotes. Nil means the formula's own sheet.

---@alias Sheet.TokenKind 'number'|'string'|'error'|'ref'|'range'|'name'|'op'|'open'|'close'|'comma'|'lbrace'|'rbrace'|'semicolon'

---@class Sheet.Token
---@field kind Sheet.TokenKind
---@field text string The source text.
---@field from integer The first byte.
---@field to integer The last byte.
---@field value? number|string
---@field a? Sheet.Ref A reference, or the first end of a range.
---@field b? Sheet.Ref The second end of a range.
---@field sheet? string The sheet a reference names, without quotes.
---@field sheet_text? string The sheet part of a reference as written, with its quotes and "!".
---@field spill? boolean True for a reference to the block a formula spills, such as `A1#`.

---@alias Sheet.NodeKind 'number'|'string'|'bool'|'error'|'ref'|'range'|'spill'|'name'|'call'|'invoke'|'unary'|'binary'|'percent'|'empty'|'array'|'intersect'|'union'

---A node of the formula tree.
---@class Sheet.Node
---@field kind Sheet.NodeKind
---@field value? number|string|boolean
---@field op? string
---@field left? Sheet.Node The operand of a unary or percent node, the left side, or the function an invoke node calls.
---@field right? Sheet.Node
---@field name? string A function or a name, in upper case.
---@field args? Sheet.Node[]
---@field a? Sheet.Ref
---@field b? Sheet.Ref
---@field array? Sheet.Array The values of an array constant such as `{1,2;3,4}`.

---A block of cells a formula reads. Whole columns leave the rows out, and whole rows leave the
---columns out.
---@class Sheet.Area
---@field r1? integer
---@field c1? integer
---@field r2? integer
---@field c2? integer
---@field sheet? string The sheet it names. Nil means the formula's own sheet.

---A block of cells with every side known, top left to bottom right.
---@class Sheet.Rect
---@field r1 integer
---@field c1 integer
---@field r2 integer
---@field c2 integer

---A block of cells as a value, while a function reads it.
---@class Sheet.RangeValue: Sheet.Rect
---@field is_range true
---@field sheet? string

---A block of values worked out by a formula, such as `{1,2;3,4}` or `A1:A3*2`. The values run
---row by row, and an empty cell leaves a hole.
---@class Sheet.Array
---@field is_array true
---@field h integer
---@field w integer
---@field v Sheet.Values

---@alias Sheet.Grid Sheet.RangeValue|Sheet.Array

---Several blocks of cells as one reference, from the union operator, as in `(A1:A3,C1:C3)`.
---Functions that read every value, such as SUM, read each block.
---@class Sheet.Union
---@field is_union true
---@field areas Sheet.RangeValue[]

---A function a formula makes with LAMBDA. It keeps the names around it when it was made.
---@class Sheet.Lambda
---@field is_lambda true
---@field params string[] The names of its arguments, in upper case.
---@field body Sheet.Node
---@field scope? Sheet.Scope

---Names that LET and LAMBDA give values, inside the part of a formula they cover.
---@class Sheet.Scope
---@field names table<string, Sheet.Result|Sheet.Lambda>
---@field parent? Sheet.Scope

---@alias Sheet.Result Sheet.Value|Sheet.RangeValue|Sheet.Array|Sheet.Lambda

---What the evaluator needs from a workbook.
---@class Sheet.Context
---@field value fun(row: integer, col: integer, sheet?: string): Sheet.Value
---@field rows integer The last row a whole column reaches.
---@field cols integer The last column a whole row reaches.
---@field size? fun(sheet: string): integer?, integer? The rows and columns of a named sheet, or nil when there is no such sheet.
---@field clock? fun(): number The date and time now, as a serial number of days.
---@field random? fun(): number
---@field row? integer The row of the cell being worked out, for ROW() with no argument.
---@field col? integer The column of the cell being worked out, for COLUMN() with no argument.
---@field spill? fun(row: integer, col: integer, sheet?: string): integer?, integer? The height and width of the block a formula's cell spills, or nil when it spills none.
---@field scope? Sheet.Scope The names LET and LAMBDA give, while their part of a formula is worked out.
---@field hidden? fun(row: integer, sheet?: string): 'filter'|'user'|nil Why a row is hidden: by the filter or by the user.
---@field subtotal? fun(row: integer, col: integer, sheet?: string): boolean True when a cell holds a SUBTOTAL or an AGGREGATE, which those leave out.
---@field formula_text? fun(row: integer, col: integer, sheet?: string): string? The formula a cell holds, with its "=", or nil.
---@field sheet_index? fun(sheet?: string): integer? Where a sheet sits in the book, the formula's own when nil.
---@field sheet_count? fun(): integer
---@field name? fun(name: string): Sheet.Node? The parsed formula a defined name stands for, by its name in upper case.
---@field name_depth? integer How deep names that name other names go, while one is worked out.

---A function the formulas can call. `run` gets the argument trees and works them out as it
---needs to. `map` gets the argument values instead, and runs once for each value when an
---argument is a block of cells. With `catch`, `map` also gets errors as values.
---@class Sheet.Function
---@field min integer
---@field max integer
---@field run? fun(args: Sheet.Node[], ctx: Sheet.Context): Sheet.Result
---@field map? fun(v: Sheet.Values, n: integer, ctx: Sheet.Context): Sheet.Value
---@field catch? boolean

---@alias Sheet.Category 'Math'|'Statistics'|'Logic'|'Text'|'Lookup'|'Date'|'Info'|'Financial'

---@class Sheet.CatalogEntry
---@field name string
---@field category Sheet.Category
---@field syntax string Such as `SUMIF(range, criterion, [sum_range])`.
---@field summary string One plain sentence.

---A function name being typed, from `complete`.
---@class Sheet.Completion
---@field from integer The first byte of the name.
---@field to integer The last byte of the name, which may run on past the caret.
---@field prefix string The part of the name before the caret, as typed.

---The function whose arguments hold the caret, from `call_at`.
---@class Sheet.CallInfo
---@field name string In upper case.
---@field arg integer Counts from 1.

---A reference in formula text, from `ref_spans`.
---@class Sheet.RefSpan
---@field from integer
---@field to integer
---@field area Sheet.Area

---@class Sheet.MoveOptions
---@field from string The sheet the block moves from.
---@field to string The sheet the block moves to.
---@field own string The sheet the formula lives on.
---@field lands? string The sheet the formula lives on after the move, when it moves too.

---@class Sheet.AdjustOptions
---@field sheet? string The sheet where the rows or columns changed.
---@field own? string The sheet the formula lives on.

---An open bracket while formula text is scanned.
---@class Sheet.Frame
---@field name? string The function the bracket belongs to, or nil for a plain bracket.
---@field arg integer
---@field brace boolean True for the `{` of an array constant.

---@class Sheet.Parser
---@field tokens Sheet.Token[]
---@field i integer
---@field depth integer

---@class Sheet.FormulaModule
local M = lexer.M

return M
