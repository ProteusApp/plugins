---
title: 6. Shapes from distance
section: Learning shaders
order: 306
keywords: signed distance function sdf 2d circle box rectangle line segment edge anti-aliasing antialias soft edge outline glow union intersection subtraction smooth minimum smin combine shapes cloud
---

# 6. Shapes from distance

The circles so far asked "is this pixel inside?" and got yes or no. A better question is "how far is this pixel from the edge?".

The answer gives clean edges, outlines and glows for free, and it lets shapes melt into one another. [3D with ray marching](raymarching.md) builds 3D on the same idea.

## Signed distance

A signed distance function takes a point and returns how far it is from a shape's edge. The value is negative inside the shape, positive outside, and 0 on the edge. For a circle it is one line: the distance from the centre, minus the radius.

The three below cover most needs. They come from Inigo Quilez's list of [2D distance functions](https://iquilezles.org/articles/distfunctions2d/), which has dozens more, each with a live example.

```glsl
uniform float u_shape; // @range 0 2 @step 1 @default 0

float sdCircle(vec2 p, float r) {
  return length(p) - r;
}

// A box with half its width and half its height in b.
float sdBox(vec2 p, vec2 b) {
  vec2 d = abs(p) - b;
  return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// A line from a to b. Subtract a thickness to give it width.
float sdSegment(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

vec3 showValue(float v) {
  vec3 color = v > 0.0 ? vec3(0.9, 0.6, 0.3) : vec3(0.4, 0.7, 0.9);
  color *= 0.8 + 0.2 * cos(v * 62.83);
  color = mix(color, vec3(1.0), 1.0 - smoothstep(0.0, 0.01, abs(v)));
  return color;
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  float d = sdCircle(p, 0.3);
  if (u_shape > 0.5) d = sdBox(p, vec2(0.35, 0.2));
  if (u_shape > 1.5) d = sdSegment(p, vec2(-0.3, -0.2), vec2(0.3, 0.2)) - 0.05;
  fragColor = vec4(showValue(d), 1.0);
}
```

