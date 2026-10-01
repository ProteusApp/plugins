local ignore = require ('lib.ignore') --[[@as LangGitfiles.IgnoreModule]]

---True when the text holds the words.
---@param text string?
---@param words string
---@return boolean
local function says (text, words)
  return text ~= nil and text:find (words, 1, true) ~= nil
end

test ('a comment and a blank line', function ()
  eq (ignore.explain ('# build output'), 'A comment. Git skips this line.')
  eq (ignore.explain ('   '), nil)
end)

test ('a known pattern says why projects ignore it', function ()
  local text = ignore.explain ('node_modules/')
  ok (says (text, '**`node_modules/`**'))
  ok (says (text, 'npm'))
  ok (says (text, 'folders only'))
  ok (says (text, 'every folder below'))
end)

test ('a pattern with a slash matches from this folder only', function ()
  ok (says (ignore.explain ('/build'), 'not anywhere below'))
  ok (says (ignore.explain ('docs/*.md'), 'not anywhere below'))
  ok (not says (ignore.explain ('build/'), 'not anywhere below'))
end)

test ('negation, double stars and wildcards are explained', function ()
  local text = ignore.explain ('!.env.example')
  ok (says (text, 'brings back'))
  ok (says (ignore.explain ('**/logs'), 'in any folder'))
  ok (says (ignore.explain ('logs/**'), 'everything inside'))
  ok (says (ignore.explain ('a/**/b'), 'any number of folders'))
  ok (says (ignore.explain ('*.log'), 'any characters except'))
  ok (says (ignore.explain ('file?.txt'), 'one character except'))
  ok (says (ignore.explain ('*.py[cod]'), 'one character of the ones'))
  ok (not says (ignore.explain ('**/logs'), 'any characters except'))
end)

test ('a backslash makes # and ! plain characters', function ()
  local text = ignore.explain ('\\#notes#')
  ok (not says (text, 'comment'))
  ok (not says (ignore.explain ('\\!x'), 'brings back'))
end)

test ('pattern drops the spaces Git drops', function ()
  eq (ignore.pattern ('*.log   '), '*.log')
  eq (ignore.pattern ('name\\ '), 'name\\ ')
  eq (ignore.pattern ('# x'), nil)
end)

test ('at finds the pattern being typed, after any !', function ()
  eq (ignore.at ('node_mo', 7), { word = 'node_mo', from = 0 })
  eq (ignore.at ('!.env', 5), { word = '.env', from = 1 })
  eq (ignore.at ('', 0), { word = '', from = 0 })
  eq (ignore.at ('# comm', 6), nil)
  eq (ignore.at ('a b', 3), nil)
end)

test ('entry ties a file to its place and keeps wildcards plain', function ()
  eq (ignore.entry ('src/notes.txt'), '/src/notes.txt')
  eq (ignore.entry ('a\\b[1]*.txt'), '/a/b\\[1]\\*.txt')
  eq (ignore.entry ('odd name '), '/odd name\\ ')
end)

test ('every common pattern comes with an explanation', function ()
  for _, item in ipairs (ignore.items ()) do
    ok (item.documentation and item.documentation:match ('%.$'), item.label)
  end
end)
