---
title: From GLSL to WGSL
section: Learning shaders
order: 314
keywords: wgsl webgpu port convert glsl to wgsl f32 vec3f let var fn struct uniforms binding fragment entry point select atan2 mod differences
---

# From GLSL to WGSL

WGSL is the shading language of WebGPU, the newer graphics interface in browsers. The Shader Builder runs `.wgsl` files on WebGPU, and the Preview can show a node graph in either language.

The ideas in this course carry over unchanged, and only the spelling differs. This page lists the differences, then turns two shaders from the course into WGSL.

WGSL needs a computer and browser engine with WebGPU. Where it is missing, the Preview says so, and GLSL still works. The [WGSL specification](https://www.w3.org/TR/WGSL/) is the full reference, and [WebGPU Fundamentals](https://webgpufundamentals.org/) teaches WebGPU from the start.

## A WGSL shader in the Shader Builder

A WGSL file holds a fragment entry point, a function marked `@fragment` that returns the pixel's colour. Its uniforms live in one struct called `Uniforms`, bound at group 0 and binding 0.

The Preview fills the fields named `resolution`, `time`, `frame` and `mouse` every frame, as it fills the `u_` uniforms in GLSL. Every other field gets a control, shaped by the same notes in its comment.

When a file has no vertex entry point, the Shader Builder adds one at its end. It draws one triangle over the picture, so the fragment entry point runs for every pixel.

```wgsl
struct Uniforms {
  resolution: vec2f,
  time: f32,
  frame: f32,
  mouse: vec4f,
  speed: f32, // @range 0 4 @default 1
  rings: f32, // @range 1 20 @step 1 @default 8
  tint: vec3f, // @color @default 0.3 0.6 1.0
}

@group(0) @binding(0) var<uniform> u: Uniforms;

@fragment
fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  // WebGPU counts y down from the top, so flip it to match GLSL.
  let frag = vec2f(position.x, u.resolution.y - position.y);
  let p = (frag - 0.5 * u.resolution) / u.resolution.y;
  let wave = 0.5 + 0.5 * sin(length(p) * u.rings * 6.2831853 - u.time * u.speed * 3.0);
  return vec4f(u.tint * wave, 1.0);
}
```

This is the slider shader from [The GLSL language](glsl-language.md#uniforms-and-sliders), line for line. **Flip `y` first.** WebGPU's pixel position counts down from the top, the other way from `gl_FragCoord`, so every shader in this course comes out upside down without the flip.

## The differences

| GLSL | WGSL |
|------|------|
| `float`, `int`, `bool` | `f32`, `i32`, `bool` |
| `vec2`, `vec3`, `vec4` | `vec2f`, `vec3f`, `vec4f` |
| `mat2`, `mat3` | `mat2x2f`, `mat3x3f` |
| `float x = 1.0;` | `var x = 1.0;` for a value that changes, `let x = 1.0;` for one that does not |
| `const float PI = 3.14159;` | `const PI = 3.14159;` |
| `float f(vec2 p) { ... }` | `fn f(p: vec2f) -> f32 { ... }` |
| `for (int i = 0; i < 5; i++)` | `for (var i = 0; i < 5; i++)` |
| `float(i)` | `f32(i)` |
| `a ? b : c` | `select(c, b, a)`. Note the order: the value when false comes first. |
| `atan(y, x)` | `atan2(y, x)` |
| `mod(x, y)` | `x - y * floor(x / y)`. WGSL's `%` differs from `mod` for negative numbers. |
| `uniform float u_speed;` | A field `speed: f32` in `struct Uniforms`, read as `u.speed` |
| `gl_FragCoord.xy` | `@builtin(position)`, with `y` flipped |
| `fragColor = c;` | `return c;` from the `@fragment` function |
| A variable outside every function | `var<private> name: Type;` |

Most built-in functions keep their names: `sin`, `cos`, `fract`, `floor`, `mix`, `step`, `smoothstep`, `clamp`, `length`, `distance`, `dot`, `cross`, `normalize`, `reflect`, `pow`, `exp` and `sqrt` all work as before. Swizzles such as `p.xy` and `color.rgb` work too.

WGSL is stricter about types than GLSL, but in one way easier. A plain number such as `2` takes whatever type it is used with, so `2 * x` works when `x` is an `f32`. Two named values of different types still never mix.

## Clouds in WGSL

This is [Clouds in 2D](noise.md#clouds-in-2d) in WGSL. It shows functions, a loop, a matrix and a `var` that changes inside the loop.

```wgsl
struct Uniforms {
  resolution: vec2f,
  time: f32,
  frame: f32,
  mouse: vec4f,
  cover: f32, // @range 0 1 @default 0.5
  wind: f32, // @range 0 1 @default 0.15
  dark: f32, // @range 0 1 @default 0.2
}

@group(0) @binding(0) var<uniform> u: Uniforms;

fn hash(p: vec2f) -> f32 {
  var p3 = fract(vec3f(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

fn noise(p: vec2f) -> f32 {
  let i = floor(p);
  let f = fract(p);
  let s = f * f * (3.0 - 2.0 * f);
  let a = hash(i);
  let b = hash(i + vec2f(1.0, 0.0));
  let c = hash(i + vec2f(0.0, 1.0));
  let d = hash(i + vec2f(1.0, 1.0));
  return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

fn fbm(start: vec2f) -> f32 {
  var p = start;
  var sum = 0.0;
  var amplitude = 0.5;
  for (var i = 0; i < 6; i++) {
    sum += amplitude * noise(p);
    p = mat2x2f(1.6, 1.2, -1.2, 1.6) * p;
    amplitude *= 0.5;
  }
  return sum / 0.984375;
}

@fragment
fn fs_main(@builtin(position) position: vec4f) -> @location(0) vec4f {
  let frag = vec2f(position.x, u.resolution.y - position.y);
  let uv = frag / u.resolution;
  let p = frag / u.resolution.y * vec2f(2.0, 3.5) + vec2f(u.time * u.wind, 0.0);

  let sky = mix(vec3f(0.6, 0.75, 0.95), vec3f(0.2, 0.4, 0.8), uv.y);
  let n = fbm(p);
  let edge = mix(0.75, 0.3, u.cover);
  let c = smoothstep(edge, edge + 0.3, n);
  let toward = fbm(p + vec2f(0.05, 0.08));
  let shade = clamp(0.65 + (n - toward) * 5.0, 0.0, 1.0);
  let lit = mix(vec3f(0.95, 0.97, 1.0), vec3f(0.35, 0.38, 0.45), u.dark);
  let cloudColor = lit * mix(0.55, 1.05, shade);

  return vec4f(mix(sky, cloudColor, c), 1.0);
}
```

A function's inputs cannot change in WGSL, so `fbm` copies `start` into a `var p` before the loop moves it. That is the most common surprise when turning GLSL into WGSL.

## Graphs in both languages

A node graph writes both languages from the same nodes. **Show the Generated Code** (**Ctrl+Shift+C**) opens the Code panel, with a tab for the GLSL and a tab for the WGSL. Switching between them is a quick way to learn WGSL's spelling for anything in [Shaders as node graphs](node-graphs.md).

**Build Shader** writes both, ready to use elsewhere.

Next: [Further reading](resources.md).
