local F = require ('sheet_format') --[[@as Sheet.FormatModule]]
local formula = require ('sheet_formula') --[[@as Sheet.FormulaModule]]

-- Expected strings come from Excel. Where a case is not obvious, the comment names the source.
-- "SheetJS" means the Excel output recorded in the test data of the SheetJS SSF library.

---@param value Sheet.Value
---@param code? string
---@return string
local function show (value, code)
  local text = F.format (value, code)
  return text
end

---@param value Sheet.Value
---@param code? string
---@return string?
local function color (value, code)
  local _, c = F.format (value, code)
  return c
end

---@param text string
---@param clock? fun(): number
---@return table
local function parse (text, clock)
  local value, code = F.parse_input (text, clock)
  return { value, code }
end

-- A fixed clock, so dates typed without a year land in 2026 on every run.
---@return number
local function clock ()
  return F.serial (2026, 9, 29, 14, 30, 0)
end

local TUESDAY = 46294 -- 2026-09-29
local HALF_PAST_TWO = TUESDAY + (14 * 3600 + 30 * 60) / 86400

---------------------------------------------------------------------------------------------
-- General and the values that are not numbers
---------------------------------------------------------------------------------------------

test (
  'General shows up to 10 significant digits without float noise',
  function ()
    eq (show (1234.5), '1234.5')
    eq (show (0.1 + 0.2), '0.3')
    eq (show (0.1 + 0.2, 'General'), '0.3')
    eq (show (1 / 3), '0.3333333333')
    eq (show (-5, 'general'), '-5')
    eq (show (0), '0')
    eq (show (-0.0), '0')
    eq (show (1e20), '1E+20')
    eq (show (1e-7), '1E-07')
    eq (show (0 / 0, '0.00'), '#NUM!')
    eq (show (math.huge), '#NUM!')
  end
)

test ('TRUE, FALSE, errors and empty cells ignore the format', function ()
  eq (show (true, '0.00'), 'TRUE')
  eq (show (false), 'FALSE')
  eq (show (formula.error ('#DIV/0!'), '0.00'), '#DIV/0!')
  eq (show (nil, '0.00'), '')
  eq (show (nil), '')
end)

test ('text shows as it is unless the format has a text section', function ()
  eq (show ('abc', '0.00'), 'abc')
  eq (show ('abc'), 'abc')
  eq (show ('abc', '0;-0;0;"<"@">"'), '<abc>')
  eq (show ('ab', '@@'), 'abab')
  eq (show ('Ann', '"Name: "@'), 'Name: Ann')
  eq (show ('', '"x"@'), '')
  -- A number under a text-only format shows as General.
  eq (show (1234.5, '@'), '1234.5')
  eq (show (-1, '@'), '-1')
end)

---------------------------------------------------------------------------------------------
-- Digits
---------------------------------------------------------------------------------------------

test (
  '0 forces a digit, # shows one when needed and ? pads with a space',
  function ()
    eq (show (5, '000'), '005')
    eq (show (0, '#'), '')
    eq (show (0, '0'), '0')
    eq (show (0.5, '#.00'), '.50')
    eq (show (3.1, '0.##'), '3.1')
    -- Excel keeps the point when # hides every decimal (SheetJS).
    eq (show (1, '0.##'), '1.')
    eq (show (0, '#.##'), '.')
    eq (show (12.345, '0.0#'), '12.35')
    eq (show (0.0012345, '0.0#'), '0.0')
    eq (show (1.5, '??.??'), ' 1.5 ')
    eq (show (1.5, '0.0?'), '1.5 ')
    eq (show (12345, '000#0#0#0##00##00##0#########'), '0000000000012345')
  end
)

test ('numbers round half away from zero with no float noise', function ()
  eq (show (2.5, '0'), '3')
  eq (show (-2.5, '0'), '-3')
  eq (show (0.5, '0'), '1')
  eq (show (1234.5, '#,##0'), '1,235')
  eq (show (0.1 + 0.2, '0.00'), '0.30')
  eq (show (0.1 + 0.2, '0.00000000000000000'), '0.30000000000000000')
  eq (show (2.675, '0.00'), '2.68')
  eq (show (1.005, '0.00'), '1.01')
  eq (show (-1.008, '0.##'), '-1.01')
  -- Excel keeps 15 significant digits and shows zeros after them (SheetJS).
  eq (show (1e20, '0.00'), '100000000000000000000.00')
  eq (show (1234567890123456789, '0'), '1234567890123460000')
end)

test ('a number too wide for its format keeps all its digits', function ()
  eq (show (123456, '00'), '123456')
  eq (show (123456, '#'), '123456')
  eq (show (1234.5678, '0.0'), '1234.6')
end)

test ('literals sit between the digits they separate', function ()
  eq (show (123456789, '000-00-0000'), '123-45-6789')
  eq (show (2813308004, '(###) ###-####'), '(281) 330-8004')
  eq (show (941051630, '00000-0000'), '94105-1630')
  -- SheetJS: digits after the point fill the placeholders on both sides of a literal.
  eq (show (-3.14159, '"This is a ".00"test"000'), '-This is a 3.14test159')
  eq (show (101, '###\\###\\##0.00'), '#1#01.00')
end)

test ('a negative number that rounds to zero shows no minus sign', function ()
  -- Excel shows -0.00 here. The Sheet app drops the sign, as its TEXT function always has.
  eq (show (-0.001, '0.00'), '0.00')
  eq (show (-0.4, '0'), '0')
  eq (show (-0.00001, '0.00E+00'), '-1.00E-05')
end)

---------------------------------------------------------------------------------------------
-- Commas, percent and scientific notation
---------------------------------------------------------------------------------------------

test ('a comma between digits groups thousands', function ()
  eq (show (1234567, '#,##0'), '1,234,567')
  eq (show (1234.5, '#,##0.00'), '1,234.50')
  eq (show (5, '0,000'), '0,005')
  eq (show (12, '#,##0'), '12')
  eq (show (-1234567.891, '#,##0.00'), '-1,234,567.89')
end)

