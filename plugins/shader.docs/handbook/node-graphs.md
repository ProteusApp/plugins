---
title: Shaders as node graphs
section: Learning shaders
order: 313
keywords: node graph nodes wires canvas add node connect expression node parameter output generated code open as code shader visual shader no code
---

# Shaders as node graphs

A node graph builds a shader without typing code. Each node is one of the functions from this course, and wires carry values between them. The Shader Builder turns the graph into GLSL and WGSL as it changes.

Graphs suit the 2D chapters well: shaping, coordinates, shapes, colour and noise. Ray marching, volumes and the weather shader need loops, which graphs do not have, so they stay as code.

## How a graph works

A graph reads from left to right. Nodes on the left produce values, such as the pixel's position or the time, and nodes in the middle change them. Every graph ends at one **Output** node, whose `colour` input is the pixel's colour, the same as `fragColor`.

A wire runs from a node's output, on its right side, to another node's input, on its left. Its colour shows the type of value it carries:

| Colour | Type |
|--------|------|
| Grey | `float` |
| Green | `vec2` |
| Yellow | `vec3` |
| Pink | `vec4` |

An input with no wire shows a number field instead. Most `uv` inputs read the pixel's position by themselves when nothing is wired in. Many maths nodes, such as **Add** and **Mix**, take whichever type is wired in, so one **Mix** node blends numbers or colours alike.

## Working in the editor

| To | Do this |
|----|---------|
| Start a graph | **File > New Node Graph** (**Ctrl+N**) |
| Add a node | Double-click the canvas, press **Ctrl+K**, or click a node in the **Nodes** list on the left |
| Connect two nodes | Drag from an output to an input |
| Move a wire | Drag its end off the input it is plugged into |
| Move around | Drag empty canvas to pan. A mouse wheel zooms, and a touchpad pans. |
| Delete or copy nodes | **Delete**, or **Ctrl+D** to duplicate |
| Tidy the layout | **Tidy Up** from the command palette |
| See the whole graph | **Shift+1** |
| Undo | **Ctrl+Z** |

The **Nodes** list has a search box, which finds a node by its name or its group.

## A first graph

The `clouds` graph in `shaders/` is the 2D clouds from [Randomness and noise](noise.md#clouds-in-2d), as nodes. Open it from the **Shaders** list and follow the wires from left to right:

1. **Square UV** gives the pixel's position, with square pixels so the clouds are not stretched.
2. **Time**, multiplied by a **Vector 2**, makes an offset that grows with time, which is the wind.
3. **Fractal Noise** reads the position plus the offset.
4. **Smooth Step** turns the noise into cloud or clear sky, as the `cover` slider did in code.
5. **Mix** blends between two **Colour** nodes, sky and cloud, by that amount.
6. **Output** shows the result.

Click any node to see its settings. Change the **Smooth Step** node's `from` and `to`, and the cloud cover changes, the same as moving the bar in code.

## Which node is which

Every function in the 2D chapters has a node:

| In code | Node |
|---------|------|
| `v_uv`, or `gl_FragCoord.xy / u_resolution` | **UV** |
| `(gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y` | **Centred UV** |
| `gl_FragCoord.xy` | **Pixel Position** |
| `u_time`, `sin(u_time)` | **Time**, with outputs for both |
| `u_mouse` | **Mouse** |
| A uniform with a slider | **Parameter** |
| `mix`, `smoothstep`, `step`, `clamp` | **Mix**, **Smooth Step**, **Step**, **Clamp** |
| `fract`, `floor`, `abs`, `sin` | **Fraction**, **Floor**, **Absolute**, **Sine** |
| `remap` from [Shaping values](shaping.md#mix-clamp-and-changing-a-range) | **Remap** |
| `rotate`, zooming, `fract` of coordinates, polar coordinates | **Rotate**, **Scale**, **Tile**, **Polar** |
| A circle, a ring, a box | **Circle**, **Ring**, **Rectangle** |
| `hash` | **Random** |
| Value noise, gradient noise, fractal noise, cells | **Value Noise**, **Gradient Noise**, **Fractal Noise**, **Voronoi** |
| `hsv2rgb`, the cosine palette | **HSV to RGB**, **Cosine Palette** |
| Splitting or building vectors, swizzles | **Split**, **Combine**, **Swizzle** |

A **Parameter** node becomes a uniform. Its value gets a slider in the Preview panel, as a uniform with notes does in code, and its `min` and `max` set the slider's range.

## The Expression node

Some maths has no node of its own. The **Expression** node takes up to four inputs, `a`, `b`, `c` and `d`, and any expression over them, such as `sin(a * 3.0) + b`.

It writes the expression into both languages, so `vec3(` and `vec3f(` both work. Most one-line formulas in this course fit in one.

## From a graph to code

A graph is a good way to sketch an idea. When it needs a loop, a function of its own, or 3D, move it to code:

- **Show the Generated Code** (**Ctrl+Shift+C**) shows the code the graph turns into. A click on a line selects the node that wrote it, which is a good way to learn how each node works.
- **Open This Graph as a Code Shader** copies that code into a new code shader, to take further by hand.

The code a graph writes is plain GLSL or WGSL, with each node's result in its own variable. Reading it is a quick way to see the chapters' ideas in a form the Shader Builder wrote itself.
