-- Tests for sheet_xml: reading XML into a tree, finding children and attributes whatever
-- prefix a file gives them, and the text the writer puts in elements and attributes.

local xlsx = require ('sheet_xlsx') --[[@as Sheet.XlsxModule]]
local xml = require ('sheet_xml') --[[@as Sheet.XmlModule]]

test ('sheet_xlsx reads XML through this module', function ()
  ok (xlsx.parse_xml == xml.parse_xml)
end)

test ('a document reads into a tree, with entities decoded', function ()
  local root = assert (
    xml.parse_xml (
      '\239\187\191<?xml version="1.0"?>\r\n<x:a n="1 &amp; 2"><b>A &lt; B &#65;&#x42;</b><b/></x:a>'
    )
  )
  eq (root.name, 'x:a')
  eq (root.attrs.n, '1 & 2')
  eq (#root.children, 2)
  eq (root.children[1].text, 'A < B AB')
  local none, err = xml.parse_xml ('<a><b></a>')
  eq (none, nil)
  ok (type (err) == 'string', 'a message for text that is not well formed')
end)

test ('children and attributes ignore namespace prefixes', function ()
  local root = assert (
    xml.parse_xml ('<w:sheet><w:row r="1"/><row r="2"/><col/></w:sheet>')
  )
  eq (xml.bare ('w:row'), 'row')
  eq (assert (xml.child (root, 'row')).attrs.r, '1')
  eq (#xml.children (root, 'row'), 2)
  eq (xml.child (root, 'cell'), nil)
  eq (xml.child (nil, 'row'), nil)
  local rel = assert (xml.parse_xml ('<sheet r:id="rId3" id="x"/>'))
  eq (xml.prefixed (rel, 'id'), 'rId3')
  ok (xml.flag (nil) and xml.flag ('1') and xml.flag ('true'))
  ok (not xml.flag ('0'))
  eq (xml.int ('12'), 12)
  eq (xml.int ('1.5'), nil)
end)

test (
  'text for elements and attributes is escaped and kept to UTF-8',
  function ()
    eq (xml.attr ('a "b" & <c>\n'), 'a &quot;b&quot; &amp; &lt;c&gt;&#10;')
    eq (xml.attr ('bell\7'), 'bell', 'control characters drop out')
    eq (xml.cell_string ('x<y\r'), 'x&lt;y_x000D_')
    eq (
      xml.cell_string ('_x0041_'),
      '_x005F_x0041_',
      'a literal escape stays as typed'
    )
    eq (xml.formula_text ('A1<"x"\7'), 'A1&lt;"x"')
    eq (
      xml.formula_text ('"a\rb"&1'),
      '"a&#13;b"&amp;1',
      'a CR is a reference, not escaped text'
    )
    local back =
      assert (xml.parse_xml ('<f>' .. xml.formula_text ('"a\rb"') .. '</f>'))
    eq (back.text, '"a\rb"', 'a CR reads back')
    eq (xml.utf8_only ('ok \255!'), 'ok \239\191\189!')
    eq (xml.utf8_only ('été'), 'été')
  end
)