test ('a comma after the digits divides by 1000', function ()
  eq (show (12345678, '#,##0,'), '12,346')
  eq (show (12345678, '0.0,,'), '12.3')
  eq (show (1234, '#,##0.0,"K"'), '1.2K')
  -- SheetJS comma data.
  eq (show (1234, '#.0000,'), '1.2340')
  eq (show (12345, '00,000.00,'), '00,012.35')
  eq (show (1.2345, '** #,###,#00,000.00,**'), ' 00,000.00')
end)

test ('% multiplies by 100', function ()
  eq (show (0.256, '0%'), '26%')
  eq (show (0.256, '0.0%'), '25.6%')
  eq (show (-0.1234, '0.00%'), '-12.34%')
  eq (show (0.07, '0%'), '7%')
  eq (show (0.0005, '0%%'), '5%%')
end)

test ('E+ and E- give scientific notation', function ()
  eq (show (12345, '0.00E+00'), '1.23E+04')
  eq (show (0.00012345, '0.00E+00'), '1.23E-04')
  eq (show (0, '0.00E+00'), '0.00E+00')
  eq (show (-12345, '0.00E+00'), '-1.23E+04')
  eq (show (12345, '0.00E-00'), '1.23E04')
  eq (show (0.00012, '0.00E-00'), '1.20E-04')
  eq (show (1e100, '0.0E+0'), '1.0E+100')
  eq (show (9.999, '0.00E+00'), '1.00E+01')
  eq (show (12345, '0E+00'), '1E+04')
end)

test (
  'several integer placeholders before E make the exponent a multiple of their count',
  function ()
    -- SheetJS exponent data.
    eq (show (12345, '##0.0E+0'), '12.3E+3')
    eq (show (1234, '##0.0E+0'), '1.2E+3')
    eq (show (123, '##0.0E+0'), '123.0E+0')
    eq (show (0.000123457, '##0.0E+0'), '123.5E-6')
    eq (show (123456.789, '#0.0E+0'), '12.3E+4')
    eq (show (0.000123457, '####0.0E+0'), '12.3E-5')
  end
)

---------------------------------------------------------------------------------------------
-- Fractions
---------------------------------------------------------------------------------------------

test ('# ?/? shows a whole number and a fraction', function ()
  eq (show (1.25, '# ?/?'), '1 1/4')
  eq (show (0.5, '# ?/?'), ' 1/2')
  eq (show (-1.2, '# ?/?'), '-1 1/5')
  -- SheetJS: a whole number keeps the width of the fraction as spaces.
  eq (show (3, '# ?/?'), '3    ')
  eq (show (0, '# ?/?'), '0    ')
  eq (show (0.0123456789, '# ?/?'), '0    ')
  eq (show (123.45, '# ?/?'), '123 4/9')
  eq (show (-123.456, '# ?/?'), '-123 1/2')
end)

test (
  'fractions follow the steps of the continued fraction, as Excel does',
  function ()
    -- SheetJS: the float 0.3 is a hair below 3/10, so it lands on 2/7, and 12.3 is a hair
    -- above, so it lands on 1/3.
    eq (show (0.3, '# ?/?'), ' 2/7')
    eq (show (12.3, '# ?/?'), '12 1/3')
    eq (show (1.3, '# ?/?'), '1 1/3')
  end
)

test (
  '# ??/?? lines up the slash, and ?/? alone gives an improper fraction',
  function ()
    eq (show (-1.2, '# ??/??'), '-1  1/5 ')
    eq (show (12.3, '# ??/??'), '12  3/10')
    eq (show (-12.34, '# ??/??'), '-12 17/50')
    eq (show (1, '# ??/??'), '1      ')
    eq (show (-123.456, '# ???/???'), '-123  57/125')
    eq (show (12.3456789, '??/??'), '1000/81')
    eq (show (12.3456789, '# ??/??'), '12 28/81')
    eq (show (1.25, '?/?'), '5/4')
    eq (show (0.00001, '??/??'), ' 0/1 ')
    eq (show (1.25, '# ?? / ??'), '1  1 / 4 ')
  end
)

test ('# ?/8 uses a fixed denominator', function ()
  eq (show (12.3, '# ?/8'), '12 2/8')
  eq (show (-1.2, '# ??/16'), '-1  3/16')
  eq (show (12.3, '# ?/10'), '12 3/10')
  eq (show (1, '# ?/2'), '1    ')
  eq (show (-1.2, '# ?/2'), '-1    ')
  eq (show (1.99, '# ?/4'), '2    ')
end)

---------------------------------------------------------------------------------------------
-- Literals, spacing and fill
---------------------------------------------------------------------------------------------

test ('quotes, backslashes and some symbols show as they are', function ()
  eq (show (7, '0 "items"'), '7 items')
  eq (show (5, '0\\ \\k\\g'), '5 kg')
  eq (show (5, '$ (0) : +- '), '$ (5) : +- ')
  eq (show (1234.5, '#,##0.00 €'), '1,234.50 €')
  eq (show (-3.14159, '"-"0.00'), '--3.14')
  eq (show (-51968287, '"Rs."#,##0.00'), '-Rs.51,968,287.00')
  eq (show (0.7, '123'), '123')
end)

test ('[$sym-locale] shows its symbol', function ()
  eq (show (1234.5, '[$€-407] #,##0.00'), '€ 1,234.50')
  eq (show (3.14159, '[$INR]\\ #,##0.00'), 'INR 3.14')
  eq (show (-3.14159, '[$£-809]#,##0.0000;\\-[$£-809]#,##0.0000'), '-£3.1416')
  eq (show (12345, '[$-409]mmm\\-yy'), 'Oct-33')
  eq (show (5, '[DBNum1]0'), '5')
end)

test ('_x leaves a space and *x fills with nothing', function ()
  eq (show (5, '0_)'), '5 ')
  eq (show (5, '_(0_)'), ' 5 ')
  eq (show (5, '0_р'), '5 ')
  eq (show (5, '*-0'), '5')
  eq (show (5, '$* #,##0'), '$5')
end)

