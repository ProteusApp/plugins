---
title: 1. A first shader
section: Learning shaders
order: 301
keywords: first shader hello colour fragcolor gl_fragcoord resolution uv coordinates time animation circle beginner
---

# 1. A first shader

This chapter builds five small shaders. The first paints every pixel orange, and the last draws a sun that sets into the sea. On the way it covers the three things every fragment shader works from: its colour output, its position and the time.

## One colour

Start a new shader with **File > New GLSL Shader**, select all its code, and paste this over it:

```glsl
#version 300 es
precision highp float;

out vec4 fragColor;

void main() {
  fragColor = vec4(1.0, 0.5, 0.0, 1.0);
}
```

The Preview turns orange. Here is what each line does:

- `#version 300 es` says which GLSL this is: the version that WebGL 2 runs. It must be the first line.
- `precision highp float;` asks for full-precision numbers.
- `out vec4 fragColor;` declares the shader's output, the colour of the pixel.
- `void main()` is the function the graphics card runs for each pixel.
- `fragColor = vec4(1.0, 0.5, 0.0, 1.0);` sets that colour.

A colour is four numbers: red, green, blue and alpha. Each one runs from 0 to 1, not 0 to 255.

So `vec4(1.0, 0.5, 0.0, 1.0)` is full red, half green and no blue, which makes orange. Alpha is how solid the pixel is, and the Preview always shows it as solid.

**Write `1.0`, not `1`.** In GLSL, `1` is a whole number and `1.0` is a decimal number, and the two do not mix. `vec4(1, 0.5, 0, 1)` happens to work, but `0.5 * 2` is an error.

## The short form

The Shader Builder fills in the first three lines when a shader leaves out `#version`. This is the same shader:

```glsl
void main() {
  fragColor = vec4(1.0, 0.5, 0.0, 1.0);
}
```

From here on, the examples use the short form. The Shader Builder also declares the values the Preview sets, such as `u_time` and `u_resolution`, as soon as the code uses them. The table in [Learning shaders](learn-shaders.md#running-the-examples) lists them.

A shader meant for another program needs the full header back, and **Build Shader** writes it out in full.

## Where is this pixel?

Every pixel runs the same code, so the code needs to know which pixel it is running for. `gl_FragCoord.xy` holds the pixel's position, counted in pixels from the bottom left corner. Dividing it by the picture's size turns it into a number from 0 to 1 across the picture, whatever its size.

```glsl
void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  fragColor = vec4(uv.x, uv.y, 0.0, 1.0);
}
```

The picture is black at the bottom left, red at the bottom right, green at the top left and yellow at the top right. Red is `uv.x`, so it grows from left to right, and green is `uv.y`, so it grows upward. Where both are high, red and green light add up to yellow.

Showing a value as a colour is the main way to see what a shader is doing, and [When a shader goes wrong](debugging.md) builds on it.

The name `uv` is a habit from 3D graphics, where `u` and `v` are the two directions across a surface. It means the same as `x` and `y` here.

## A circle

A circle is every point within a set distance of its centre. So each pixel measures its distance to the centre and picks a colour from the answer.

```glsl
void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  float d = distance(uv, vec2(0.5, 0.5));
  vec3 color = vec3(0.1, 0.1, 0.2);
  if (d < 0.3) {
    color = vec3(1.0, 0.8, 0.2);
  }
  fragColor = vec4(color, 1.0);
}
```

The circle comes out stretched into an oval. The picture is wider than it is tall, but `uv` runs from 0 to 1 both ways, so a step in `x` covers more pixels than a step in `y`. The fix is to divide both by the same number, the height:

```glsl
void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  float d = length(p);
  vec3 color = vec3(0.1, 0.1, 0.2);
  if (d < 0.3) {
    color = vec3(1.0, 0.8, 0.2);
  }
  fragColor = vec4(color, 1.0);
}
```

Subtracting half the size first moves 0 to the middle of the picture. Now `p.y` runs from -0.5 at the bottom to 0.5 at the top, and `p.x` runs a little further each way on a wide picture.

`length(p)` is the distance from the middle, so the circle is round at any size. Most shaders start with the line that sets `p`.

## Movement

`u_time` is the number of seconds since the Preview started. A value that depends on it changes every frame. `sin` turns a steadily growing number into one that swings between -1 and 1, which suits anything that goes back and forth.

```glsl
void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  vec2 center = vec2(0.4 * sin(u_time), 0.0);
  float radius = 0.2 + 0.05 * sin(u_time * 3.0);
  float d = length(p - center);
  vec3 color = vec3(0.1, 0.1, 0.2);
  if (d < radius) {
    color = vec3(1.0, 0.8, 0.2);
  }
  fragColor = vec4(color, 1.0);
}
```

The circle slides from side to side and breathes in and out. Multiplying the time makes a change faster, as `u_time * 3.0` does for the radius. Multiplying the result of `sin` makes it bigger, as `0.4 *` does for the slide.

## A sunset

This one puts the pieces together. It also uses `mix`, which blends two colours. `mix(a, b, 0.0)` is `a`, `mix(a, b, 1.0)` is `b`, and the numbers in between blend.

```glsl
void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;

  // The sky fades from orange at the bottom to blue at the top.
  vec3 color = mix(vec3(1.0, 0.6, 0.3), vec3(0.2, 0.4, 0.8), uv.y);

  // The sun sinks and rises again every few seconds.
  vec2 sun = vec2(0.0, 0.25 * sin(u_time * 0.5));
  if (length(p - sun) < 0.12) {
    color = vec3(1.0, 0.9, 0.6);
  }

  // Below the horizon is the sea, painted last so it covers the sun.
  if (p.y < -0.1) {
    color = vec3(0.05, 0.15, 0.3);
  }

  fragColor = vec4(color, 1.0);
}
```

Order matters, because each step can paint over the one before it. The sea is painted last, so it hides the sun as it sets. Painting a picture in layers from back to front is how almost every shader in this course works.

## Try this

- Make the sea move: change `-0.1` to `-0.1 + 0.01 * sin(p.x * 40.0 + u_time)`.
- Make the sky darker as the sun goes down. Multiply `color` by a number that depends on `sun.y`, before the sun is drawn.
- Draw a second, smaller sun, moving the other way.
- Replace `vec2(0.5, 0.5)` in the oval example with `u_mouse.xy / u_resolution`, then click on the picture.

Next: [The GLSL language](glsl-language.md).
