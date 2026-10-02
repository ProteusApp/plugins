-- Numbers and colours as the canvas and the Preview show them.

local format = require ('shader_format') --[[@as Shader.FormatModule]]

test ('a number shows without the zeros at its end', function ()
  eq (format.fmt (2), '2')
  eq (format.fmt (-3), '-3')
  eq (format.fmt (0.25), '0.25')
  eq (format.fmt (1.5), '1.5')
  eq (format.fmt (0.123456), '0.1235')
  eq (format.fmt (0.123456, 3), '0.123')
  eq (format.fmt (0.0001, 3), '0')
end)

test ('a colour reads back the way it is written', function ()
  eq (format.to_hex ({ 1, 0.5, 0 }), '#ff8000')
  eq (format.to_hex ({ 2, -1 }), '#ff0000', 'out of range and missing parts')
  eq (format.from_hex ('#ff8000'), { 1, 0.502, 0 })
  eq (format.to_hex (assert (format.from_hex ('#12abef'))), '#12abef')
  eq (format.from_hex ('red'), nil)
  eq (format.from_hex ('#fff'), nil)
end)
