---
title: 7. Colour
section: Learning shaders
order: 307
keywords: colour color rgb gradient hsv hue saturation palette cosine palette layer blend alpha over add multiply gamma linear tone mapping exposure luminance desaturate grade
---

# 7. Colour

A colour in a shader is three amounts of light: red, green and blue. That makes colour maths simple, since adding two colours adds their light and multiplying tints one by the other. It also hides two traps, the screen's gamma and colours brighter than white, and this chapter covers both.

## Adding and multiplying

The two ways to combine colours behave like light:

- **Adding** is two lights shining on the same spot. Red plus green is yellow. Glows, the sun and lightning are added, so they brighten what is under them.
- **Multiplying** is light passing through a filter, or falling on a surface. White light times a red surface is red. Shadows, fog tints and dark storm light are multiplied, so they darken or tint what is under them.

`mix` is the third way. It replaces one colour with another by an amount, the way paint covers paint.

## Gradients

`mix` between two colours by a position makes a gradient. More colours need more steps, and `smoothstep` gives each step its own range:

```glsl
void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec3 color = vec3(0.95, 0.55, 0.3);
  color = mix(color, vec3(0.95, 0.8, 0.6), smoothstep(0.0, 0.25, uv.y));
  color = mix(color, vec3(0.45, 0.65, 0.95), smoothstep(0.2, 0.6, uv.y));
  color = mix(color, vec3(0.1, 0.2, 0.5), smoothstep(0.55, 1.0, uv.y));
  fragColor = vec4(color, 1.0);
}
```

