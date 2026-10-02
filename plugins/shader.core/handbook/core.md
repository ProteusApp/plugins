---
title: shader: the Shader Builder's core
section: Shader Builder
order: 318
keywords: shader core service Shader.Core graph compile glsl wgsl nodes catalog code shader source uniforms passes channels buffers file history build examples format subgraph made node make unpack expand shader.core
---

# shader: the Shader Builder's core

`shader.core` holds the logic of the Shader Builder: the node catalog, graph operations, the GLSL and WGSL compiler, code shaders, channels and passes, the file format, undo, and builds. It is pure Lua. It draws nothing and touches no file, so a plugin can use it to make, check and build shaders without opening any.

It offers the `shader` service, a table of modules. List `shader.core` in `depends`. The service needs no permission. Its type is `Shader.Core`, in `shader.core/types/shader.lua`, so cast it:

```lua
local shader = app.use ('shader') --[[@as Shader.Core]]
```

| Module | What it holds |
|--------|---------------|
| `nodes` | The node catalog: `list`, `categories`, and `get (type_id)` for one node's inputs, outputs and settings. |
| `graph` | Graph operations. Each returns a new graph, or nil and why not. |
| `subgraph` | Made nodes: a group of nodes made into one node, and unpacked again. |
| `compile` | `compile (doc)`, which turns a graph into GLSL and WGSL. |
| `source` | Code shaders: their uniforms, their programs, and the templates for new files. |
| `passes` | Channels and buffers: which file is which pass, and what each channel shows. |
| `file` | Reading and writing `*.shader.json` files. |
| `history` | Undo and redo for a graph. |
| `build` | The files a build writes. |
| `examples` | The example graphs, and the start of a new graph buffer. |
| `format` | Numbers and colours as the fields show them. |
| `types`, `helpers`, `layout` | Port types, the helper functions the code calls, and the WGSL uniform layout. |

The open shaders, their tabs and their files belong to `shader.docs`. See [shader.docs](shader.docs/documents.md).

## Graphs

A graph is a `Shader.Doc`: a name, a list of nodes and a list of wires. `graph.new (name)` makes one with a UV node wired into the output. The operations never change the graph they get. Each returns a new one, or nil and a sentence that says why not:

```lua
local shader = app.use ('shader') --[[@as Shader.Core]]
local doc = shader.graph.new ('Pulse')
local added, id = shader.graph.add_node (doc, 'time', 40, 240)
if not added then
  app.log (id)
  return
end
local wired, why = shader.graph.connect (added, id, 'time', 'n2', 'color')
if wired then
  doc = wired
else
  app.log (why)
end
```

The node ids are the `type` of each entry in `nodes.list`, such as `'time'`, `'mix'` or `'texture'`. `add_node` returns the new node's id, such as `'n3'`. `connect` takes the node and output a wire starts from, then the node and input it goes into. `why_not` says why a wire cannot go in, without making it.

Other operations change inputs and settings (`set_input`, `set_setting`), remove and move nodes, copy and paste, and keep the canvas's frames (`set_canvas`). `graph.set_channel (doc, index, source)` sets what channel `index` shows, from 0 to 3. See [Channels and passes](#channels-and-passes).

`graph.def (doc, type_id)` gives a node type as the graph reads it: an entry of the catalog, or a node made from a group in this graph. Use it instead of `nodes.get` for a node of a graph.

## Made nodes

`subgraph.make (doc, ids, name)` makes one node from a group of nodes. A wire from outside into the group becomes an input, and a wire out of it an output. The graph keeps the group in `doc.subgraphs`, by an id such as `'s1'`, and the made node's type is `'subgraph:s1'`. `subgraph.unpack (doc, id)` puts the nodes back, wired as before:

```lua
local shader = app.use ('shader') --[[@as Shader.Core]]
local doc = shader.graph.new ('Glow')
local made, id = shader.subgraph.make (doc, { 'n1' }, 'Place')
if not made then
  app.log (id)
  return
end
local back, ids = shader.subgraph.unpack (made, id)
if back then
  app.log (#ids .. ' nodes back')
end
```

`subgraph.rename (doc, sid, name)` renames a group, and every node made from it shows the new name. `subgraph.list (doc)` lists the groups with the type a new node made from each takes, for `graph.add_node`. Copy and paste carry a made node's group, and a group no node uses any more is dropped.

The compiler never sees a made node: `compile` calls `subgraph.expand (doc)` first, which puts each one's nodes in its place, with ids such as `n5_n1` inside `n5`. What the result says of those nodes it says of the made node, so a problem inside one shows on it. A graph with made nodes saves as format 2, which an older Shader Builder refuses rather than misreads.

