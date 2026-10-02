---
title: Textures and buffers
section: Learning shaders
order: 315
keywords: texture textures image picture sampler sampler2D iChannel channel buffer buffers multipass pass feedback last frame trail blur simulation render to texture shadertoy iChannelResolution iDate date noise checker texelFetch
---

# Textures and buffers

A shader can read pictures as well as numbers. Each shader has four channels, `iChannel0` to `iChannel3`, as on Shadertoy, and each channel shows one picture:

| Source | What the channel shows |
|--------|------------------------|
| Nothing | Black. The Preview warns about a channel the shader reads that shows nothing. |
| Noise | 256 by 256 pixels of random colour. Each of red, green, blue and alpha is random on its own. |
| Checker | Eight grey and white squares to a side, for checking how a picture is placed. |
| Image | A picture you pick from your computer. |
| Buffer A to D | What another pass of this shader drew. See [Buffers](#buffers). |

## Picking what a channel shows

The **Channels** section of the Preview panel lists each channel the shader in front reads. Its menu picks the source, and two more menus pick how it is read:

- **Smooth** blends between pixels, and **Pixels** reads the nearest one, for a sharp, blocky look or for exact values from a buffer.
- **Repeat** tiles the picture past its edges, and **Clamp** repeats its edge pixels instead. A buffer starts on Clamp.

**Image…** opens your computer's own file dialog. The picture goes to the Preview and nowhere else: the Shader Builder gets a name for the file, never its path, and needs no permission to read it. After Proteus restarts, the first preview that uses your earlier pictures asks once whether it may use them again.

A graph keeps its channels in its file. A code shader keeps them beside your workspace, and its notes give the ones you have not picked, as the next section shows.

## Reading a texture in GLSL

`texture(channel, uv)` reads a picture at a position from 0 to 1, with 0 at the bottom left. Here the image is stretched over the whole preview:

```glsl
// @channel 0 noise
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv = fragCoord / iResolution.xy;
  fragColor = vec4(texture(iChannel0, uv).rgb, 1.0);
}
```

A short shader like this one gets `uniform sampler2D iChannel0;` added when it uses `iChannel0`. A full shader declares it, as any uniform:

```glsl
#version 300 es
precision highp float;

uniform vec2 u_resolution;
uniform sampler2D iChannel0; // @channel 0 checker nearest
uniform sampler2D u_paper; // @channel 1 noise

out vec4 fragColor;

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  fragColor = texture(iChannel0, uv * 2.0) * texture(u_paper, uv);
}
```

The note `@channel` does two things:

- On a `sampler2D` line, it says which channel the sampler reads. A sampler named `iChannel0` to `iChannel3` needs no note.
- With a source after the number, such as `@channel 0 buffer-a`, it says what the channel shows until you pick something else. The sources are `noise`, `checker`, `buffer-a` to `buffer-d` and `none`, and `nearest` or `clamp` may follow.

A sampler that reads no channel gets a warning, and so does a `samplerCube` or a `sampler3D`, which the Preview cannot fill. `iChannelResolution[n].xy` is the size of channel `n`'s picture, in pixels.

## Reading a texture in a graph

The **Texture** node reads one channel, picked in its settings, at its `uv` input. With nothing wired in, `uv` is the pixel's own position, so the picture covers the preview. Its outputs are the colour, its alpha, all four together, and the picture's size in pixels.

## Buffers

A buffer is a pass of the shader that draws before the image, each frame, into a picture of its own. The image reads that picture through a channel, and so can every buffer, itself included. A buffer that reads itself gets the picture it drew one frame earlier, so it can carry anything over from frame to frame: trails, paint, a simulation, or a blur built up over time.

A buffer is a file named after its shader. `ink.buffer-a.frag` is Buffer A of `ink.frag`, and `glow.buffer-b.shader.json` is Buffer B of the graph `glow.shader.json`. **File > Add a Buffer to This Shader** makes the next one, in the shader's language, from a start that leaves a trail behind the mouse.

Each frame:

1. Buffers A, B, C and D draw, in that order, each the size of the preview.
2. The image draws, reading what the buffers drew.

A channel that shows a buffer reads its newest picture. For a buffer that already drew this frame, that is this frame's. For the buffer itself, and for the ones after it, that is the last frame's.

The `ink` example in `shaders/` is a shader with one buffer. Its Buffer A keeps how much ink lies on each pixel. Here is a smaller Buffer A in the same spirit. Each frame it reads the ink it held, lets a little dry, and adds a drop under the mouse:

```glsl
// @channel 0 buffer-a
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv = fragCoord / iResolution.xy;
  float ink = texture(iChannel0, uv).r * 0.996;
  if (iMouse.z > 0.0) {
    ink += 1.0 - smoothstep(0.0, 10.0, length(fragCoord - iMouse.xy));
  }
  fragColor = vec4(min(ink, 1.0), 0.0, 0.0, 1.0);
}
```

The image then reads the ink on `iChannel0` and turns it into colour. A buffer keeps numbers below 0 and above 1 where the graphics card can draw into floats, as most can.

A few rules keep passes simple:

- With a buffer's tab in front, the Preview shows that buffer's picture, which is how to see what it holds.
- Every pass runs in the image's language. A graph buffer follows the image, and a code buffer in the other language is a problem in the Preview.
- Pausing the Preview stops the buffers too, and starting the time again from 0 clears them.
- A problem in a buffer shows in the Preview as, for example, `Buffer A line 4`. A click opens the buffer.

## Textures in WGSL

In WGSL, a channel is a `texture_2d<f32>` named `iChannel0` to `iChannel3`, or noted with `@channel`. A sampler named after its texture, such as `iChannel0_sampler`, reads as that channel says:

```wgsl
@group(1) @binding(0) var iChannel0: texture_2d<f32>; // @channel 0 noise
@group(1) @binding(1) var iChannel0_sampler: sampler;
```

WGSL counts a texture's rows from its top, as it counts `position.y`. So `position.xy / u.resolution` reads a buffer or an image the right way up, while a position with 0 at the bottom needs its `y` turned over first, as `1.0 - uv.y`.

## The date

`iDate` holds the year, the month counting from 0, the day of the month, and the seconds since midnight, so `iDate.w` drives a clock. A graph has the **Date** node, and a full GLSL shader declares `uniform vec4 u_date;`.

## Building a shader with buffers

**Build** writes every buffer beside the image, as `ink.buffer-a.frag`, and the page it writes runs them all. Noise and Checker come with the page. An image a channel shows goes beside the page under its own name, and a browser loads it only when the folder is served, such as with `npx serve`, rather than opened as a file. The build's README lists each pass's channels.

## Try this

- In the `ink` example, change `0.996` to `0.95`, and the ink dries quickly.
- Set the image's `iChannel0` to Noise, then back to Buffer A.
- Add Buffer B to `ink.frag`, and have it blur Buffer A by reading four neighbours. Then show Buffer B in the image instead.
