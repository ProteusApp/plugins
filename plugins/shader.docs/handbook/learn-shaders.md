---
title: Learning shaders
section: Learning shaders
order: 300
keywords: shader tutorial beginner learn glsl course guide start lessons chapters weather fragment shader builder how to
---

# Learning shaders

These pages teach shaders from the very start, with no graphics knowledge needed. They end with one shader that draws a whole weather system: a sky that moves from day to night, clouds that build and darken, rain, snow, lightning and wet ground. Each chapter adds one idea and ends with a shader that runs.

Every GLSL example here is a complete shader. Paste it into the Shader Builder and it runs as it is.

## What a shader is

A shader is a small program that runs on the graphics card. The kind these pages teach is a fragment shader, and it answers one question: what colour is this pixel? The graphics card runs it once for every pixel of the picture, side by side, about 60 times a second.

A pixel's program cannot see what its neighbours decided, and it keeps nothing from one frame to the next. It knows where it is, what time it is and the values it was handed, and the whole picture comes from those.

So shader code reads differently from most code. It never says "draw a circle here". Instead, each pixel asks "am I inside the circle?" and picks its own colour from the answer.

## Running the examples

The Shader Builder profile runs the Handbook beside the builder. **Ctrl+Shift+H** shows or hides it, so a page and its shader can stay open together.

1. Choose **File > New GLSL Shader** and give it a name.
2. Select all the starting code and paste an example over it.
3. Watch the **Preview** panel. It redraws as soon as the code changes.

A mistake shows as a red line in the editor, with the compiler's message, and the Preview lists it under the picture. The last picture that worked stays up until the code compiles again.

The Preview sets these values by itself, every frame:

| Name | Type | What it holds |
|------|------|---------------|
| `u_resolution` | `vec2` | The picture's width and height in pixels. |
| `u_time` | `float` | Seconds since the Preview started. |
| `u_frame` | `float` | How many frames it has drawn. |
| `u_mouse` | `vec4` | `xy` is where the mouse was last pressed or dragged on the picture, in pixels. `z` is 1 while the button is held. |
| `v_uv` | `vec2` | The pixel's place in the picture, from 0 at the bottom left to 1 at the top right. |

When a shader has no `#version` line, the Shader Builder adds one, with the precision line, a declaration for each value above that the shader uses, and `out vec4 fragColor`. The examples rely on this to stay short. [A first shader](first-shader.md) shows the full header once, so nothing stays hidden.

The buttons above the picture help while learning:

- **Pause** stops time, so a moving picture can be studied. **Ctrl+Space** does the same.
- **Restart** sets `u_time` back to 0.
- The scale buttons draw fewer or more pixels. A heavy shader runs faster at `0.5`.
- **Open a large preview** shows the picture in a bigger window.

## The chapters

Read them in order. Each one uses what the ones before it taught.

| Chapter | What it teaches |
|---------|-----------------|
| 1. [A first shader](first-shader.md) | Colours, pixel positions and the first moving picture. |
| 2. [The GLSL language](glsl-language.md) | Numbers, vectors, functions, loops and the mistakes everyone makes. |
| 3. [When a shader goes wrong](debugging.md) | Reading errors, showing values as colours and keeping a shader fast. |
| 4. [Shaping values](shaping.md) | `step`, `smoothstep`, `mix`, `fract` and the other functions that do most of the work. |
| 5. [Moving space](space.md) | Centring, scaling, turning and repeating the picture. |
| 6. [Shapes from distance](shapes.md) | Circles, boxes and lines, with clean edges, joined into larger shapes. |
| 7. [Colour](colour.md) | Gradients, palettes, layers and why light needs a gamma step. |
| 8. [Randomness and noise](noise.md) | Random numbers, smooth noise, and fractal noise for clouds and terrain. |
| 9. [3D with ray marching](raymarching.md) | A camera, rays and solid shapes in 3D, from distances alone. |
| 10. [Light, shadow and fog](lighting.md) | Shading, shadows, the sky and the haze of distance. |
| 11. [Clouds and other volumes](volumes.md) | Light passing through fog, smoke and cloud. |
| 12. [A weather system](weather.md) | Sky, sun, stars, clouds, rain, snow, lightning and wet ground, all set by one dial. |

Four more pages sit beside the course:

- [Shaders as node graphs](node-graphs.md) builds the same ideas from nodes, and shows which node matches which function.
- [From GLSL to WGSL](wgsl.md) turns a GLSL shader into WGSL for WebGPU.
- [Textures and buffers](textures.md) reads pictures in a shader, and adds passes that remember what they drew.
- [Further reading](resources.md) lists the books, articles, videos and shaders these pages draw on.

## How to learn from these pages

Reading a shader teaches far less than changing one. After each example, change every number in it, one at a time, and watch what moves. Break it on purpose and read the error.

Each chapter ends with a few changes to try, under **Try this**.

When an idea does not click, the same idea is usually in [The Book of Shaders](https://thebookofshaders.com/) or in an article by [Inigo Quilez](https://iquilezles.org/articles/), explained another way. [Further reading](resources.md) says which chapter each source matches.
