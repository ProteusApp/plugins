local templates = require ('lib.templates') --[[@as LangGitfiles.TemplatesModule]]

test ('the templates the command offers are all there', function ()
  for _, name in ipairs ({
    'Node',
    'Python',
    'Rust',
    'Go',
    'Java',
    'Lua',
    'macOS',
    'Windows',
    'Linux',
    'VS Code',
    'JetBrains',
  }) do
    ok (templates.get (name), name)
  end
  eq (templates.get ('Cobol'), nil)
end)

test ('every template line is one line of plain text', function ()
  for _, t in ipairs (templates.list) do
    ok (t.detail ~= '', t.name)
    ok (#t.lines > 0, t.name)
    for _, line in ipairs (t.lines) do
      ok (not line:find ('%c'), t.name .. ': ' .. line)
      ok (
        line == line:gsub ('^%s+', ''):gsub ('%s+$', ''),
        t.name .. ': ' .. line
      )
    end
  end
end)

test ('a template starts a new file under its heading', function ()
  local rust = templates.get ('Rust') --[[@as LangGitfiles.Template]]
  eq (
    templates.add ('', rust),
    '# Rust\n' .. table.concat (rust.lines, '\n') .. '\n'
  )
end)

test (
  'a template goes after a blank line, without lines the file has',
  function ()
    eq (
      templates.append ('target/\n*.log', '# Rust', { 'target/', '*.pdb' }),
      'target/\n*.log\n\n# Rust\n*.pdb\n'
    )
    eq (templates.append ('a\n\n', '# B', { 'b' }), 'a\n\n# B\nb\n')
  end
)

test ('nothing changes when every line is there', function ()
  eq (templates.append ('  dist/  \n# x\n', '# Node', { '# x', 'dist/' }), nil)
end)

test ('a line repeated in a template goes in once', function ()
  eq (templates.append ('', nil, { 'a', 'a' }), 'a\n')
end)

test ('without a heading the line goes right after the last one', function ()
  eq (templates.append ('a', nil, { '/b.txt' }), 'a\n/b.txt\n')
  eq (templates.append ('a\n', nil, { 'a' }), nil)
end)