Each `mix` lays a new colour over the last one, starting at its own height. This is a dawn sky, and the weather sky in [A weather system](weather.md#the-sky) starts from the same idea.

## Hue, saturation and value

Picking a colour by its red, green and blue is awkward for some jobs. HSV describes it another way: hue is the place on the colour wheel, saturation is how strong the colour is, and value is how bright. This function from Inigo Quilez turns HSV into RGB:

```glsl
vec3 hsv2rgb(vec3 c) {
  vec3 rgb = clamp(abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0, 0.0, 1.0);
  return c.z * mix(vec3(1.0), rgb, c.y);
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  // Hue runs across the picture, and saturation up it.
  vec3 color = hsv2rgb(vec3(uv.x + u_time * 0.05, uv.y, 1.0));
  fragColor = vec4(color, 1.0);
}
```

Hue suits anything that should cycle through colours. Each cell of a grid can get `hsv2rgb(vec3(random, 0.6, 0.9))`, and every cell gets a different colour of the same strength.

## Cosine palettes

A palette is a smooth run of colours from one number. Inigo Quilez's [cosine palettes](https://iquilezles.org/articles/palettes/) make one from four `vec3` values, `a`, `b`, `c` and `d`, with one line of code. Each channel is a wave: `a` sets its middle, `b` how far it swings, `c` how fast, and `d` where it starts.

```glsl
uniform vec3 u_a; // @default 0.5 0.5 0.5
uniform vec3 u_b; // @default 0.5 0.5 0.5
uniform vec3 u_c; // @range 0 2 @default 1 1 1
uniform vec3 u_d; // @default 0 0.33 0.67

vec3 palette(float t) {
  return u_a + u_b * cos(6.2831853 * (u_c * t + u_d));
}

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec3 color = palette(uv.x + u_time * 0.1);
  fragColor = vec4(color, 1.0);
}
```

Move the twelve sliders to find a palette, then copy the numbers into the code. The `shadertoy.frag` example in `shaders/` uses one, and the **Cosine Palette** node in the node editor is the same function.

## Layers

Most pictures are drawn as layers, back to front. A layer has a colour and an amount, often called alpha, from 0 to 1.

`mix(color, layer, amount)` lays it on. The amount usually comes from a shape's soft edge, as in [Shapes from distance](shapes.md#soft-edges).

Order decides what covers what. The sky comes first, then far things, then near things, then anything that glows, then the rain in front of it all.

## Gamma

A screen does not show a value of 0.5 as half the light. It shows about a fifth, because screens follow a curve close to `pow(value, 2.2)`. Colours picked by eye already allow for this, but light worked out with maths, from distances, angles or fog, does not.

So shaders that do lighting work in amounts of light, and convert once at the very end:

```glsl
void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  // A lamp's light falls off with distance. These are amounts of light.
  float d = length(vec2(p.x, fract(uv.y * 2.0) - 0.5));
  vec3 light = vec3(1.0, 0.8, 0.6) / (1.0 + 40.0 * d * d);
  // The bottom half sends the amounts to the screen as they are.
  // The top half converts them with the gamma step first.
  vec3 color = uv.y > 0.5 ? pow(light, vec3(1.0 / 2.2)) : light;
  fragColor = vec4(color, 1.0);
}
```

The lamp at the bottom looks small and harsh, with a hard dark edge. The top one has the soft spread of real light.

The difference is `pow(color, vec3(1.0 / 2.2))`, the last step of every lit shader from [Light, shadow and fog](lighting.md) on. Two rules follow from it:

- Do the lighting maths in amounts of light, and apply the gamma step once, at the end.
- Convert a colour picked by eye the other way, with `pow(color, vec3(2.2))`, before using it in lighting maths. For flat 2D pictures this rarely matters.

## Brighter than white

The sun is many times brighter than the sky, and lightning brighter still. In amounts of light, values far above 1 are normal. The screen clips them all to 1, so every bright thing turns into the same flat white blob, and colours wash out where they clip.

Tone mapping squeezes any amount of light into 0 to 1, keeping the order. `1.0 - exp(-color)` is a simple version: small values pass almost unchanged, and huge ones approach 1 without reaching it. Exposure multiplies the light before it, the way a camera lets in more or less light.

## Grading a scene

This shader runs the steps a picture goes through after the scene is lit. It scales by exposure, tone maps, adjusts saturation, and applies gamma. The sun's disc is 20 times brighter than white.

```glsl
uniform float u_exposure; // @range 0.1 4 @default 1.5
uniform float u_saturation; // @range 0 1.5 @default 1
uniform float u_tonemap; // @range 0 1 @step 1 @default 1

void main() {
  vec2 uv = gl_FragCoord.xy / u_resolution;
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;

  // The scene, in amounts of light.
  vec3 sky = mix(vec3(0.9, 0.45, 0.2), vec3(0.08, 0.15, 0.45), pow(uv.y, 0.5));
  float d = length(p - vec2(0.2, 0.0));
  vec3 color = sky + vec3(1.0, 0.6, 0.3) * exp(-d * 8.0);
  color += vec3(20.0, 16.0, 10.0) * smoothstep(0.06, 0.055, d);
  if (p.y < -0.15) {
    color = vec3(0.02, 0.025, 0.03);
  }

  color *= u_exposure;
  if (u_tonemap > 0.5) {
    color = 1.0 - exp(-color);
  }
  // Luminance is how bright a colour looks. Green looks brightest and blue darkest.
  float luminance = dot(color, vec3(0.2126, 0.7152, 0.0722));
  color = mix(vec3(luminance), color, u_saturation);
  color = pow(clamp(color, 0.0, 1.0), vec3(1.0 / 2.2));

  fragColor = vec4(color, 1.0);
}
```

Turn `u_tonemap` off and raise the exposure. The sun's glow clips into flat bands of yellow and white. With it on, the glow stays smooth at any exposure.

Lower the saturation to about 0.4, and the evening turns grey and heavy, as it does before a storm. [A weather system](weather.md#the-weather-dial) does the same.

## Try this

- Add a fourth stop to the dawn gradient, a thin bright band just above the horizon.
- Find a cosine palette for fire and one for the sea, and note their numbers.
- In the grading shader, add `u_warmth` that multiplies the colour by `vec3(1.0 + u_warmth, 1.0, 1.0 - u_warmth)` before tone mapping.
- Add a vignette, a darkening toward the corners: multiply by `1.0 - 0.5 * dot(p, p)`.

Next: [Randomness and noise](noise.md).
