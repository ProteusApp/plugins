local hover = require ('lib.hover')

test ('clean leaves plain Markdown as it is', function ()
  local text =
    '```gdscript\nfunc jump() -> void\n```\n---\nMakes the player jump.'
  eq (hover.clean (text), text)
end)

test ('clean turns br into a paragraph break', function ()
  eq (hover.clean ('One.`br`Two.'), 'One.\n\nTwo.')
end)

test ('clean turns gdscript and csharp marks into code blocks', function ()
  local text = '`codeblocks``gdscript`\nvar x = 1\n`/gdscript``csharp`\n'
    .. 'int x = 1;\n`/csharp``/codeblocks`'
  eq (
    hover.clean (text),
    '\nGDScript:\n```gdscript\nvar x = 1\n```\nC#:\n```csharp\nint x = 1;\n```'
  )
end)

test (
  'clean takes # off lines outside code, which Markdown reads as headings',
  function ()
    eq (
      hover.clean ('Moves the player.\n## Speed in pixels.\n# More.'),
      'Moves the player.\nSpeed in pixels.\nMore.'
    )
  end
)

test ('clean keeps # comments inside code blocks', function ()
  local text = 'Example:\n```gdscript\n# a comment\nvar x = 1\n```'
  eq (hover.clean (text), text)
end)

test ('clean gives nil for no help', function ()
  eq (hover.clean (nil), nil)
  eq (hover.clean (''), nil)
  eq (hover.clean ('\n\n'), nil)
end)
