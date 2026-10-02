---
title: Further reading
section: Learning shaders
order: 316
keywords: resources links books articles videos tutorials book of shaders inigo quilez shadertoy art of code sebastian lague freya holmer clouds horizon zero dawn frostbite scratchapixel webgl webgpu lygia gpu gems references sources
---

# Further reading

These are the sources the course draws on, and the best places to go next. All of them are free to read or watch. The table under [By chapter](#by-chapter) says which chapter each source goes with.

## Start with these

- [The Book of Shaders](https://thebookofshaders.com/) by Patricio Gonzalez Vivo and Jen Lowe is a gentle book on fragment shaders, with every example running live beside its code. Its chapters on [shaping functions](https://thebookofshaders.com/05/), [noise](https://thebookofshaders.com/11/) and [fractal Brownian motion](https://thebookofshaders.com/13/) go with chapters 4 and 8.
- [Inigo Quilez's articles](https://iquilezles.org/articles/) are short, exact write-ups of most techniques in this course, by one of the people who made them common. The table below lists the most useful under each chapter.
- [Shadertoy](https://www.shadertoy.com/) holds tens of thousands of shaders with their code, all in the browser. A shader written with `mainImage` runs in the Shader Builder unchanged: choose **File > New Shadertoy-Style Shader** and paste it in. Shaders that read textures or other buffers, through `iChannel0` and the like, need features the Preview does not have.
- [The Art of Code](https://www.youtube.com/@TheArtofCodeIsCool) is Martijn Steinrucken's YouTube channel. He writes shaders live from an empty file and explains each line, from first circles to rain on glass.
- [Shaders for Game Devs](https://www.youtube.com/watch?v=kfM-yu0iQBk) by Freya Holmér is a video course on how shaders work and why, aimed at game developers.

## By chapter

| Chapter | Sources |
|---------|---------|
| [1. A first shader](first-shader.md) | [The Book of Shaders](https://thebookofshaders.com/), its first chapters |
| [2. The GLSL language](glsl-language.md) | The [GLSL ES 3.00 specification](https://registry.khronos.org/OpenGL/specs/es/3.0/GLSL_ES_Specification_3.00.pdf), and [WebGL2 Fundamentals](https://webgl2fundamentals.org/) for the WebGL side |
| [3. When a shader goes wrong](debugging.md) | Any shader on [Shadertoy](https://www.shadertoy.com/), taken apart one value at a time |
| [4. Shaping values](shaping.md) | [Shaping functions](https://thebookofshaders.com/05/), and Inigo Quilez's [useful little functions](https://iquilezles.org/articles/functions/) |
| [5. Moving space](space.md) | The Book of Shaders chapters on matrices and patterns |
| [6. Shapes from distance](shapes.md) | Inigo Quilez's [2D distance functions](https://iquilezles.org/articles/distfunctions2d/) and [smooth minimum](https://iquilezles.org/articles/smin/) |
| [7. Colour](colour.md) | Inigo Quilez's [palettes](https://iquilezles.org/articles/palettes/) |
| [8. Randomness and noise](noise.md) | [Noise](https://thebookofshaders.com/11/), [fractal Brownian motion](https://thebookofshaders.com/13/), Dave Hoskins's [Hash without Sine](https://www.shadertoy.com/view/4djSRW), and Inigo Quilez's [fbm](https://iquilezles.org/articles/fbm/) and [domain warping](https://iquilezles.org/articles/warp/) |
| [9. 3D with ray marching](raymarching.md) | Inigo Quilez's [ray marching distance fields](https://iquilezles.org/articles/raymarchingdf/), [3D distance functions](https://iquilezles.org/articles/distfunctions/) and [normals for an SDF](https://iquilezles.org/articles/normalsSDF/) |
| [10. Light, shadow and fog](lighting.md) | Inigo Quilez's [soft shadows](https://iquilezles.org/articles/rmshadows/), and [LearnOpenGL](https://learnopengl.com/) for lighting in depth |
| [11. Clouds and other volumes](volumes.md) | [Coding Adventure: Clouds](https://www.youtube.com/watch?v=4QOcCGI6xOU) by Sebastian Lague, Scratchapixel's [introduction to volume rendering](https://www.scratchapixel.com/lessons/3d-basic-rendering/volume-rendering-for-developers/intro-volume-rendering.html), the [Beer–Lambert law](https://en.wikipedia.org/wiki/Beer%E2%80%93Lambert_law), and [phase functions](https://www.pbr-book.org/4ed/Volume_Scattering/Phase_Functions) in Physically Based Rendering |
| [12. A weather system](weather.md) | The talks and shaders under [Weather and skies](#weather-and-skies) |
| [From GLSL to WGSL](wgsl.md) | The [WGSL specification](https://www.w3.org/TR/WGSL/) and [WebGPU Fundamentals](https://webgpufundamentals.org/) |

## Weather and skies

- [The Real-time Volumetric Cloudscapes of Horizon Zero Dawn](https://www.guerrilla-games.com/read/the-real-time-volumetric-cloudscapes-of-horizon-zero-dawn) by Andrew Schneider and Nathan Vos is a talk from the SIGGRAPH 2015 graphics conference. It shows how a game draws a whole sky of clouds that change with the weather. The cloud layer's height profile and coverage bar in this course follow the same idea.
- [Physically Based Sky, Atmosphere and Cloud Rendering in Frostbite](https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/s2016_pbs_frostbite_sky_clouds.pdf) by Sébastien Hillaire is a talk from SIGGRAPH 2016. It goes a step beyond a painted sky gradient, to a sky worked out from how air and dust scatter light.
- [Clouds](https://www.shadertoy.com/view/XslGRr) by Inigo Quilez is a complete cloud shader to read from start to end.
- [Rainforest](https://www.shadertoy.com/view/4ttSWf) by Inigo Quilez ray marches terrain, trees, fog and light.
- [Heartfelt](https://www.shadertoy.com/view/ltffzl) by Martijn Steinrucken shows rain running down a window, with a blurred city behind.
- [Just snow](https://www.shadertoy.com/view/ldsGDn) by Andrew Baldwin draws layers of falling snow in very little code.

## Going further

- [LYGIA](https://lygia.xyz/) is a large library of shader functions for noise, colour, lighting and shapes, in GLSL and WGSL. Copying a function from it is a good way to learn how that function works.
- [GPU Gems](https://developer.nvidia.com/gpugems/gpugems/contributors) is a series of free books of graphics techniques from NVIDIA. They are older, but much of what they cover still applies.
- [WebGL2 Fundamentals](https://webgl2fundamentals.org/) and [WebGPU Fundamentals](https://webgpufundamentals.org/) cover the JavaScript side of running these shaders on a web page of one's own. **Build Shader** writes such a page already, and the two sites explain how it works.
