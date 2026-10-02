---
title: 9. 3D with ray marching
section: Learning shaders
order: 309
keywords: ray marching raymarching sphere tracing 3d camera ray origin direction signed distance function sdf sphere box plane torus normal look at orbit mouse scene map steps
---

# 9. 3D with ray marching

A fragment shader only colours flat pixels, yet it can draw a 3D scene. Each pixel sends a ray from a camera into the scene, finds what the ray hits, and colours itself by that surface.

This chapter finds the hits with ray marching, which uses the distance functions from [Shapes from distance](shapes.md) in 3D. The weather shader draws its clouds this way too.

## A ray for each pixel

A ray is a starting point and a direction. All rays start at the camera, and each pixel picks its own direction:

- `ro`, the ray origin, is where the camera is.
- `rd`, the ray direction, points from the camera through the pixel.

The simplest camera sits at 0 and looks along `z`. The pixel's position gives the sideways and upward parts of the direction, and a fixed number gives the forward part. That number works like a zoom: larger means a narrower view.

```glsl
vec3 rd = normalize(vec3(p, 1.5));
```

A point along the ray is `ro + rd * t`, where `t` is how far along it is. Finding the hit means finding the `t` where the ray first meets a surface.

## Marching along the ray

A signed distance function in 3D says how far a point is from the nearest surface, in any direction. So a ray can safely move that far, since nothing is closer than that.

At the new point, the shader measures the distance again, and the ray moves again. Near a surface the steps grow tiny. When a step is smaller than a hair, the ray has hit.

```glsl
// The distance from p to the nearest surface: one sphere, three units ahead.
float map(vec3 p) {
  return length(p - vec3(0.0, 0.0, 3.0)) - 1.0;
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  vec3 ro = vec3(0.0);
  vec3 rd = normalize(vec3(p, 1.5));

  float t = 0.0;
  bool hit = false;
  for (int i = 0; i < 100; i++) {
    float d = map(ro + rd * t);
    if (d < 0.001) {
      hit = true;
      break;
    }
    t += d;
    if (t > 20.0) break;
  }

  // Nearer points are brighter. The sphere's front is 2 units away and its edge about 3.
  vec3 color = hit ? vec3(3.0 - t) : vec3(0.0);
  fragColor = vec4(color, 1.0);
}
```

The loop stops in one of three ways: it hits, it goes past 20 units and gives up, or it runs out of steps. Most rays that hit take 10 to 30 steps. Rays that skim past an edge take the most, since they keep passing close to the surface.

The sphere shows as a grey disc, brighter in the middle, where it is nearest. This way of marching is often called sphere tracing. Inigo Quilez's [ray marching distance fields](https://iquilezles.org/articles/raymarchingdf/) covers it in more depth.

## Shapes in 3D

The 2D distance functions have 3D versions that work the same way, and the ways of combining them carry over unchanged: `min`, `max` and `smin`. Inigo Quilez's [3D distance functions](https://iquilezles.org/articles/distfunctions/) lists dozens.

| Shape | Distance |
|-------|----------|
| Sphere | `length(p) - r` |
| Box, half size `b` | `length(max(abs(p) - b, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0)`, where `q = abs(p) - b` |
| Flat ground | `p.y`, the height above it |
| Torus | `length(vec2(length(p.xz) - R, p.y)) - r` |

Moving, turning and repeating work as in [Moving space](space.md). Subtract a position from `p` to move a shape. `mod` repeats one shape forever, across a whole field.

## Which way a surface faces

To light a surface, the shader needs its normal, the direction it faces. A distance function gives it for free.

The distance grows fastest straight out from the surface, so measuring how it changes along `x`, `y` and `z` gives the normal. Inigo Quilez's article on [normals for an SDF](https://iquilezles.org/articles/normalsSDF/) explains the maths.

```glsl
vec3 normalAt(vec3 p) {
  vec2 e = vec2(0.001, 0.0);
  return normalize(vec3(
    map(p + e.xyy) - map(p - e.xyy),
    map(p + e.yxy) - map(p - e.yxy),
    map(p + e.yyx) - map(p - e.yyx)));
}
```