---------------------------------------------------------------------------------------------
-- Sections, colours and conditions
---------------------------------------------------------------------------------------------

test ('the second section is for negatives and drops the minus sign', function ()
  eq (show (5, '0.00;(0.00)'), '5.00')
  eq (show (-5, '0.00;(0.00)'), '(5.00)')
  eq (show (0, '0.00;(0.00)'), '0.00')
  eq (show (-1.1, '0;0'), '1')
  -- SheetJS: the section is picked before rounding.
  eq (show (-0.1, '"$"#,##0_);\\("$"#,##0\\);"-"'), '($0)')
  eq (show (0.1, '"$"#,##0_);\\("$"#,##0\\);"-"'), '$0 ')
  -- A single section puts the minus sign before everything, even a literal.
  eq (show (-12345.6789, '(#,##0.00)'), '-(12,345.68)')
end)

test ('the third section is for zero and the fourth for text', function ()
  eq (show (0, '0;-0;"zero"'), 'zero')
  eq (show (-3, '0;-0;"zero"'), '-3')
  eq (show ('hi', '0;-0;"zero";"text: "@'), 'text: hi')
  eq (show (1, '"foo";"bar";"baz";"qux"'), 'foo')
  eq (show (-1, '"foo";"bar";"baz";"qux"'), 'bar')
  eq (show ('x', '"foo";"bar";"baz";"qux"'), 'qux')
  -- SheetJS: with a text section last, zero uses the first section.
  eq (show (0, '"foo";"bar";@'), 'foo')
  eq (show ('x', '"foo";"bar";@'), 'x')
end)

test (
  'empty sections hide values, and a section with no digits shows no minus sign',
  function ()
    eq (show (5, ';;;'), '')
    eq (show (-5, ';;;'), '')
    eq (show ('x', ';;;'), '')
    eq (show (-5, '"none"'), 'none')
    eq (show (-1, 'A"TODO"'), 'ATODO')
  end
)

test ('General can sit inside a section and keeps its own sign', function ()
  local code = "General ;General\\ ;Generalp;General'"
  eq (show (50, code), '50 ')
  eq (show (0, code), '0p')
  -- SheetJS: General in the negative section still shows the minus sign.
  eq (show (-25, code), '-25 ')
  eq (show ('foo', code), "foo'")
  eq (show (5, '"Qty: "General'), 'Qty: 5')
end)

test ('a colour in a section comes back as a CSS colour', function ()
  eq (color (5, '[Red]0'), '#e03e3e')
  eq (color (5, '0;[Red]-0'), nil)
  eq (show (-5, '0;[Red]-0'), '-5')
  eq (color (-5, '0;[Red]-0'), '#e03e3e')
  eq (color (5, '[BLUE]0'), '#3d7fe0')
  eq (color (5, '[Color3]0'), '#e03e3e')
  eq (color ('x', '0;0;0;[Magenta]@'), '#c940c9')
  eq (color ('x', '[Red]0'), nil)
  eq (color (5, '[Color40]0'), nil)
end)

---@param hex string
---@return number
local function luminance (hex)
  local weights = { 0.2126, 0.7152, 0.0722 }
  local total = 0
  for k = 1, 3 do
    local c = (tonumber (string.sub (hex, 2 * k, 2 * k + 1), 16) or 0) / 255
    local linear = c <= 0.03928 and c / 12.92 or ((c + 0.055) / 1.055) ^ 2.4
    total = total + weights[k] * linear
  end
  return total
end

---@param a string
---@param b string
---@return number
local function contrast (a, b)
  local x, y = luminance (a), luminance (b)
  return (math.max (x, y) + 0.05) / (math.min (x, y) + 0.05)
end

test ('every colour reads on a light and on a dark background', function ()
  local names =
    { 'Black', 'White', 'Red', 'Green', 'Blue', 'Yellow', 'Magenta', 'Cyan' }
  for _, name in ipairs (names) do
    local c = color (1, '[' .. name .. ']0') --[[@as string]]
    ok (string.match (c, '^#%x%x%x%x%x%x$'), name)
    ok (contrast (c, '#ffffff') >= 3, name .. ' on white')
    ok (contrast (c, '#1b1d23') >= 3, name .. ' on the dark theme')
  end
end)

test ('a condition picks the section', function ()
  eq (show (150, '[>=100]"big";"small"'), 'big')
  eq (show (50, '[>=100]"big";"small"'), 'small')
  -- SheetJS.
  eq (show (8675309, '[<=9999999]###-####;(###) ###-####'), '867-5309')
  eq (show (2813308004, '[<=9999999]###-####;(###) ###-####'), '(281) 330-8004')
  eq (show (50, '[Red][=50]General;[Blue]000'), '50')
  eq (show (51, '[Red][=50]General;[Blue]000'), '051')
  eq (show (50, '[Red][<>50]General;[Blue]000'), '050')
  eq (color (51, '[Red][=50]General;[Blue]000'), '#3d7fe0')
end)

test ('with two conditions, the third section takes the rest', function ()
  local code = '[<1000]0;[<1000000]0.0,"K";0.0,,"M"'
  eq (show (500, code), '500')
  eq (show (12345, code), '12.3K')
  eq (show (1234567, code), '1.2M')
  eq (show (-5, code), '-5')
  eq (show (-1, '[Red][<-25]General;[Blue][>25]General;[Green]General'), '-1')
  eq (
    color (-1, '[Red][<-25]General;[Blue][>25]General;[Green]General'),
    '#2b9348'
  )
end)

test (
  'a section whose condition lets only negatives in drops the minus sign',
  function ()
    eq (show (-5, '[<0](0);0'), '(5)')
    eq (show (5, '[<0](0);0'), '5')
    eq (show (-150, '[>=100]0;[<=-100](0);0'), '(150)')
    eq (show (-50, '[>=100]0;[<=-100](0);0'), '-50')
  end
)

