---
title: Meshes and other engines
section: Learning shaders
order: 316
keywords: 3d mesh preview sphere cube plane torus orbit view surface v_uv export engines hlsl direct3d godot gdshader three.js threejs shadermaterial unity shaderlab shader game engine copy build mesh uv surface
---

# Meshes and other engines

In a game or a 3D scene, a shader colours the surface of a mesh rather than a flat picture. The Preview shows a shader on a mesh, and a node graph can go to the engines most games and web pages run on: Direct3D through HLSL, Godot, three.js and Unity.

## Seeing a shader on a mesh

The **View** menu in the Preview panel's bar picks what the shader shows on: **Flat**, the whole panel as before, or a **Sphere**, a **Cube**, a **Plane** or a **Torus**. Drag the mesh to turn around it, use the mouse wheel to come nearer or go back, and double-click to put the camera back. While a mesh shows, the mouse turns the camera, so `u_mouse` keeps its last value.

A node graph runs as the fragment shader of the mesh's surface. **UV** runs across the surface from 0 to 1: around a sphere and a torus, and across each face of a cube. `u_resolution` is a square as wide as the panel's shorter side, so **Pixel Position** and **Square UV** count in it, and circles stay round on a plane.

A GLSL code shader does the same when it finds its place from `v_uv` alone. One that reads `gl_FragCoord`, such as a Shadertoy shader, draws a square picture first, and the mesh shows that picture. Either way, the surface shows the shader's colours as they are, without light.

## Getting the code

There are two ways:

- **Build Shader** (**Ctrl+Shift+B**) writes a file for each engine beside the GLSL and WGSL ones in `shaders/build/`, and its README says what each holds.
- **Copy the Shader for Another Engine** in the **Build** menu asks which engine, then copies that file's text, ready to paste into a project.

Only a node graph exports to other engines, since code shaders can hold any GLSL or WGSL. A graph with problems does not export until they are fixed.

| Engine | File | What it holds |
|--------|------|---------------|
| HLSL | `.hlsl` | A vertex and a pixel shader for Direct3D 11 and later, `VSMain` and `PSMain` |
| Godot | `.gdshader` | A canvas item shader for Godot 4 |
| three.js | `.three.js` | A JavaScript module whose `createMaterial()` makes a `ShaderMaterial` |
| Unity | `.shader` | An unlit shader for the built-in render pipeline |

## How the exports read their place

An export reads **UV** from the UV of whatever it draws on, as the Preview does on a mesh, so it colours the surface of any mesh, such as a sphere or a quad. **Pixel Position** is the UV times `u_resolution`, which says how many pixels the graph thinks it draws.

Each file says at its top what it needs each frame:

- **Time.** Godot and Unity keep the time themselves. For HLSL and three.js, set `u_time` to the seconds that have passed.
- **Size.** `u_resolution` starts at 512 by 512. Set it to the size of the surface in pixels, so shapes keep their proportions.
- **Parameters.** Each **Parameter** node is a uniform called `u_` and its name, with its starting value. In Godot and Unity it shows as a field of the material, with a slider or a colour picker.
- **Channels.** A **Texture** node's channel is a texture the engine gives it: `iChannel0` and its sampler in HLSL, a `sampler2D` uniform in Godot and three.js, and `_Channel0` in Unity. A channel that shows a buffer in the Shader Builder needs the engine to draw that buffer itself.

A graph that sets its own alpha blends in three.js and Unity, so what is behind shows through.

## Differences to know

The exports compute what the graph does, with a few differences each engine brings:

- HLSL and Godot count a texture's rows from the top, so the export turns the UV over when it reads a channel, and pictures stay the right way up.
- **Change Up** follows each engine's own direction for up on the screen.
- The HLSL constant buffer is laid out by HLSL's packing rules, which differ from WGSL's. The comment beside each field gives its offset.
