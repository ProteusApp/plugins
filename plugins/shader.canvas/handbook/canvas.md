---
title: shader.canvas: the node editor
section: Shader Builder
order: 320
keywords: shader canvas node editor graph add node fit select pick shader.canvas Shader.CanvasService
---

# shader.canvas: the node editor

`shader.canvas` draws a shader graph as nodes and wires. Each graph open in the Shader Builder gets its own canvas, and the graph itself lives in `shader.docs`. The canvas offers the `shader.canvas` service, so other plugins can add nodes, frame the graph and pick nodes.

List `shader.canvas` in `depends`, or in `optional` and use `app.try_use`. The service needs no permission. Its type is `Shader.CanvasService`, in `shader.core/types/shader.lua`, so cast it:

```lua
local canvas = app.use ('shader.canvas') --[[@as Shader.CanvasService]]
```

| Function | What it does |
|----------|--------------|
| `add (type_id)` | Adds a node of that type to the graph in front, in the middle of the view, and picks it. False when no graph is in front. |
| `fit ()` | Zooms and pans the graph in front so every node and frame shows. |
| `select (path, ids)` | Picks the nodes with these ids on the canvas of the graph at `path`, a workspace path. |

## `canvas.add`

`canvas.add (type_id)` adds one node, such as `'time'`, `'mix'` or `'value_noise'`. The ids are the `type` of each node in the `shader` service's catalog, `nodes`. The change is one undo step. A node the graph cannot take, such as a second Output node, is refused with a message, and nothing changes.

```lua
local canvas = app.use ('shader.canvas') --[[@as Shader.CanvasService]]
app.use ('commands').register ({
  id = 'mynodes.add_time',
  category = 'My nodes',
  title = 'Add a Time Node',
  run = function ()
    if not canvas.add ('time') then
      app.log ('Open a shader graph first.')
    end
  end,
})
```

## `canvas.fit`

`canvas.fit ()` frames the graph in front, the same as **Graph > Zoom to Fit** (**Shift+1**). It does nothing when no graph is in front.

## `canvas.select`

`canvas.select (path, ids)` picks nodes, replacing what was picked. The pick goes to `shader.docs` too, which sends `shader:selected` with the path and the ids, so the code view marks the lines those nodes wrote. The Preview and the code view use it to point at the node an error comes from:

```lua
local canvas = app.try_use ('shader.canvas') --[[@as Shader.CanvasService?]]
if canvas then
  canvas.select ('shaders/plasma.shader.json', { 'n3' })
end
```

It does nothing for a graph that is not open.