With a normal and a direction toward the light, `dot` says how directly the light falls on the surface. 1 means straight on, and 0 or less means the light is edge-on or behind. This is the oldest lighting rule in graphics, and [Light, shadow and fog](lighting.md) builds on it.

## A camera that looks at a point

A camera that can move needs its own three directions: forward, right and up. Forward points from the camera to whatever it looks at.

`cross` gives right, the direction at right angles to forward and to the world's up. Up is at right angles to both.

```glsl
vec3 cameraRay(vec3 ro, vec3 target, vec2 p, float zoom) {
  vec3 forward = normalize(target - ro);
  vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
  vec3 up = cross(forward, right);
  return normalize(p.x * right + p.y * up + zoom * forward);
}
```

## A first scene

This shader puts it together: a ball melting into a rounded box, on flat ground, under a light. The camera circles the scene, and dragging on the picture turns it by hand.

```glsl
float sdBox(vec3 p, vec3 b) {
  vec3 q = abs(p) - b;
  return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

float map(vec3 p) {
  float ball = length(p - vec3(0.0, 1.0 + 0.3 * sin(u_time), 0.0)) - 0.6;
  float box = sdBox(p - vec3(0.0, 0.4, 0.0), vec3(0.5, 0.4, 0.5)) - 0.05;
  float shapes = smin(ball, box, 0.3);
  float ground = p.y;
  return min(shapes, ground);
}

vec3 normalAt(vec3 p) {
  vec2 e = vec2(0.001, 0.0);
  return normalize(vec3(
    map(p + e.xyy) - map(p - e.xyy),
    map(p + e.yxy) - map(p - e.yxy),
    map(p + e.yyx) - map(p - e.yyx)));
}

// How far along the ray the first surface is, or -1 when the ray hits nothing.
float march(vec3 ro, vec3 rd) {
  float t = 0.0;
  for (int i = 0; i < 128; i++) {
    float d = map(ro + rd * t);
    if (d < 0.001) return t;
    t += d;
    if (t > 40.0) break;
  }
  return -1.0;
}

vec3 cameraRay(vec3 ro, vec3 target, vec2 p, float zoom) {
  vec3 forward = normalize(target - ro);
  vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
  vec3 up = cross(forward, right);
  return normalize(p.x * right + p.y * up + zoom * forward);
}

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  // The camera circles the scene, or follows the mouse while a button is held.
  float angle = u_mouse.z > 0.0 ? u_mouse.x / u_resolution.x * 6.2831853 : u_time * 0.3;
  vec3 ro = vec3(4.0 * sin(angle), 2.0, 4.0 * cos(angle));
  vec3 rd = cameraRay(ro, vec3(0.0, 0.5, 0.0), p, 1.5);

  vec3 color = vec3(0.6, 0.75, 0.9) - rd.y * 0.3;
  float t = march(ro, rd);
  if (t > 0.0) {
    vec3 pos = ro + rd * t;
    vec3 n = normalAt(pos);
    vec3 light = normalize(vec3(0.6, 0.8, 0.4));
    float diffuse = max(dot(n, light), 0.0);
    color = vec3(0.9, 0.5, 0.3) * (0.2 + 0.8 * diffuse);
  }
  fragColor = vec4(color, 1.0);
}
```

The ground and the shapes share one colour, and nothing casts a shadow yet, so the ground under the box is lit as if the box were not there. [Light, shadow and fog](lighting.md) fixes both.

Everything in the picture comes from `map`. To change the scene, change `map` and nothing else. The whole scene is one function, so any shape that has a distance can go in it.

## Try this

- Keep a count of the steps in a variable during the march, and show it as grey, divided by 128. Edges, where rays skim past, take the most.
- Add a torus around the ball, and a second ball that orbits the first.
- Repeat the ball forever: in `map`, use `mod(p.xz + 2.0, 4.0) - 2.0` in place of `p.xz` for the ball.
- Compare with `shaders/raymarch.frag`, a larger version of this scene with shadows and a checked floor.

Next: [Light, shadow and fog](lighting.md).
