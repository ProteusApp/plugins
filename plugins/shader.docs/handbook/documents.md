---
title: shader.docs: the open shaders
section: Shader Builder
order: 319
keywords: shader docs documents service Shader.Docs open save undo redo active compiled program passes channels set_channel new_buffer buffer uniform rename remove events shader:dirty shader:changed shader:opened shader:closed shader:active shader:saved shader:reloaded shader:selected shader:uniform
---

# shader.docs: the open shaders

`shader.docs` keeps the shaders open in the Shader Builder. It reads and saves their files, keeps the undo history of each graph, knows which one is in front, and works out what the Preview runs. It draws nothing itself: `shader.canvas` draws a graph's tab and `shader.code` a code shader's.

A graph is a `*.shader.json` file. A code shader is a `.frag`, `.glsl` or `.wgsl` file, and a `.vert` file beside a `.frag` file of the same name is its vertex shader. New shaders go in `shaders/`.

It offers the `shader.docs` service. List `shader.docs` in `depends`. The service needs no permission. Its type is `Shader.Docs`, in `shader.core/types/shader.lua`, so cast it:

```lua
local docs = app.use ('shader.docs') --[[@as Shader.Docs]]
```

## An open shader

Each open shader is a `Shader.OpenDoc`:

| Field | What it holds |
|-------|---------------|
| `path` | Its workspace path, such as `'shaders/waves.frag'`. |
| `kind` | `'graph'` or `'code'`. |
| `language` | `'glsl'` or `'wgsl'`. For a graph, the language the Preview runs. |
| `stage` | For code: `'fragment'`, or `'vertex'` for a `.vert` file. |
| `title` | The name its tab shows. |
| `text` | For code: the text now. |
| `history` | For a graph: its undo history. `history.doc` is the graph now. |
| `selection` | For a graph: the ids of the picked nodes. |
| `values` | For code: the values the Preview's controls set, by uniform. |
| `channels` | For code: what the user picked for each channel, by `'0'` to `'3'`. A graph keeps them in its file. |
| `dirty` | True while it has changes that are not saved. |
| `missing` | True once its file was deleted. It stays open, unsaved, until a save writes the file again. |
| `version` | Goes up with each change. |

Read these fields, and change a shader through the service, so its tab, its undo and the other plugins follow.

## Functions

| Function | What it does |
|----------|--------------|
| `open (path)` | Opens a shader in a tab, or brings its tab to the front. Returns it, or nil when it cannot open. |
| `get (path)` | The open shader at `path`, or nil. |
| `active ()` | The shader whose tab was in front last, or nil. |
| `list ()` | Every open shader, in the order they opened. |
| `files ()` | Every shader in `shaders/`, apart from builds. Do not change the list it returns. |
| `kind_of (path)` | `'graph'`, `'code'`, or nil for a file that is not a shader. |
| `change (path, doc, key)` | Records a new graph for an open graph. Quick changes with the same `key` merge into one undo step. |
| `set_text (path, text)` | Changes an open code shader's text. |
| `undo (path)` and `redo (path)` | Undo and redo in an open graph. True when something changed. |
| `save (path)` | Writes an open shader to its file. True when it saved. |
| `select (path, ids)` | Picks nodes in an open graph. |
| `compiled (path)` | A graph compiled, kept until it changes. |
| `program (path, lang)` | What the Preview runs, and its problems. |
| `passes (path)` | The files of the shader's passes. |
| `channels (path)` | What each channel, 0 to 3, shows. |
| `set_channel (path, index, source)` | Picks what a channel shows. |
| `new_buffer (path)` | Adds the next free buffer to the shader and opens it. |
| `set_language (path, lang)` | Picks the language the Preview runs a graph in. |
| `set_uniform (path, key, value)` | Sets the value a uniform's control holds. |
| `remove (path)` | Deletes a shader's file and closes its tab. |
| `rename (path, to)` | Renames a shader's file. |
| `new_graph (name)` and `new_code (lang, name, template)` | Make a new shader in `shaders/` and open it. |
| `register_opener (kind, fn)` | Sets what draws a tab for `'graph'` or `'code'`. |

`folder` is `'shaders'`, and `extensions` lists the endings of shader files.

## Changing a graph

A graph changes through the `shader` service's `graph` module, which returns a new graph, and `docs.change`, which records it. The change is one undo step:

```lua
local shader = app.use ('shader') --[[@as Shader.Core]]
local docs = app.use ('shader.docs') --[[@as Shader.Docs]]
local front = docs.active ()
if front and front.kind == 'graph' then
  local doc, id = shader.graph.add_node (front.history.doc, 'time', 40, 40)
  if doc then
    docs.change (front.path, doc)
  else
    app.log (id)
  end
end
```

## What the Preview runs

`docs.program (path, lang)` returns the `Shader.Program` the Preview runs, and a list of problems. It works for an open shader and for any shader file that is not open, such as the buffers of the one in front. For a graph, `lang` picks GLSL or WGSL, and it is the graph's own language when nil. A vertex shader runs with the `.frag` file of the same name.

The problems include the channels the code reads: one that shows nothing, one that reads a buffer the shader does not have, and one that waits for an image.

```lua
local docs = app.use ('shader.docs') --[[@as Shader.Docs]]
local program, problems = docs.program ('shaders/waves.frag')
if program then
  app.log (#program.uniforms .. ' uniforms')
end
for _, p in ipairs (problems) do
  app.log (p.line, p.message)
end
```

`docs.compiled (path)` returns the whole `Shader.CompileResult` of a graph, with both programs. It is nil for code.

## Passes and channels

A shader can have up to four buffers, Buffer A to D, each a file named after it, such as `ink.buffer-a.frag` for `ink.frag`. [Textures and buffers](textures.md) covers them for people writing shaders.

- `docs.passes (path)` returns a `Shader.PassSet` for the shader a file belongs to: `base`, the path without the pass and the ending, `show`, the pass of the file asked about, `image`, the image's file, and `buffers`, the file of each buffer that exists, by `'a'` to `'d'`.
- `docs.channels (path)` returns what each channel, 0 to 3, shows: the user's pick, or else what the code's `@channel` notes give, or `{ kind = 'none' }`.
- `docs.set_channel (path, index, source)` picks what channel `index` shows in an open shader. Nil goes back to what the notes give. A graph keeps the pick in its file, as an undo step. A code shader keeps it beside the workspace.
- `docs.new_buffer (path)` writes the next free buffer, in the shader's language, from a start that leaves a trail behind the mouse, and opens it. It returns the new buffer, or nil and why, such as when the shader has all four.

This adds a buffer to the shader in front and shows it on the image's `iChannel0`:

```lua
local shader = app.use ('shader') --[[@as Shader.Core]]
local docs = app.use ('shader.docs') --[[@as Shader.Docs]]
local front = docs.active ()
if front then
  local image = front.path
  local buffer, why = docs.new_buffer (image)
  if buffer then
    local _, pass = shader.passes.pass_of (buffer.path)
    docs.set_channel (image, 0, { kind = 'buffer', buffer = pass })
  else
    app.log (why)
  end
end
```

`new_buffer` opens the buffer, so it comes to the front. The image stays open in its own tab.

## Files

- `docs.save (path)` writes an open shader. When the file changes outside the builder, a shader with no unsaved changes loads it again, and one with changes asks first.
- `docs.rename (path, to)` keeps the ending. An open shader moves to a new tab with its undo and unsaved changes. It returns false and why when it cannot.
- `docs.remove (path)` deletes the file and closes the tab. A changed example goes back to the original instead.
- `docs.new_graph (name)` and `docs.new_code (lang, name, template)` pick a free name in `shaders/`. `lang` is `'glsl'`, `'wgsl'` or `'vertex'`. A `name` with a `/` in it is the path itself.

## Events

`shader.docs` sends these events. Any plugin can listen.

| Event | Receives | When |
|-------|----------|------|
| `shader:opened` | the path | A shader opened in a tab. |
| `shader:closed` | the path | Its tab closed. |
| `shader:active` | the path, or nil | Another shader came to the front, or none is in front. |
| `shader:changed` | the path | Its graph, its text or its channels changed. |
| `shader:dirty` | the path, and true while it has unsaved changes | It gained or lost unsaved changes. A shader that closes with changes sends false. |
| `shader:saved` | the path | It was written to its file. |
| `shader:reloaded` | the path | It loaded its file again after a change from outside. |
| `shader:selected` | the path and the picked node ids | The pick in a graph changed. |
| `shader:uniform` | the path, the uniform's key and its value | A uniform's control changed. |

The tabs show unsaved changes by themselves. `shader:dirty` is for a plugin that shows them somewhere else, such as a list of open shaders:

```lua
local unsaved = {} ---@type table<string, boolean>
app.on ('shader:dirty', function (path, dirty)
  unsaved[path] = dirty or nil
  app.log (path, dirty and 'has changes' or 'is saved')
end)
```
