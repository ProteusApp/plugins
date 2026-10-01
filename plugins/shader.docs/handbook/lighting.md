---
title: 10. Light, shadow and fog
section: Learning shaders
order: 310
keywords: lighting light diffuse lambert ambient sky light hemisphere shadow soft shadow ambient occlusion specular shine highlight sky gradient sun disc time of day sunset fog haze distance tone mapping gamma material
---

# 10. Light, shadow and fog

[3D with ray marching](raymarching.md) found surfaces and lit them with one rule. Real light comes from two places, the sun and the whole sky. It casts shadows, gathers less in corners, shines off smooth surfaces and fades into the air with distance.

This chapter adds each of those, and ends with a scene whose sun can be moved from noon to night.

## Light from the sun

How much of the sun's light falls on a surface is `max(dot(n, sunDir), 0.0)`, where `n` is the surface's normal and `sunDir` points toward the sun. A surface facing the sun gets full light, and one turned away gets none. This is called diffuse light, the soft light of a matte surface.

The sun has a colour too, and at noon it is near white. Near the horizon its light passes through much more air, which takes out the blue, so it turns orange and red. A sun colour that depends on the sun's height does most of the work of a sunset:

```glsl
vec3 sunColor(vec3 sunDir) {
  vec3 low = vec3(1.0, 0.4, 0.15);
  vec3 high = vec3(1.0, 0.95, 0.85);
  // Fades out as the sun sets, so the scene goes dark at night.
  return mix(low, high, smoothstep(0.0, 0.4, sunDir.y)) * 3.0 * smoothstep(-0.05, 0.05, sunDir.y);
}
```