test ('a malformed code shows as General and never raises', function ()
  eq (show (5, '"open'), '5')
  eq (show (5, '[Red'), '5')
  eq (show (-5, '0;0;0;0;0'), '-5')
  eq (show (5, '0\\'), '5')
  eq (show (5, '0_'), '5')
  eq (show (5, '[>abc]0'), '5')
  eq (show ('x', '"open'), 'x')
  eq (show (1.5, '0.00;'), '1.50')
end)

---------------------------------------------------------------------------------------------
-- Dates and times
---------------------------------------------------------------------------------------------

test ('year, month and day codes', function ()
  eq (show (TUESDAY, 'yyyy-mm-dd'), '2026-09-29')
  eq (show (TUESDAY, 'yy'), '26')
  eq (show (TUESDAY, 'y'), '26')
  eq (show (TUESDAY, 'yyy'), '2026')
  eq (show (TUESDAY, 'e'), '2026')
  eq (show (TUESDAY, 'm/d/yyyy'), '9/29/2026')
  eq (show (TUESDAY, 'mm/dd/yyyy'), '09/29/2026')
  eq (show (TUESDAY, 'mmm'), 'Sep')
  eq (show (TUESDAY, 'mmmm'), 'September')
  eq (show (TUESDAY, 'mmmmm'), 'S')
  eq (show (TUESDAY, 'ddd'), 'Tue')
  eq (show (TUESDAY, 'dddd'), 'Tuesday')
  eq (show (TUESDAY, 'DD/MM/YYYY'), '29/09/2026')
  local day = F.serial (2026, 3, 7, 9, 5, 30)
  eq (show (day, 'd'), '7')
  eq (show (day, 'dd'), '07')
  eq (show (day, 'm'), '3')
  eq (show (day, 'dddd, mmmm d'), 'Saturday, March 7')
  eq (show (day, 'yyyy-mm-dd "at" hh:mm'), '2026-03-07 at 09:05')
end)

test (
  'hour, minute and second codes, where m after h or before s means minutes',
  function ()
    local day = F.serial (2026, 3, 7, 9, 5, 30)
    eq (show (day, 'hh:mm:ss'), '09:05:30')
    eq (show (day, 'h:mm'), '9:05')
    eq (show (day, 'mm:ss'), '05:30')
    eq (show (day, 'h'), '9')
    eq (show (day, 's'), '30')
    eq (show (day, 'mm'), '03')
    eq (show (day, 'hh"h"mm'), '09h05')
    -- SheetJS time data: 0.1 of a day is 2:24.
    eq (show (0.1, 'hm'), '224')
  end
)

test ('AM/PM and A/P show a twelve-hour clock', function ()
  eq (show (HALF_PAST_TWO, 'h:mm AM/PM'), '2:30 PM')
  eq (show (HALF_PAST_TWO, 'hh:mm am/pm'), '02:30 PM')
  eq (show (HALF_PAST_TWO, 'h A/P'), '2 P')
  eq (show (HALF_PAST_TWO, 'h a/p'), '2 p')
  eq (show (0, 'h:mm AM/PM'), '12:00 AM')
  eq (show (0.5, 'hh:mm:ss AM/PM'), '12:00:00 PM')
  eq (show (0.7, 'hh:mm AM/PM'), '04:48 PM')
  -- SheetJS: AM/P is not AM/PM, so the A shows as itself and the M is a month.
  eq (show (0.5, 'hh:mm:ss AM/P'), '12:00:00 A1/P')
end)

test ('.0 to .000 show decimals of a second', function ()
  -- SheetJS.
  eq (show (0.70707, 'hh:mm:ss.000'), '16:58:10.848')
  eq (show (0.70707, 'hh .00'), '16 .85')
  eq (show (0.123456789, 'mmss.0'), '5746.7')
  eq (show (0.00001, 'ss.00'), '00.86')
end)

test (
  'time rounds to the shown precision before it splits into parts',
  function ()
    local late = F.serial (2026, 9, 29, 10, 30, 59.9999)
    eq (show (late, 'h:mm:ss'), '10:31:00')
    eq (show (late, 'ss'), '00')
    eq (show (late, 'ss.00'), '00.00')
    eq (show (F.serial (2026, 9, 29, 10, 30, 59.9994), 'ss.000'), '59.999')
    -- Minutes do not round up when seconds are hidden, as in Excel.
    eq (show (F.serial (2026, 9, 29, 10, 30, 59), 'h:mm'), '10:30')
    eq (show (TUESDAY + 0.99999999, 'm/d/yyyy'), '9/30/2026')
    eq (show (0.00001, 's'), '1')
  end
)

test ('[h], [mm] and [ss] show elapsed time', function ()
  eq (show (1.5, '[h]:mm:ss'), '36:00:00')
  eq (show (1 / 24, '[mm]:ss'), '60:00')
  eq (show (1 / 1440, '[ss]'), '60')
  eq (show (0.1, '[hh]'), '02')
  -- SheetJS: 2.9999999999999996 rounds to 72 hours.
  eq (show (2.9999999999999996, '[h]:mm:ss;@'), '72:00:00')
  eq (show (-1.5, '[h]:mm'), '-36:00')
  eq (show (-1.5, '[h]:mm;[Red]-[h]:mm'), '-36:00')
  eq (show (-0.25, 'h:mm'), '-6:00')
end)

test ('dates near month ends and in leap years', function ()
  local iso = 'yyyy-mm-dd'
  eq (show (F.serial (2026, 1, 31) + 1, iso), '2026-02-01')
  eq (show (F.serial (2026, 4, 30) + 1, iso), '2026-05-01')
  eq (show (F.serial (2026, 12, 31) + 1, iso), '2027-01-01')
  eq (show (F.serial (2024, 2, 28) + 1, iso), '2024-02-29')
  eq (show (F.serial (2024, 2, 29) + 1, iso), '2024-03-01')
  eq (show (F.serial (2026, 2, 28) + 1, iso), '2026-03-01')
  eq (show (F.serial (2000, 2, 28) + 1, iso), '2000-02-29')
  eq (show (F.serial (2100, 2, 28) + 1, iso), '2100-03-01')
  eq (show (F.serial (9999, 12, 31), iso), '9999-12-31')
end)