The slider picks a shape, and `showValue` from [When a shader goes wrong](debugging.md#showing-a-value-as-colour) draws its distances. The white line is the edge. The bands mark every 0.1 of distance from the edge, with blue inside the shape.

For the box, `abs(p)` folds the picture into one corner, as in [Moving space](space.md#mirrors), so the code only handles one quarter of the box. `d` is how far the point is past the box's sides.

Outside, `length(max(d, 0.0))` is the distance to the nearest side or corner. Inside, `min(max(d.x, d.y), 0.0)` is minus the distance to the nearest side.

## Soft edges

Filling a shape with `d < 0.0` gives a hard edge, which looks jagged on slanted lines and shimmers as the shape moves. The fix is a soft step across the edge, one pixel either side of it. A pixel is `1.0 / u_resolution.y` in the units of `p`.

```glsl
float sdCircle(vec2 p, float r) {
  return length(p) - r;
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  float px = 1.0 / u_resolution.y;
  float d = sdCircle(p - vec2(0.3 * sin(u_time), 0.0), 0.25);

  vec3 color = vec3(0.1, 0.12, 0.18);
  // The fill fades from 1 to 0 across one pixel either side of the edge.
  float fill = smoothstep(px, -px, d);
  color = mix(color, vec3(0.95, 0.6, 0.25), fill);
  fragColor = vec4(color, 1.0);
}
```

Making the edge smooth like this is called anti-aliasing. Replace `smoothstep(px, -px, d)` with `step(d, 0.0)`, a hard edge, and compare.

GLSL also has `fwidth(d)`, which measures how much `d` changes from one pixel to the next. Using it in place of `px` keeps the edge sharp even after the coordinates are scaled.

## Outlines, rounding and glows

With a distance, these become one line each:

| Effect | Code | Why it works |
|--------|------|--------------|
| Outline | `abs(d) - 0.01` | The distance to the edge itself, so a thin band either side of it counts as inside. |
| Rounded corners | `d - 0.05` | Every distance shrinks, so the edge moves outward and every corner rounds. |
| Hollow shape | `max(d, -(d + 0.05))` | Keeps the outside of a smaller copy of the shape. |
| Glow | `exp(-max(d, 0.0) * 20.0)` | Bright at the edge and fading with distance, as in [Shaping values](shaping.md#pow-sqrt-and-exp-curves). |
| Shadow | the shape again, moved down and right, blurred with a wide `smoothstep` | A soft dark copy drawn first, under the shape. |

## Combining shapes

Two distances combine into one shape:

| Combination | Code |
|-------------|------|
| Both shapes together | `min(a, b)` |
| Only where they overlap | `max(a, b)` |
| The first shape with the second cut out | `max(a, -b)` |
| Both, melted together | `smin(a, b, k)` |

`min` takes whichever edge is nearer, so it keeps both shapes. `smin` is a smooth version of `min` from Inigo Quilez's article on the [smooth minimum](https://iquilezles.org/articles/smin/). Where the shapes come within `k` of each other, it blends their edges into one curve, like drops of water joining.

```glsl
uniform float u_melt; // @range 0 0.3 @default 0.1

float sdCircle(vec2 p, float r) {
  return length(p) - r;
}

float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  float px = 1.0 / u_resolution.y;
  float a = sdCircle(p - vec2(-0.2 + 0.1 * sin(u_time), 0.0), 0.18);
  float b = sdCircle(p - vec2(0.2, 0.0), 0.14);
  float d = smin(a, b, max(u_melt, 0.0001));
  vec3 color = mix(vec3(0.1, 0.12, 0.18), vec3(0.4, 0.75, 1.0), smoothstep(px, -px, d));
  fragColor = vec4(color, 1.0);
}
```

At `u_melt` 0 the two circles stay apart. Raise it and a bridge grows between them. `max(u_melt, 0.0001)` keeps `smin` from dividing by 0.

## A cartoon cloud

This shader joins five circles into a cloud with `smin` and cuts its base flat with `max`. Short line segments fall from it as rain, each one repeating with `fract` as in [Shaping values](shaping.md#fract-and-mod-repeating).

```glsl
uniform float u_puff; // @range 0.01 0.2 @default 0.08
uniform float u_rain; // @range 0 1 @default 1

float sdCircle(vec2 p, float r) {
  return length(p) - r;
}

float sdSegment(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

float cloud(vec2 p) {
  float d = sdCircle(p - vec2(-0.25, 0.0), 0.13);
  d = smin(d, sdCircle(p - vec2(-0.1, 0.09), 0.17), u_puff);
  d = smin(d, sdCircle(p - vec2(0.1, 0.12), 0.2), u_puff);
  d = smin(d, sdCircle(p - vec2(0.27, 0.02), 0.13), u_puff);
  d = smin(d, sdCircle(p - vec2(0.0, -0.02), 0.14), u_puff);
  // Keep only what is above the line y = -0.08, so the base is flat.
  return max(d, -(p.y + 0.08));
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  float px = 1.0 / u_resolution.y;
  p.y -= 0.12;

  vec3 color = mix(vec3(0.55, 0.75, 0.95), vec3(0.25, 0.45, 0.8), gl_FragCoord.y / u_resolution.y);

  // Each drop falls from the cloud's base, starting at its own time.
  for (int i = 0; i < 7; i++) {
    float fi = float(i);
    float x = -0.27 + fi * 0.09;
    float fall = fract(u_time * 0.9 + fi * 0.37);
    float y = -0.1 - fall * 0.5;
    float drop = sdSegment(p, vec2(x, y), vec2(x - 0.01, y + 0.05)) - 0.006;
    float fade = (1.0 - fall) * u_rain;
    color = mix(color, vec3(0.2, 0.35, 0.8), smoothstep(px, -px, drop) * fade);
  }

  float d = cloud(p);
  // The cloud is darker toward its base, with a soft grey outline.
  vec3 body = mix(vec3(0.8, 0.83, 0.9), vec3(1.0), smoothstep(-0.1, 0.25, p.y));
  color = mix(color, vec3(0.45, 0.5, 0.6), smoothstep(px, -px, d - 0.008));
  color = mix(color, body, smoothstep(px, -px, d));

  fragColor = vec4(color, 1.0);
}
```

The outline is the same cloud grown by 0.008 and drawn first in grey. The cloud itself, drawn on top, covers all but a thin rim of it. Drawing a shape twice like this is often simpler than working out the outline's own distance.

## Try this

- Raise `u_puff` until the cloud turns to one blob, then lower it until the circles show.
- Add a sun behind the cloud, half hidden. Draw it before the cloud, so the cloud covers it.
- Give the drops a round end: add `sdCircle` at the bottom of each segment with `min`.
- Build a lightning bolt from three `sdSegment` lines joined with `min`. [A weather system](weather.md#lightning) draws one this way.

Next: [Colour](colour.md).