## Compiling

`compile.compile (doc)` returns a `Shader.CompileResult`. `ok` is true when the graph has no errors, `errors` lists the problems, each with the node it comes from, and `glsl` and `wgsl` are the two programs:

```lua
local shader = app.use ('shader') --[[@as Shader.Core]]
local result = shader.compile.compile (shader.graph.new ('Gradient'))
if result.ok then
  app.log (result.glsl.source)
else
  for _, e in ipairs (result.errors) do
    app.log (e.message)
  end
end
```

A program holds the code in `source`, the uniforms the Preview shows controls for, and the channels it reads. `lines` maps a line of the code to the node that wrote it.

## Code shaders

`source.program (lang, text)` reads a code shader in `'glsl'` or `'wgsl'`. It returns the program and a list of problems. Each uniform with a note such as `@range 0 4 @default 1` in its comment gets a control:

```lua
local shader = app.use ('shader') --[[@as Shader.Core]]
local program, errors =
  shader.source.program ('glsl', shader.source.TEMPLATES.glsl)
for _, u in ipairs (program.uniforms) do
  app.log (u.key, u.min, u.max)
end
app.log (#errors .. ' problems')
```

`source.kind_of (path)` gives a file's language and stage from its name, such as `'glsl', 'fragment'` for a `.frag` file. `source.TEMPLATES` holds the starts of new files: `glsl`, `wgsl`, `shadertoy`, `vertex`, `buffer` and `buffer_wgsl`.

## Channels and passes

A shader reads up to four pictures, the channels `iChannel0` to `iChannel3`. A buffer is another pass of the same shader, drawn before the image each frame. `ink.buffer-a.frag` is Buffer A of `ink.frag`. [Textures and buffers](shader.docs/textures.md) covers them for people writing shaders. The `passes` module holds the rules:

| Function | What it does |
|----------|--------------|
| `pass_of (path)` | The shader a file belongs to, without its ending, and which pass it is: `'image'`, or `'a'` to `'d'`. |
| `pass_paths (base, pass)` | The paths a pass of that shader can have, in the order they are looked for. |
| `buffer_path (path, pass)` | The path a new buffer of the shader at `path` gets, keeping its ending. |
| `parse_source (words)` | A source from a note's words, such as `'buffer-a nearest'`. Nil when the words name none. |
| `clean_source (value)` | A source as it was stored, checked, or nil. |
| `label (source)` and `pass_label (pass)` | How a source or a pass reads to a person, such as `Buffer A`. |
| `glsl_channels (text)` and `wgsl_resources (text, code)` | The channels a code shader reads, with the sources its `@channel` notes give. |

A source is a `Shader.ChannelSource`. Its `kind` is `'none'`, `'noise'`, `'checker'`, `'image'` or `'buffer'`. A buffer source names the buffer in `buffer`, and any source may set `filter` (`'linear'` or `'nearest'`) and `wrap` (`'repeat'` or `'clamp'`).

```lua
local shader = app.use ('shader') --[[@as Shader.Core]]
local base, pass = shader.passes.pass_of ('shaders/ink.buffer-a.frag')
app.log (base, pass) -- shaders/ink  a
local source = shader.passes.parse_source ('buffer-a nearest')
app.log (shader.passes.label (source)) -- Buffer A
app.log (shader.passes.buffer_path ('shaders/ink.frag', 'b'))
```

## Files and undo

`file.save (doc)` returns a graph as the text of a `*.shader.json` file, and `file.load (text)` reads it back, or returns nil and why. `history.new (doc)` starts an undo history, `history.push (h, doc)` records a change, and `history.undo (h)` and `history.redo (h)` move through it. `h.doc` is the graph now.

## Builds

`build.files (input)` returns the files a build writes, by name: the GLSL shaders, the WGSL module, the code of each buffer, a page for each language that runs them in a browser, `uniforms.json` and a README. `input` is a `Shader.BuildInput` with the shader's name, its programs, its channels and its buffers. `shader.build` writes them to `shaders/build`.

```lua
local shader = app.use ('shader') --[[@as Shader.Core]]
local result = shader.compile.compile (shader.graph.new ('Gradient'))
local files = shader.build.files ({
  name = 'Gradient',
  glsl = result.glsl,
  wgsl = result.wgsl,
})
for name in pairs (files) do
  app.log (name)
end
```

`examples.build (name)` makes one of the example graphs in `examples.names`, and `examples.buffer (pass)` makes a new graph buffer that reads its own last frame.