test ('1900 has a 29 February, as in Excel', function ()
  local iso = 'yyyy-mm-dd'
  eq (show (1, iso), '1900-01-01')
  eq (show (59, iso), '1900-02-28')
  eq (show (60, iso), '1900-02-29')
  eq (show (61, iso), '1900-03-01')
  eq (show (0, iso), '1900-01-00')
  -- SheetJS date data: weekdays follow the serial, so Excel's 1900-01-01 is a Sunday.
  eq (show (60, 'dddd'), 'Wednesday')
  eq (show (1, 'dddd'), 'Sunday')
  eq (show (0, 'ddd'), 'Sat')
  eq (show (0.5, 'm/d/yy h:mm'), '1/0/00 12:00')
end)

test ('dates before 1900 and past 9999', function ()
  -- Excel shows #### here. The Sheet app shows the date, as other spreadsheets do.
  eq (show (-1, 'yyyy-mm-dd'), '1899-12-30')
  -- 36524 days before 1900-01-01, one more for the day Excel adds in 1900.
  eq (F.serial (1800, 1, 1), -36523)
  eq (show (-36523, 'yyyy-mm-dd'), '1800-01-01')
  eq (show (F.serial (10000, 1, 1), 'yyyy-mm-dd'), '2958466')
  eq (show (1e12, 'h:mm'), '1E+12')
end)

---------------------------------------------------------------------------------------------
-- The presets
---------------------------------------------------------------------------------------------

---@type table<string, { [1]: number, [2]: number, [3]: string, [4]: string, [5]: string, [6]: string }>
local PRESET_CASES = {
  general = { 1234.5, -1234.5, '1234.5', '-1234.5', '0', 'abc' },
  text = { 1234.5, -1234.5, '1234.5', '-1234.5', '0', 'abc' },
  number = { 1234.5, -1234.5, '1,234.50', '-1,234.50', '0.00', 'abc' },
  percent = { 0.256, -0.256, '25.60%', '-25.60%', '0.00%', 'abc' },
  scientific = { 1234.5, -1234.5, '1.23E+03', '-1.23E+03', '0.00E+00', 'abc' },
  -- SheetJS shows this code's zero as " $- " with no decimals, so two decimals give
  -- two more spaces.
  accounting = {
    1234.5,
    -1234.5,
    ' $1,234.50 ',
    ' $(1,234.50)',
    ' $-   ',
    ' abc ',
  },
  financial = { 1234.5, -1234.5, '1,234.50', '(1,234.50)', '0.00', 'abc' },
  currency = { 1234.5, -1234.5, '$1,234.50', '-$1,234.50', '$0.00', 'abc' },
  currency_rounded = { 1234.5, -1234.5, '$1,235', '-$1,235', '$0', 'abc' },
  date = { HALF_PAST_TWO, -1, '9/29/2026', '12/30/1899', '1/0/1900', 'abc' },
  long_date = {
    HALF_PAST_TWO,
    -1,
    'Tuesday, September 29, 2026',
    'Friday, December 30, 1899',
    'Saturday, January 0, 1900',
    'abc',
  },
  time = {
    HALF_PAST_TWO,
    -0.25,
    '2:30:00 PM',
    '-6:00:00 AM',
    '12:00:00 AM',
    'abc',
  },
  datetime = {
    HALF_PAST_TWO,
    -1,
    '9/29/2026 14:30:00',
    '12/30/1899 0:00:00',
    '1/0/1900 0:00:00',
    'abc',
  },
  duration = { 1.5, -1.5, '36:00:00', '-36:00:00', '0:00:00', 'abc' },
}

