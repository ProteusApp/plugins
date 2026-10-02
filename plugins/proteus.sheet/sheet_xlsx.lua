-- sheet_xlsx: Excel files for the Sheet app. `read` turns the XML files inside an `.xlsx` zip
-- into workbook data, and `write` turns workbook data back into those files. The host does the
-- zipping. The module draws nothing and calls no host function.
--
-- An Excel file can hold more than a workbook file keeps. Whatever does not come across, such
-- as pictures or pivot tables, is named in a list of warnings. Notes, links, conditional
-- formats, validation, the filter and charts come across both ways, through
-- sheet_xlsx_parts.lua.
--
-- This module puts the parts together: sheet_xml reads and escapes XML, sheet_xlsx_read reads
-- a file, and sheet_xlsx_write writes one. It hands their helpers to sheet_xlsx_parts.

local reader = require ('sheet_xlsx_read') --[[@as Sheet.XlsxReadModule]]
local writer = require ('sheet_xlsx_write') --[[@as Sheet.XlsxWriteModule]]
local xml_mod = require ('sheet_xml') --[[@as Sheet.XmlModule]]

-- The workbook shapes it reads and writes, Sheet.BookData and the types inside it, are
-- declared in sheet_book.lua.

---A relationship from one part of the file to another.
---@class Sheet.XlsxRel
---@field type string The last word of the relationship type, such as `worksheet`.
---@field target string The path of the part inside the zip.

---The zip's files, with a lower-case index, since part names ignore case.
---@class Sheet.XlsxSource
---@field files table<string, string>
---@field lower table<string, string>

---What every sheet of a workbook shares while it is read.
---@class Sheet.XlsxBook
---@field strings string[]
---@field rich table<integer, boolean> Shared strings with mixed formatting.
---@field xf_styles table<integer, Sheet.Style> Styles by `s` number, relative to style 0.
---@field xf_dates table<integer, boolean> Styles with a date format.
---@field date1904 boolean
---@field typed table<string, Sheet.XlsxTyped>
---@field dxfs Sheet.Style[] The styles of conditional formats.
---@field theme string[]

---A column range from a `<col>` element.
---@class Sheet.XlsxCol
---@field min integer
---@field max integer
---@field width? number Pixels, when it differs from the sheet's default.
---@field hidden boolean
---@field style? Sheet.Style

---A shared formula cell that waits for its master cell.
---@class Sheet.XlsxShared
---@field addr string
---@field row integer
---@field col integer
---@field si string
---@field value? string The cached value, used when the master is missing.

---The parts of a style that Excel keeps in separate lists, while a file is written.
---@class Sheet.XlsxStyleSheet
---@field fonts string[]
---@field font_ids table<string, integer>
---@field fills string[]
---@field fill_ids table<string, integer>
---@field borders string[]
---@field border_ids table<string, integer>
---@field formats string[]
---@field format_ids table<string, integer>
---@field xfs string[]
---@field xf_ids table<string, integer>
---@field dxfs string[] The styles of conditional formats, as XML.
---@field by_style table<string, integer> Style keys to `s` numbers.

---@class Sheet.XlsxStrings
---@field list string[]
---@field ids table<string, integer>
---@field uses integer How many cells use a shared string.

---What every sheet shares while a workbook is written.
---@class Sheet.XlsxWriter
---@field styles Sheet.XlsxStyleSheet
---@field strings Sheet.XlsxStrings
---@field values? Sheet.XlsxValues
---@field warnings string[]
---@field typed table<string, Sheet.XlsxTyped>
---@field spills? Sheet.XlsxSpills
---@field filtered? Sheet.XlsxFiltered
---@field dynamic? boolean True once a formula writes a spilled block, which needs the metadata part.
---@field seen table<string, boolean> Kinds of warnings already given.
---@field charts integer How many charts the sheets written so far hold.

---What typing a text stores, kept so that text which repeats is parsed once.
---@class Sheet.XlsxTyped
---@field value Sheet.Value
---@field code? string

---@alias Sheet.XlsxValues fun(sheet_index: integer, row: integer, col: integer): Sheet.Value

---The height and width of the block a formula cell spills, or nil when it spills none.
---@alias Sheet.XlsxSpills fun(sheet_index: integer, row: integer, col: integer): integer?, integer?

---The rows a sheet's filter hides, so the Excel file shows them hidden too.
---@alias Sheet.XlsxFiltered fun(sheet_index: integer): integer[]

---@class Sheet.XlsxModule
local M = {}
M.parse_xml = xml_mod.parse_xml
M.read = reader.read
M.write = writer.write

-- The helpers sheet_xlsx_parts uses, from the reader, the writer and the XML module.
local KIT = reader.KIT

KIT.child = xml_mod.child
KIT.children = xml_mod.children
KIT.bare = xml_mod.bare
KIT.prefixed = xml_mod.prefixed
KIT.flag = xml_mod.flag
KIT.int = xml_mod.int
KIT.attr = xml_mod.attr
KIT.text = xml_mod.cell_string
KIT.formula_text = xml_mod.formula_text
KIT.from_excel = reader.from_excel
KIT.to_excel = reader.to_excel
KIT.color_of = reader.color_of
KIT.argb = writer.argb
KIT.part_xml = reader.part_xml
KIT.resolve = reader.resolve
KIT.string_of = reader.string_of
KIT.number_text = reader.number_text
KIT.read_number = reader.read_number
KIT.format_id = writer.format_id_of
KIT.border_read = reader.BORDER_READ

return M