The `3.0` makes the sun's light several times brighter than the sky's, whose amounts stay below about 1. These are amounts of light, as in [Colour](colour.md#gamma), and tone mapping brings them back to the screen at the end.

## Light from the sky

A surface in shadow is not black, because the whole blue sky lights it. Surfaces that face up see more of the sky than surfaces that face sideways, and `0.5 + 0.5 * n.y` measures that: 1 facing straight up, 0.5 facing sideways, 0 facing down. Multiply it by the sky's colour, and shadows turn a soft blue, as they do outdoors.

## Shadows

A point is in shadow when something stands between it and the sun. To find out, march a second ray from the point toward the sun. If it hits anything, the point is in shadow.

```glsl
float shadow = march(pos + n * 0.002, sunDir) > 0.0 ? 0.0 : 1.0;
```

The ray starts a hair above the surface, `n * 0.002`, or it would hit the surface it starts on at once. This gives hard shadows with sharp edges. Real shadows soften with distance from what casts them.

Inigo Quilez found a way to get [soft shadows](https://iquilezles.org/articles/rmshadows/) almost for free. While the ray marches toward the sun, the shader keeps track of how closely it passes surfaces, compared with how far it has gone. A ray that only just misses an edge is in the soft edge of the shadow.

```glsl
float softShadow(vec3 ro, vec3 rd, float k) {
  float result = 1.0;
  float t = 0.02;
  for (int i = 0; i < 64; i++) {
    float h = map(ro + rd * t).x;
    result = min(result, k * h / t);
    t += clamp(h, 0.02, 0.25);
    if (result < 0.001 || t > 10.0) break;
  }
  return clamp(result, 0.0, 1.0);
}
```

`k` sets how sharp the shadow is. 32 gives a crisp edge, as on a clear day. 4 gives a wide, soft one, as under a hazy sky.

## Corners

Less light reaches into corners, creases and the gaps under things. This darkening is called ambient occlusion.

A cheap way to find it is to take a few small steps out from the surface, along the normal. In open space each step's distance equals how far it went. Near another surface it is smaller, and the shortfall says how hemmed in the point is.

```glsl
float occlusion(vec3 p, vec3 n) {
  float occ = 0.0;
  float weight = 1.0;
  for (int i = 1; i <= 5; i++) {
    float h = 0.03 + 0.06 * float(i);
    occ += (h - map(p + n * h).x) * weight;
    weight *= 0.7;
  }
  return clamp(1.0 - 1.5 * occ, 0.0, 1.0);
}
```

Occlusion only darkens the sky's light, not the sun's. The sun's light already has its own shadow.

## Shine

A smooth surface also reflects the sun as a bright spot, the highlight. It is brightest where the surface is turned halfway between the eye and the sun. The direction halfway between the two is `normalize(sunDir - rd)`, and how closely the normal matches it gives the highlight:

```glsl
vec3 halfway = normalize(sunDir - rd);
float shine = pow(max(dot(n, halfway), 0.0), 48.0);
```

A high power such as 48 makes a small, sharp highlight, like polished plastic. A low one such as 8 spreads it wide, like a dull surface.

## The sky

A ray that hits nothing shows the sky. The sky's colour depends on how high the ray points: pale near the horizon, where the light passes through the most air, and deeper blue overhead.

The sky's colour also depends on the sun. Near sunset the horizon on the sun's side glows orange, and at night everything fades to dark blue.

The sun itself is a disc where the ray points almost straight at it. `dot(rd, sunDir)` is 1 there, so a `smoothstep` between 0.9995 and 0.9998 draws a small disc. A `pow` of the same `dot` gives the glow around it.

## Fog

Air is not perfectly clear. Over distance, it hides what is behind it and shows its own colour instead. The fraction that gets through falls off as `exp(-distance * density)`, the curve from [Shaping values](shaping.md#pow-sqrt-and-exp-curves):

```glsl
float fogAmount = 1.0 - exp(-t * u_fog);
color = mix(color, fogColor, fogAmount);
```

The fog's colour should be the sky's colour at the horizon in the same direction, so faraway things fade smoothly into the sky behind them. Near the sun, fog glows warm, because it scatters the sun's light toward the eye.

## A sun from noon to night

This shader uses all of it. Drag `u_sun` from high to low and past the horizon.

The light turns gold, the shadows stretch, the sky glows and darkens, and the scene goes to night. `u_fog` thickens the air.

```glsl
uniform float u_sun; // @range -0.2 1.4 @default 0.6
uniform float u_fog; // @range 0 0.15 @default 0.03

float sdBox(vec3 p, vec3 b) {
  vec3 q = abs(p) - b;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

// The distance to the nearest surface in x, and which surface it is in y: 1 for the shapes
// and 2 for the ground.
vec2 map(vec3 p) {
  float ball = length(p - vec3(0.0, 1.0, 0.0)) - 0.6;
  float box = sdBox(p - vec3(0.0, 0.4, 0.0), vec3(0.5, 0.4, 0.5)) - 0.05;
  float pillar = sdBox(p - vec3(-1.6, 1.0, -1.2), vec3(0.2, 1.0, 0.2)) - 0.02;
  float shapes = min(smin(ball, box, 0.3), pillar);
  return shapes < p.y ? vec2(shapes, 1.0) : vec2(p.y, 2.0);
}

vec3 normalAt(vec3 p) {
  vec2 e = vec2(0.001, 0.0);
  return normalize(vec3(
    map(p + e.xyy).x - map(p - e.xyy).x,
    map(p + e.yxy).x - map(p - e.yxy).x,
    map(p + e.yyx).x - map(p - e.yyx).x));
}

vec2 march(vec3 ro, vec3 rd) {
  float t = 0.0;
  for (int i = 0; i < 160; i++) {
    vec2 h = map(ro + rd * t);
    if (h.x < 0.001) return vec2(t, h.y);
    t += h.x;
    if (t > 60.0) break;
  }
  return vec2(-1.0, 0.0);
}

float softShadow(vec3 ro, vec3 rd, float k) {
  float result = 1.0;
  float t = 0.02;
  for (int i = 0; i < 64; i++) {
    float h = map(ro + rd * t).x;
    result = min(result, k * h / t);
    t += clamp(h, 0.02, 0.25);
    if (result < 0.001 || t > 10.0) break;
  }
  return clamp(result, 0.0, 1.0);
}

float occlusion(vec3 p, vec3 n) {
  float occ = 0.0;
  float weight = 1.0;
  for (int i = 1; i <= 5; i++) {
    float h = 0.03 + 0.06 * float(i);
    occ += (h - map(p + n * h).x) * weight;
    weight *= 0.7;
  }
  return clamp(1.0 - 1.5 * occ, 0.0, 1.0);
}

vec3 sunColor(vec3 sunDir) {
  vec3 low = vec3(1.0, 0.4, 0.15);
  vec3 high = vec3(1.0, 0.95, 0.85);
  return mix(low, high, smoothstep(0.0, 0.4, sunDir.y)) * 3.0 * smoothstep(-0.05, 0.05, sunDir.y);
}

// The sky in one direction, without the sun's disc. Amounts of light, not screen colours.
vec3 sky(vec3 rd, vec3 sunDir) {
  float up = clamp(rd.y, 0.0, 1.0);
  float day = smoothstep(-0.1, 0.3, sunDir.y);
  float toward = max(dot(rd, sunDir), 0.0);
  vec3 dayColor = mix(vec3(0.3, 0.48, 0.8), vec3(0.02, 0.09, 0.45), pow(up, 0.5));
  vec3 duskColor = mix(mix(vec3(0.35, 0.15, 0.15), vec3(1.2, 0.35, 0.08), pow(toward, 3.0)),
                       vec3(0.02, 0.03, 0.12), pow(up, 0.4));
  vec3 color = mix(duskColor, dayColor, day);
  // Night: everything fades to a dim blue.
  color = mix(vec3(0.002, 0.004, 0.012), color, smoothstep(-0.2, 0.0, sunDir.y));
  color += sunColor(sunDir) * pow(toward, 12.0) * 0.15;
  return color;
}

vec3 cameraRay(vec3 ro, vec3 target, vec2 p, float zoom) {
  vec3 forward = normalize(target - ro);
  vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
  vec3 up = cross(forward, right);
  return normalize(p.x * right + p.y * up + zoom * forward);
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  vec3 sunDir = normalize(vec3(-0.78 * cos(u_sun), sin(u_sun), 0.6 * cos(u_sun)));
  vec3 sunLight = sunColor(sunDir);

  vec3 ro = vec3(3.0, 1.6, 4.0);
  vec3 rd = cameraRay(ro, vec3(-0.4, 0.7, 0.0), p, 1.6);

  vec3 color = sky(rd, sunDir);
  color += sunLight * smoothstep(0.9995, 0.9998, dot(rd, sunDir)) * 10.0;

  vec2 hit = march(ro, rd);
  if (hit.x > 0.0) {
    float t = hit.x;
    vec3 pos = ro + rd * t;
    vec3 n = normalAt(pos);

    vec3 albedo = vec3(0.6, 0.25, 0.1);
    if (hit.y > 1.5) {
      float check = mod(floor(pos.x) + floor(pos.z), 2.0);
      albedo = mix(vec3(0.16), vec3(0.07), check);
    }

    float diffuse = max(dot(n, sunDir), 0.0) * softShadow(pos + n * 0.002, sunDir, 12.0);
    float skyLight = (0.5 + 0.5 * n.y) * occlusion(pos, n);
    vec3 light = sunLight * diffuse + sky(vec3(0.0, 1.0, 0.0), sunDir) * skyLight;
    vec3 surface = albedo * light;

    vec3 halfway = normalize(sunDir - rd);
    surface += sunLight * pow(max(dot(n, halfway), 0.0), 48.0) * diffuse * 0.3;

    // Fog takes the sky's colour at the horizon, in the same direction.
    vec3 fogColor = sky(normalize(vec3(rd.x, 0.0, rd.z)), sunDir);
    color = mix(surface, fogColor, 1.0 - exp(-t * u_fog));
  }

  color = 1.0 - exp(-color * 1.5);
  color = pow(color, vec3(1.0 / 2.2));
  fragColor = vec4(color, 1.0);
}
```

Three parts of the light make the picture: the sun with its shadow, the sky with its occlusion, and the highlight. Each one is a few lines. The order at the end matters as well: fog over the lit surface, then tone mapping, then gamma.

[A weather system](weather.md) uses this same sky and sun colour, with the sun's height set by the hour of the day.

## Try this

- Change the shadow's `k` from 12 to 3, then to 40, and watch the shadow under the pillar.
- Show each part alone: only the sun's light, only the sky's light, only the occlusion. Write each to `fragColor` and `return`.
- Give the ball a mirror finish. March a second ray along `reflect(rd, n)` and mix in what it sees.
- Make the fog thicker near the ground. Multiply the density by `exp(-pos.y)`.

Next: [Clouds and other volumes](volumes.md).