test (
  'every preset shows a positive, a negative, a zero and a text value',
  function ()
    eq (#F.presets, 14)
    for _, preset in ipairs (F.presets) do
      local case = PRESET_CASES[preset.id]
      ok (case, preset.id)
      ok (preset.label ~= '', preset.id)
      eq (show (case[1], preset.code), case[3], preset.id .. ' positive')
      eq (show (case[2], preset.code), case[4], preset.id .. ' negative')
      eq (show (0, preset.code), case[5], preset.id .. ' zero')
      eq (show ('abc', preset.code), case[6], preset.id .. ' text')
    end
  end
)

test ('the presets have the codes the format menu expects', function ()
  local codes = {} ---@type table<string, string>
  for _, preset in ipairs (F.presets) do
    codes[preset.id] = preset.code
  end
  eq (codes.general, 'General')
  eq (codes.text, '@')
  eq (codes.accounting, '_($* #,##0.00_);_($* (#,##0.00);_($* "-"??_);_(@_)')
  eq (codes.duration, '[h]:mm:ss')
end)

---------------------------------------------------------------------------------------------
-- Typed text
---------------------------------------------------------------------------------------------

test (
  'typed numbers store numbers, with a format when the typing implies one',
  function ()
    eq (parse ('1234'), { 1234 })
    eq (parse ('-5'), { -5 })
    eq (parse ('1.5'), { 1.5 })
    eq (parse ('.5'), { 0.5 })
    eq (parse ('+7'), { 7 })
    eq (parse ('  42  '), { 42 })
    eq (parse ('(123)'), { -123 })
    eq (parse ('1,234.56'), { 1234.56, '#,##0.00' })
    eq (parse ('1,234'), { 1234, '#,##0' })
    eq (parse ('-1,234,567'), { -1234567, '#,##0' })
    eq (parse ('1.5E3'), { 1500, '0.00E+00' })
    eq (parse ('2e-3'), { 0.002, '0.00E+00' })
    eq (parse ('-0'), { 0 })
    ok (math.type (F.parse_input ('1234')) == 'float', 'numbers are floats')
  end
)

test ('typed currency and percent', function ()
  eq (parse ('$1,200'), { 1200, '$#,##0' })
  eq (parse ('$5.50'), { 5.5, '$#,##0.00' })
  eq (parse ('-$5.50'), { -5.5, '$#,##0.00' })
  eq (parse ('$-5.50'), { -5.5, '$#,##0.00' })
  eq (parse ('($5)'), { -5, '$#,##0' })
  eq (parse ('15%'), { 0.15, '0%' })
  eq (parse ('12.5%'), { 0.125, '0.0%' })
  eq (parse ('-3%'), { -0.03, '0%' })
  eq (parse ('0.1%'), { 0.001, '0.0%' })
end)

test (
  'typed dates store serials with a format that looks like the typing',
  function ()
    eq (parse ('2026-09-29'), { TUESDAY, 'yyyy-mm-dd' })
    eq (parse ('2026/9/29'), { TUESDAY, 'yyyy/m/d' })
    eq (parse ('9/29/2026'), { TUESDAY, 'm/d/yyyy' })
    eq (parse ('09/29/2026'), { TUESDAY, 'mm/dd/yyyy' })
    eq (parse ('12/5/2026'), { F.serial (2026, 12, 5), 'm/d/yyyy' })
    eq (parse ('9/29/26'), { TUESDAY, 'm/d/yy' })
    eq (parse ('9-29-2026'), { TUESDAY, 'm-d-yyyy' })
    eq (parse ('29-Sep-2026'), { TUESDAY, 'd-mmm-yyyy' })
    eq (parse ('29 Sep 2026'), { TUESDAY, 'd mmm yyyy' })
    eq (parse ('29 september 2026'), { TUESDAY, 'd mmmm yyyy' })
    eq (parse ('Sep 29, 2026'), { TUESDAY, 'mmm d, yyyy' })
    eq (parse ('September 29 2026'), { TUESDAY, 'mmmm d yyyy' })
    eq (parse ('Sept 29, 2026'), { TUESDAY, 'mmm d, yyyy' })
    eq (parse ('Sep 2026'), { F.serial (2026, 9, 1), 'mmm yyyy' })
    -- Two-digit years run from 1930 to 2029, as in Excel.
    eq (parse ('1/1/29'), { F.serial (2029, 1, 1), 'm/d/yy' })
    eq (parse ('1/1/30'), { F.serial (1930, 1, 1), 'm/d/yy' })
  end
)

test ('a date typed without a year lands in the year of the clock', function ()
  eq (parse ('9/29', clock), { TUESDAY, 'm/d' })
  eq (parse ('29-Sep', clock), { TUESDAY, 'd-mmm' })
  eq (parse ('Sep 29', clock), { TUESDAY, 'mmm d' })
  ---@return number
  local function later ()
    return F.serial (2031, 1, 1)
  end
  eq (parse ('9/29', later), { F.serial (2031, 9, 29), 'm/d' })
  eq (parse ('2/29', later), { '2/29' })
  local value = F.parse_input ('9/29')
  ok (type (value) == 'number', 'the real clock gives a date too')
end)

test ('typed times store fractions of a day', function ()
  local function at (h, mi, s)
    return (h * 3600 + mi * 60 + s) / 86400
  end
  eq (parse ('14:30'), { at (14, 30, 0), 'h:mm' })
  eq (parse ('09:05'), { at (9, 5, 0), 'hh:mm' })
  eq (parse ('14:30:15'), { at (14, 30, 15), 'h:mm:ss' })
  eq (parse ('2:30 PM'), { at (14, 30, 0), 'h:mm AM/PM' })
  eq (parse ('2:30:15 am'), { at (2, 30, 15), 'h:mm:ss AM/PM' })
  eq (parse ('2 pm'), { at (14, 0, 0), 'h AM/PM' })
  eq (parse ('2pm'), { at (14, 0, 0), 'h AM/PM' })
  eq (parse ('12 am'), { 0, 'h AM/PM' })
  eq (parse ('12:15 pm'), { at (12, 15, 0), 'h:mm AM/PM' })
  eq (parse ('36:00'), { 1.5, '[h]:mm' })
  eq (parse ('14:30:15.5'), { at (14, 30, 15.5), 'h:mm:ss.0' })
  eq (parse ('1:15.25'), { at (0, 1, 15.25), 'mm:ss.00' })
end)

test ('a date followed by a time', function ()
  eq (parse ('2026-09-29 14:30'), { HALF_PAST_TWO, 'yyyy-mm-dd h:mm' })
  eq (parse ('9/29/2026 2:30 PM'), { HALF_PAST_TWO, 'm/d/yyyy h:mm AM/PM' })
  eq (
    parse ('Sep 29, 2026 2:30 pm'),
    { HALF_PAST_TWO, 'mmm d, yyyy h:mm AM/PM' }
  )
  eq (parse ('2026-09-29T14:30'), { HALF_PAST_TWO, 'yyyy-mm-dd h:mm' })
end)

test ('TRUE and FALSE in any case store booleans', function ()
  eq (parse ('TRUE'), { true })
  eq (parse ('true'), { true })
  eq (parse ('False'), { false })
end)

test ('a leading quote keeps the rest as text', function ()
  eq (parse ("'123"), { '123' })
  eq (parse ("'2026-09-29"), { '2026-09-29' })
  eq (parse ("'"), { '' })
  eq (parse ("'  x"), { '  x' })
end)

test (
  'a whole number and a fraction store a number with a fraction format',
  function ()
    eq (parse ('1 1/2'), { 1.5, '# ?/?' })
    eq (parse ('-2 3/16'), { -2.1875, '# ??/??' })
    eq (parse ('0 1/2'), { 0.5, '# ?/?' })
  end
)

test ('anything else stays text', function ()
  local texts = {
    'abc',
    'Hello world',
    '1,23',
    '1.2.3',
    '12abc',
    '0x10',
    'inf',
    'nan',
    '$',
    '-',
    '%',
    '$5%',
    '1e',
    '(-5)',
    '1 3/2',
    '14:60',
    '25:00 PM',
    '13 pm',
    'Apt 12',
    '=A1',
    ' ',
  }
  for _, text in ipairs (texts) do
    eq (parse (text), { text }, text)
  end
  eq (parse (''), {})
end)

test ('impossible dates stay text', function ()
  local texts = {
    '2/30/2026',
    '2/29/2026',
    '2/29/2100',
    '13/1/2026',
    '0/5/2026',
    '4/31/2026',
    '1/1/1899',
    '2026-02-30',
    '2026-13-01',
    'Sep 31, 2026',
    '31-Nov-2026',
    '9/29/202',
  }
  for _, text in ipairs (texts) do
    eq (parse (text), { text }, text)
  end
  eq (parse ('2/29/2024'), { F.serial (2024, 2, 29), 'm/d/yyyy' })
  eq (parse ('2/29/2000'), { F.serial (2000, 2, 29), 'm/d/yyyy' })
  -- Excel takes 29 February 1900, which is serial 60.
  eq (parse ('2/29/1900'), { 60, 'm/d/yyyy' })
end)

test ('typing and DATEVALUE read the same dates', function ()
  local ctx = {
    rows = 10,
    cols = 10,
    clock = clock,
    value = function ()
      return nil
    end,
  } ---@type Sheet.Context
  ---@param text string
  ---@return Sheet.Value
  local function datevalue (text)
    local ast = assert (formula.parse ('=DATEVALUE("' .. text .. '")'))
    return formula.evaluate (ast, ctx)
  end
  local cases = {
    { '9/2026', F.serial (2026, 9, 1) },
    { '2026.09.29', TUESDAY },
    { '2026-09-29', TUESDAY },
    { '9/29/26', TUESDAY },
    { '29 Sept. 2026', TUESDAY },
    { '29-sep 2026', TUESDAY },
    { 'Sep. 29, 2026', TUESDAY },
    { 'sep 2026', F.serial (2026, 9, 1) },
    { '9/29', TUESDAY },
    { '29-Sep', TUESDAY },
    { '2/29/1900', 60 },
    -- Neither reads a year of three digits, nor one before 1900.
    { '1/2/123', nil },
    { '1/2/1899', nil },
    { '2/30/2026', nil },
    { 'Sep 292026', nil },
  }
  for _, case in ipairs (cases) do
    local text, want = case[1], case[2]
    local typed = F.parse_input (text, clock)
    if want then
      eq (typed, want, 'typed ' .. text)
      eq (datevalue (text), want, 'DATEVALUE of ' .. text)
    else
      eq (typed, text, 'typed ' .. text .. ' stays text')
      eq (datevalue (text), formula.error ('#VALUE!'), 'DATEVALUE of ' .. text)
    end
  end
  -- A dotted date shows with dashes, since a point in a format code is a decimal point.
  eq (parse ('2026.09.29'), { TUESDAY, 'yyyy-mm-dd' })
  eq (parse ('9/2026'), { F.serial (2026, 9, 1), 'm/yyyy' })
  eq (parse ('9 a.m.'), { 9 / 24, 'h AM/PM' })
  eq (
    parse ('2:30:15.5 pm'),
    { (14.5 * 3600 + 15.5) / 86400, 'h:mm:ss.0 AM/PM' }
  )
  eq (
    parse ('Sep 29, 2026, 2:30 PM'),
    { HALF_PAST_TWO, 'mmm d, yyyy h:mm AM/PM' }
  )
end)

test ('what parse_input stores shows the way it was typed', function ()
  local typed = {
    '1,234.56',
    '$1,200',
    '-$5.50',
    '15%',
    '12.5%',
    '2026-09-29',
    '9/29/2026',
    '29-Sep-2026',
    'Sep 29, 2026',
    '14:30',
    '2:30 PM',
    '2026-09-29 14:30',
    '1 1/2',
  }
  for _, text in ipairs (typed) do
    local value, code = F.parse_input (text)
    eq (show (value, code), text, text)
  end
end)

---------------------------------------------------------------------------------------------
-- Decimal places, kinds and alignment
---------------------------------------------------------------------------------------------

test (
  'adjust_decimals adds and removes a decimal place in every number section',
  function ()
    eq (F.adjust_decimals ('0.00', 1), '0.000')
    eq (F.adjust_decimals ('0.00', -1), '0.0')
    eq (F.adjust_decimals ('0.0', -1), '0')
    eq (F.adjust_decimals ('0', -1), '0')
    eq (F.adjust_decimals ('0', 1), '0.0')
    eq (F.adjust_decimals ('#,##0', 1), '#,##0.0')
    eq (F.adjust_decimals ('0%', 1), '0.0%')
    eq (F.adjust_decimals ('0.00%', -2), '0%')
    eq (F.adjust_decimals ('0.00E+00', -1), '0.0E+00')
    eq (F.adjust_decimals ('0E+00', -1), '0E+00')
    eq (F.adjust_decimals ('#,##0,"K"', 1), '#,##0.0,"K"')
    eq (F.adjust_decimals ('0 "0"', 1), '0.0 "0"')
    eq (
      F.adjust_decimals ('$#,##0.00;[Red]($#,##0.00)', 1),
      '$#,##0.000;[Red]($#,##0.000)'
    )
  end
)

test (
  'adjust_decimals on Accounting changes the question marks of its zero section',
  function ()
    local accounting = '_($* #,##0.00_);_($* (#,##0.00);_($* "-"??_);_(@_)'
    eq (
      F.adjust_decimals (accounting, 1),
      '_($* #,##0.000_);_($* (#,##0.000);_($* "-"???_);_(@_)'
    )
    -- SheetJS lists this as Excel's Accounting format with no decimals.
    eq (
      F.adjust_decimals (accounting, -2),
      '_($* #,##0_);_($* (#,##0);_($* "-"_);_(@_)'
    )
  end
)

test (
  'adjust_decimals from General starts from the decimals the value shows',
  function ()
    eq (F.adjust_decimals (nil, 1, 3.14159), '0.000000')
    eq (F.adjust_decimals (nil, -1, 3.14159), '0.0000')
    eq (F.adjust_decimals ('General', 1, 1234), '0.0')
    eq (F.adjust_decimals ('General', -1, 1234), '0')
    eq (F.adjust_decimals (nil, 1, 'abc'), '0.0')
    eq (F.adjust_decimals (nil, 1), '0.0')
    eq (F.adjust_decimals (nil, 1, -2.5), '0.00')
    eq (F.adjust_decimals (nil, 1, 1e-7), '0.0E+00')
    eq (F.adjust_decimals ('"open', 1, 2.5), '0.00')
  end
)

test (
  'adjust_decimals leaves dates, times, fractions and text alone',
  function ()
    for _, code in ipairs ({ 'm/d/yyyy', '[h]:mm:ss', 'h:mm:ss.0', '@', '# ?/?' }) do
      eq (F.adjust_decimals (code, 1), code)
      eq (F.adjust_decimals (code, -1), code)
    end
  end
)

test ('kind says what a code shows', function ()
  local kinds = {
    general = 'general',
    text = 'text',
    number = 'number',
    percent = 'percent',
    scientific = 'scientific',
    accounting = 'accounting',
    financial = 'number',
    currency = 'currency',
    currency_rounded = 'currency',
    date = 'date',
    long_date = 'date',
    time = 'time',
    datetime = 'datetime',
    duration = 'duration',
  }
  for _, preset in ipairs (F.presets) do
    eq (F.kind (preset.code), kinds[preset.id], preset.id)
  end
  eq (F.kind (nil), 'general')
  eq (F.kind ('# ?/?'), 'fraction')
  eq (F.kind ('"x"@'), 'text')
  eq (F.kind ('h:mm'), 'time')
  eq (F.kind ('mm:ss.0'), 'time')
  eq (F.kind ('yyyy-mm-dd hh:mm'), 'datetime')
  eq (F.kind ('[$€-407] #,##0.00'), 'currency')
  eq (F.kind ('#,##0.00 €'), 'currency')
  eq (F.kind ('[Blue]General'), 'general')
  eq (F.kind ('"open'), 'general')
end)

test (
  'align puts numbers right, text left, and TRUE, FALSE and errors in the centre',
  function ()
    eq (F.align (5), 'right')
    eq (F.align (TUESDAY, 'm/d/yyyy'), 'right')
    eq (F.align ('abc'), 'left')
    eq (F.align (nil), 'left')
    eq (F.align (true), 'center')
    eq (F.align (formula.error ('#N/A')), 'center')
    eq (F.align (5, '@'), 'left')
    eq (F.align (true, '@'), 'left')
  end
)

---------------------------------------------------------------------------------------------
-- Serial dates
---------------------------------------------------------------------------------------------

test (
  'serial counts days from 1899-12-30 with Excel 29 February 1900',
  function ()
    eq (F.serial (2026, 9, 29), TUESDAY)
    eq (F.serial (2026, 9, 29, 12), TUESDAY + 0.5)
    eq (F.serial (1900, 1, 1), 1)
    eq (F.serial (1900, 2, 28), 59)
    eq (F.serial (1900, 2, 29), 60)
    eq (F.serial (1900, 3, 1), 61)
    eq (F.serial (1900, 3, 0), 60)
    eq (F.serial (1900, 1, 0), 0)
    eq (F.serial (1899, 12, 31), 0)
    eq (F.serial (2026, 13, 1), F.serial (2027, 1, 1))
    eq (F.serial (2026, 2, 30), F.serial (2026, 3, 2))
    eq (F.serial (2026, 0, 1), F.serial (2025, 12, 1))
  end
)

test (
  'date_parts splits a serial and gives the weekday from 1 for Sunday',
  function ()
    eq ({ F.date_parts (TUESDAY + 0.5) }, { 2026, 9, 29, 12, 0, 0, 3 })
    eq ({ F.date_parts (60) }, { 1900, 2, 29, 0, 0, 0, 4 })
    eq ({ F.date_parts (61) }, { 1900, 3, 1, 0, 0, 0, 5 })
    eq ({ F.date_parts (0) }, { 1900, 1, 0, 0, 0, 0, 7 })
    eq ({ F.date_parts (1) }, { 1900, 1, 1, 0, 0, 0, 1 })
    eq ({ F.date_parts (-1) }, { 1899, 12, 30, 0, 0, 0, 6 })
    eq ({ F.date_parts (TUESDAY + 59.6 / 86400) }, { 2026, 9, 29, 0, 1, 0, 3 })
    eq ({ F.date_parts (TUESDAY + 0.99999999) }, { 2026, 9, 30, 0, 0, 0, 4 })
    for _, day in ipairs ({ 1, 59, 60, 61, 366, TUESDAY, 2958465 }) do
      local y, m, d = F.date_parts (day)
      eq (F.serial (y, m, d), day, 'round trip ' .. day)
    end
  end
)

---------------------------------------------------------------------------------------------
-- The TEXT function
---------------------------------------------------------------------------------------------

test ('format gives what the TEXT function shows today', function ()
  eq (show (1234.567, '0'), '1235')
  eq (show (1234.567, '0.00'), '1234.57')
  eq (show (1234.567, '#,##0'), '1,235')
  eq (show (1234567.891, '#,##0.00'), '1,234,567.89')
  eq (show (0.256, '0%'), '26%')
  eq (show (0.256, '0.0%'), '25.6%')
  eq (show (-1234.5, '#,##0.00'), '-1,234.50')
  eq (show (42, '$#,##0'), '$42')
  eq (show (-42, '$0'), '-$42')
  eq (show (0, '0.0'), '0.0')
  local day = F.serial (2026, 3, 7, 9, 5, 30)
  eq (show (day, 'dd/mm/yy'), '07/03/26')
  eq (show (day, 'd mmm yyyy'), '7 Mar 2026')
  eq (show (HALF_PAST_TWO, 'dd mmm yyyy'), '29 Sep 2026')
  eq (show (HALF_PAST_TWO, 'hh:mm'), '14:30')
end)
