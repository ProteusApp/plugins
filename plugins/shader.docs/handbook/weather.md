---
title: 12. A weather system
section: Learning shaders
order: 312
keywords: weather system rain snow lightning storm clouds sky day night cycle time of day sun moon stars wind fog mist puddles wet ground ripples cloud shadows struct capstone project
---

# 12. A weather system

This chapter puts the whole course into one shader. One slider, `u_weather`, runs from a clear day through cloud and rain to a thunderstorm, and others set the hour, the wind, the cold and the mist. Every part uses something an earlier chapter taught, and this page walks through them in the order the shader runs.

The complete shader is at the end of the page, under [The whole shader](#the-whole-shader). The Shader Builder also copies it into `shaders/weather.frag` when it starts. Open it beside this page, and change things as each part is explained.

## The sliders

| Slider | What it does |
|--------|--------------|
| `u_weather` | 0 is a clear day. Cloud builds to about 0.6, rain starts near 0.6, and lightning comes in above 0.8. |
| `u_cold` | Above 0.5, rain falls as snow, and snow settles on the ground. |
| `u_wind` | How fast the clouds move, and how far rain slants and snow drifts. |
| `u_hour` | The time of day, from 0 to 24. The sun rises at 6 and sets at 18. |
| `u_cycle` | How many hours pass each second. At 2, a whole day takes 12 seconds. |
| `u_mist` | Thickens the air, so the hills and the ground fade. |

The shader builds the picture in this order:

1. Work out the weather from the sliders, once.
2. Send a ray from a camera on the ground, as in [3D with ray marching](raymarching.md).
3. A ray that points up sees the sky, the lightning bolt, the clouds and the hills, back to front.
4. A ray that points down sees the ground, with its puddles, snow and haze.
5. Rain and snow fall in front of everything.
6. Mist, tone mapping and gamma finish the picture, as in [Colour](colour.md).

## The weather dial

Every part of the shader reads the weather, so the shader works it out once, at the start, into one value. GLSL's `struct` groups several values under one name, the way a table groups fields. `Weather W;` declares a single one outside every function, so every function can read it.

```glsl
// Everything the sliders decide, worked out once per pixel and read by every part below.
struct Weather {
  float cover; // How much of the sky has cloud, from 0.2 to 1.
  float dark; // How thick and grey the clouds are, from 0 to 1.
  float rain; // How hard it rains, from 0 to 1.
  float snow; // How hard it snows, from 0 to 1.
  float storm; // How often lightning strikes, from 0 to 1.
  float haze; // How thick the air is.
  float wind; // How fast clouds, rain and snow move sideways.
  float night; // 0 by day and 1 at night.
  vec3 sunDir;
  vec3 sunColor;
  vec3 moonDir;
  float slot; // Which 2.5-second slot of time this is, for lightning.
  float flash; // How bright the lightning is right now.
  float boltX; // Where the bolt strikes across the picture, from -1 to 1.
  float boltAge; // Seconds since the strike began.
};

Weather W;
```

`setWeather` fills it in. Each weather value comes from `u_weather` through its own `smoothstep`, so each one wakes up over its own stretch of the dial. `u_cold` decides whether what falls is rain or snow, and the hour sets the sun and moon:

```glsl
void setWeather(float time) {
  float w = u_weather;
  W.cover = mix(0.2, 1.0, smoothstep(0.0, 0.65, w));
  W.dark = smoothstep(0.35, 0.95, w);
  float fall = smoothstep(0.55, 0.75, w);
  float cold = smoothstep(0.4, 0.6, u_cold);
  W.rain = fall * (1.0 - cold);
  W.snow = fall * cold;
  W.storm = smoothstep(0.8, 1.0, w) * (1.0 - cold);
  W.haze = 0.004 + 0.03 * smoothstep(0.4, 1.0, w) + 0.06 * u_mist;
  W.wind = u_wind * (1.0 + W.storm);

  // The sun rises at 6, is highest at 12 and sets at 18. The moon is always opposite it.
  float hour = mod(u_hour + time * u_cycle, 24.0);
  float a = (hour - 6.0) / 24.0 * 2.0 * PI;
  W.sunDir = normalize(vec3(0.45 * cos(a), sin(a), 0.9));
  W.moonDir = normalize(vec3(-0.45 * cos(a), -sin(a), 0.9));
  W.night = 1.0 - smoothstep(-0.15, 0.05, W.sunDir.y);
  vec3 low = vec3(1.0, 0.45, 0.2);
  vec3 high = vec3(1.0, 0.93, 0.85);
  W.sunColor = mix(low, high, smoothstep(0.0, 0.45, W.sunDir.y));
  W.sunColor *= smoothstep(-0.08, 0.06, W.sunDir.y) * 3.0 * (1.0 - 0.9 * W.dark);

  // Lightning: each 2.5-second slot may hold one strike, more likely as the storm grows.
  W.slot = floor(time / 2.5);
  float start = W.slot * 2.5 + 1.5 * hash(vec2(W.slot, 3.0));
  W.boltAge = time - start;
  W.boltX = hash(vec2(W.slot, 11.0)) * 2.0 - 1.0;
  bool strikes = hash(vec2(W.slot, 7.0)) < W.storm;
  W.flash = 0.0;
  if (strikes && W.boltAge > 0.0) {
    W.flash = exp(-W.boltAge * 5.0) * (0.7 + 0.3 * sin(W.boltAge * 70.0));
  }
}
```

| Value | Starts | Full at | What it changes |
|-------|--------|---------|-----------------|
| `cover` | 0 | 0.65 | How much of the sky has cloud. |
| `dark` | 0.35 | 0.95 | Thicker, greyer clouds, less sun, a greyer sky. |
| `rain` and `snow` | 0.55 | 0.75 | How hard it falls. `u_cold` picks which. |
| `storm` | 0.8 | 1 | How likely each lightning slot is to strike. |
| `haze` | 0.4 | 1 | The thickness of the air. |

The [2D clouds](noise.md#clouds-in-2d) had two sliders that moved together. Here a single number moves a dozen values, each at its own pace, and the whole picture changes in step.

## The time of day

`a` is the sun's angle around a circle: 0 at 6 in the morning, a quarter turn at noon and half a turn at 6 in the evening. `sin(a)` is its height, so it rises, peaks and sets. The moon sits on the opposite side of the circle, so it rises as the sun sets.

`night` climbs from 0 to 1 as the sun drops below the horizon. As in [Light, shadow and fog](lighting.md#light-from-the-sun), the sun's colour reddens as it sinks. It also fades out after sunset and dims under thick cloud.

`u_cycle` adds time to the hour, so `mod(..., 24.0)` wraps it round the clock. Set it to 1 and watch a day go by in 24 seconds.

## The sky

`skyColor` is the sky from the lighting chapter, with a night colour added and a step that greys it as the weather turns. Many parts call it: the clouds use it for their ambient light, the ground for its own, and the haze to fade into.

```glsl
// The sky in one direction, with no sun, moon, stars or clouds. Amounts of light.
vec3 skyColor(vec3 rd) {
  float up = clamp(rd.y, 0.0, 1.0);
  float toward = max(dot(rd, W.sunDir), 0.0);
  float day = smoothstep(-0.05, 0.4, W.sunDir.y);

  vec3 dayColor = mix(vec3(0.3, 0.48, 0.8), vec3(0.02, 0.09, 0.45), pow(up, 0.5));
  vec3 duskHorizon = mix(vec3(0.35, 0.15, 0.15), vec3(1.2, 0.35, 0.08), pow(toward, 3.0));
  vec3 duskColor = mix(duskHorizon, vec3(0.02, 0.03, 0.12), pow(up, 0.4));
  vec3 nightColor = mix(vec3(0.004, 0.006, 0.015), vec3(0.0005, 0.001, 0.004), pow(up, 0.5));

  vec3 color = mix(duskColor, dayColor, day);
  color = mix(color, nightColor, W.night);
  // Cloudy weather greys the sky.
  float grey = dot(color, vec3(0.2126, 0.7152, 0.0722));
  return mix(color, vec3(grey) * 0.8, 0.8 * W.dark);
}
```

The stars are the scattered stars from [Randomness and noise](noise.md#a-random-number-for-each-cell), placed by the ray's direction rather than the pixel. `atan(rd.x, rd.z)` and `rd.y` work as a map of the sky, so the stars stay fixed to the sky.

```glsl
vec3 stars(vec3 rd) {
  if (rd.y < 0.0) return vec3(0.0);
  vec2 sp = vec2(atan(rd.x, rd.z), rd.y) * 80.0;
  vec2 cell = floor(sp);
  vec2 star = 0.2 + 0.6 * hash2(cell);
  float d = length(fract(sp) - star);
  float brightness = pow(hash(cell + 7.0), 12.0);
  float twinkle = 0.6 + 0.4 * sin(u_time * (1.0 + 3.0 * hash(cell + 3.0)) + 6.28 * hash(cell));
  return vec3(1.0, 0.95, 0.85) * brightness * twinkle * exp(-d * 30.0) * 4.0;
}
```

`background` adds the sun, its glow, the moon and the stars. The stars fade in only once `night` is well along, since `W.night * W.night` stays low until night is nearly full. They also fade under cloud.

```glsl
// Sky, sun, moon and stars, with no clouds.
vec3 background(vec3 rd) {
  vec3 color = skyColor(rd);
  float clear = 1.0 - W.dark;
  float s = max(dot(rd, W.sunDir), 0.0);
  color += W.sunColor * pow(s, 8.0) * 0.15 * (0.4 + 0.6 * clear);
  color += W.sunColor * smoothstep(0.9994, 0.9997, s) * 8.0;
  float m = max(dot(rd, W.moonDir), 0.0);
  color += vec3(0.8, 0.85, 1.0) * smoothstep(0.9997, 0.9998, m) * 1.5 * W.night;
  color += vec3(0.4, 0.5, 0.7) * pow(m, 20.0) * 0.08 * W.night;
  color += stars(rd) * W.night * W.night * clear;
  return color;
}
```

## Clouds

The clouds are the cloud layer from [Clouds and other volumes](volumes.md#a-layer-of-clouds), with the weather wired in. `cloudDensity` lowers its bar as `cover` grows, and thickens the cloud as `dark` grows:

```glsl
float cloudDensity(vec3 p, int octaves) {
  float h = (p.y - CLOUD_BASE) / (CLOUD_TOP - CLOUD_BASE);
  if (h < 0.0 || h > 1.0) return 0.0;
  float profile = smoothstep(0.0, 0.1, h) * smoothstep(1.0, 0.35, h);
  vec3 q = p * 0.07 + vec3(u_time * W.wind * 0.1, 0.0, u_time * 0.01);
  float n = fbm3(q, octaves);
  // More cover lowers the bar the noise must clear. Storm clouds are thicker as well.
  float bar = mix(0.62, 0.2, W.cover) - 0.15 * W.dark;
  return clamp((n - bar) * profile * 3.0, 0.0, 1.0) * (1.0 + 1.5 * W.dark);
}
```

The march adds four things to the volumes chapter's version:

- **Moonlight.** After sunset the moon lights the clouds, faintly and blue.
- **A darker base under thick cloud.** The ambient light uses the same `depth` as the sun's light, so the cloud between each point and the sun dims it. Without this, an overcast sky is one flat grey.
- **Lightning inside the cloud.** Near the bolt, the flash lights the lower part of the cloud from within.
- **A stop when opaque.** Once `transmit` is nearly 0, the march sets it to exactly 0 and stops, so no trace of the sun shows through a storm cloud.

```glsl
// The light the clouds send toward the eye in rgb, and the share of what is behind them that
// still shows through in a.
vec4 clouds(vec3 ro, vec3 rd, float jitter) {
  if (rd.y <= 0.01) return vec4(0.0, 0.0, 0.0, 1.0);
  float t0 = (CLOUD_BASE - ro.y) / rd.y;
  float t1 = min((CLOUD_TOP - ro.y) / rd.y, t0 + 40.0);
  const int STEPS = 40;
  float dt = (t1 - t0) / float(STEPS);
  float t = t0 + dt * jitter;

  // By night the moon lights the clouds, faintly.
  vec3 lightDir = W.sunDir.y > 0.0 ? W.sunDir : W.moonDir;
  vec3 lightColor = W.sunDir.y > 0.0 ? W.sunColor : vec3(0.15, 0.17, 0.22) * W.night;
  float c = dot(rd, lightDir);
  float ph = mix(phase(c, 0.6), phase(c, -0.2), 0.4);
  vec3 ambientTop = skyColor(vec3(0.0, 1.0, 0.0)) * 0.8 * (1.0 - 0.5 * W.dark);
  vec3 ambientBottom = skyColor(vec3(0.0, 0.2, 0.0)) * 0.15 * (1.0 - 0.8 * W.dark);
  vec3 flashColor = vec3(0.7, 0.75, 1.0) * W.flash * 2.5;
  float absorb = mix(0.6, 1.4, W.dark);

  vec3 light = vec3(0.0);
  float transmit = 1.0;
  for (int i = 0; i < STEPS; i++) {
    vec3 pos = ro + rd * t;
    float d = cloudDensity(pos, 4);
    if (d > 0.002) {
      float depth = 0.0;
      for (int j = 0; j < 3; j++) {
        float dist = 0.8 + 2.5 * float(j * j);
        depth += cloudDensity(pos + lightDir * dist, 2) * (1.0 + 2.0 * float(j));
      }
      float h = (pos.y - CLOUD_BASE) / (CLOUD_TOP - CLOUD_BASE);
      vec3 sun = lightColor * exp(-depth * absorb) * ph;
      // Thick cloud overhead blocks some of the sky's light too, which textures the base.
      vec3 ambient = mix(ambientBottom, ambientTop, h) * (0.3 + 0.7 * exp(-depth * 0.5));
      // Lightning lights the lower cloud near the bolt.
      vec3 flash = flashColor * exp(-abs(pos.x / pos.z - W.boltX * 0.55) * 3.0) * (1.0 - h);
      float block = 1.0 - exp(-d * dt * absorb);
      light += transmit * (sun + ambient + flash) * block;
      transmit *= 1.0 - block;
      if (transmit < 0.01) {
        transmit = 0.0;
        break;
      }
    }
    t += dt;
  }
  float far = exp(-t0 * 0.007);
  return vec4(light * far, mix(1.0, transmit, far));
}
```

`main` multiplies the sky behind by what the clouds let through, `c.a`, then adds the clouds' own light, `c.rgb`.

## Lightning

Lightning has to strike at random moments, but a shader has no memory to plan one. So the shader cuts time into slots of 2.5 seconds and hashes each slot's number.

One hash decides whether the slot holds a strike, another when it starts within the slot, and another where. Every pixel works out the same answers, so they all agree on the strike.

The flash is the pulse from [Shaping values](shaping.md#making-a-pulse): `exp(-age * 5.0)` fades it out, and a fast `sin` makes it flicker. It brightens the clouds, the ground, the hills and the falling rain.

The bolt is made of line segments, as [Shapes from distance](shapes.md#a-cartoon-cloud) suggested. Ten segments run from the top of the picture to the horizon, each one nudged sideways by a hash of its number, which makes the zigzag. Two `exp` curves of the distance give a bright core and a wider glow.

```glsl
// A jagged bolt from the top of the picture down to the horizon, in screen space.
vec3 bolt(vec2 p, float horizon) {
  if (W.flash < 0.05 || W.boltAge > 0.3) return vec3(0.0);
  vec2 a = vec2(W.boltX * 0.7, 0.6);
  float d = 10.0;
  for (int i = 0; i < 10; i++) {
    float y = mix(0.6, horizon, float(i + 1) / 10.0);
    vec2 b = vec2(a.x + (hash(vec2(W.slot, float(i))) - 0.5) * 0.08, y);
    d = min(d, sdSegment(p, a, b));
    a = b;
  }
  float glow = exp(-d * 400.0) + 0.25 * exp(-d * 40.0);
  return vec3(0.85, 0.9, 1.0) * glow * W.flash * 4.0;
}
```

`main` draws the bolt before the clouds, so the clouds cover its top. It shows for only 0.3 seconds, while the flash lingers.

## Rain

The shader draws rain flat, in front of the scene, the way a camera sees it. Each layer is a grid of tall cells, as in [Moving space](space.md#repeating), with at most one streak in each.

A hash of the cell decides whether it holds a streak. The share of cells that do is `W.rain`, so heavier rain fills more of them.

```glsl
// One layer of falling streaks. Nearer layers use larger cells and fall faster.
float rainLayer(vec2 p, float scale, float speed, float seed) {
  p *= scale;
  p.x += p.y * W.wind * 0.4;
  p.y += u_time * speed;
  // Cells four times taller than they are wide, one streak in each.
  vec2 grid = vec2(p.x, p.y / 4.0);
  vec2 cell = floor(grid);
  vec2 local = fract(grid);
  float on = step(hash(cell + seed), W.rain);
  float x = 0.2 + 0.6 * hash(cell + seed + 13.0);
  float y = 0.2 + 0.6 * hash(cell + seed + 29.0);
  float streak = smoothstep(0.08, 0.0, abs(local.x - x)) * smoothstep(0.2, 0.0, abs(local.y - y));
  return streak * on;
}
```

Moving `p.y` with time makes the streaks fall. Adding `p.y` to `p.x` slants them with the wind.

Three layers, each with larger cells and a faster fall than the one behind it, give the rain depth. Near drops look bigger and move faster across the picture than far ones.

## Snow

Snow uses the same kind of grid, with square cells and a round flake in each. Flakes fall slowly, drift with the wind, and sway from side to side. Each flake sways at its own pace, from a hash of its cell.

```glsl
// One layer of flakes, drifting with the wind and wobbling as they fall.
float snowLayer(vec2 p, float scale, float speed, float seed) {
  p *= scale;
  p.y += u_time * speed;
  p.x += u_time * W.wind * speed * 0.8 + 0.4 * sin(p.y * 0.4 + seed);
  vec2 cell = floor(p);
  vec2 local = fract(p);
  float on = step(hash(cell + seed), W.snow * 0.7);
  vec2 pos = 0.3 + 0.4 * hash2(cell + seed);
  pos.x += 0.15 * sin(u_time * 1.5 + 6.28 * hash(cell + seed + 5.0));
  float d = length(local - pos);
  return smoothstep(0.12, 0.05, d) * on;
}
```

## Wet ground

The ground is flat, at height 0. A ray that points down meets it at `t = -CAMERA.y / rd.y`, which needs no marching. The ground's colour comes from 2D fractal noise, between green and brown.

```glsl
vec3 ground(vec3 ro, vec3 rd, float t) {
  vec3 pos = ro + rd * t;
  float n = fbm(pos.xz * 0.3);
  vec3 albedo = mix(vec3(0.03, 0.06, 0.015), vec3(0.09, 0.07, 0.03), n);

  // Snow settles in the low parts first, where the noise is smallest.
  float snowCover = smoothstep(n * 0.8, n * 0.8 + 0.3, W.snow);
  albedo = mix(albedo, vec3(0.7, 0.75, 0.8), snowCover);

  // Wet ground is darker, and puddles gather in the low parts.
  float wet = W.rain;
  albedo *= 1.0 - 0.45 * wet;
  float puddle = smoothstep(0.42, 0.4, n - wet * 0.15) * wet;
  vec2 rip = ripple(pos.xz) * W.rain * exp(-t * 0.08) * 0.25;
  vec3 normal = normalize(vec3(rip.x, 1.0, rip.y));

  // Cloud shadow: the cloud's density above this point, toward the sun.
  float shadow = 1.0;
  if (W.sunDir.y > 0.05) {
    vec3 above = pos + W.sunDir * ((CLOUD_BASE + 3.0 - pos.y) / W.sunDir.y);
    shadow = exp(-cloudDensity(above, 2) * 3.0);
  }

  vec3 ambient = skyColor(vec3(0.0, 1.0, 0.0)) * (1.0 - 0.5 * W.dark);
  ambient += vec3(0.6, 0.65, 0.8) * W.flash * 2.0;
  vec3 color = albedo * (W.sunColor * max(W.sunDir.y, 0.0) * shadow + ambient);

  // Wet ground reflects a little and puddles a lot, more so at a glancing angle.
  vec3 r = reflect(rd, normal);
  float fresnel = 0.04 + 0.96 * pow(1.0 - max(dot(-rd, normal), 0.0), 5.0);
  vec3 overcast = skyColor(vec3(0.0, 1.0, 0.0)) * (1.0 - 0.6 * W.dark);
  vec3 reflected = mix(background(r), overcast, W.cover * 0.8);
  float shine = max(puddle, wet * 0.4) * fresnel + puddle * 0.5;
  return mix(color, reflected, clamp(shine, 0.0, 1.0));
}
```

The weather changes it in five ways:

- **Snow** covers it where the noise is low first, then everywhere as `snow` grows.
- **Rain** darkens it, because a wet surface soaks up more light.
- **Puddles** form where the noise is lowest, and spread as `rain` grows.
- **Ripples** spread across the wet ground, and show most in the puddles, which reflect the most. `ripple` is a grid of rings, each cell with its own drop at its own time. The rings bend the surface's normal, which bends the reflection.
- **Cloud shadows** move across it. A point is in shadow when its ray to the sun meets thick cloud at the cloud layer. That takes one density lookup.

Reflections follow the Fresnel effect: any surface reflects more at a glancing angle. Look across a wet road toward a low sun, and it shines like a mirror. `pow(1.0 - dot(-rd, normal), 5.0)` is a standard short version of it.

```glsl
// Rings spreading where raindrops land: a push to the surface's normal.
vec2 ripple(vec2 xz) {
  vec2 grid = xz * 1.5;
  vec2 cell = floor(grid);
  vec2 local = fract(grid) - 0.5;
  float age = fract(u_time * 1.3 + hash(cell));
  vec2 d = local - (hash2(cell) - 0.5) * 0.4;
  float r = length(d);
  float ring = sin((r - age * 0.45) * 50.0) * smoothstep(0.08, 0.0, abs(r - age * 0.45)) * (1.0 - age);
  return d / max(r, 0.001) * ring;
}
```

## Hills and haze

The hills are only an outline. For each direction around the horizon, 1D fractal noise of the angle gives a height, and a ray that points below that height sees hill. Haze fades the hills toward the sky's colour at the horizon, and the ground fades the same way with distance.

```glsl
// Far hills along the horizon, drawn by their outline alone and faded by the haze.
vec3 hills(vec3 rd, vec3 color) {
  float a = atan(rd.x, rd.z);
  float height = 0.005 + 0.06 * pow(fbm(vec2(a * 2.5, 1.0)), 2.0);
  if (rd.y >= height) return color;
  float day = 1.0 - W.night;
  vec3 hill = vec3(0.015, 0.03, 0.02) * (0.1 + 0.9 * day) + vec3(0.3, 0.32, 0.4) * W.flash;
  hill = mix(hill, vec3(0.4, 0.42, 0.46) * (0.1 + 0.9 * day), smoothstep(0.3, 0.7, W.snow));
  float fog = 1.0 - exp(-150.0 * W.haze);
  return mix(hill, skyColor(normalize(vec3(rd.x, 0.0, rd.z))), fog);
}
```

## Putting it together

`main` runs the steps in order. The camera looks a little upward, so the sky fills most of the picture. `horizon` is where the horizon falls in the picture, and the bolt stops there.

```glsl
void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  setWeather(u_time);

  // A camera on the ground, looking a little upward.
  vec3 forward = normalize(vec3(0.0, 0.18, 1.0));
  vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
  vec3 up = cross(forward, right);
  float zoom = 1.3;
  vec3 rd = normalize(p.x * right + p.y * up + zoom * forward);
  // The height of the horizon in the picture, where rd.y is 0.
  float horizon = -zoom * forward.y / up.y;

  vec3 color;
  if (rd.y > 0.0) {
    color = background(rd);
    color += bolt(p, horizon);
    // A new random start each frame turns the march's bands into a fine grain.
    vec4 c = clouds(CAMERA, rd, hash(gl_FragCoord.xy + fract(u_time) * 100.0));
    color = color * c.a + c.rgb;
    color = hills(rd, color);
  } else {
    float t = -CAMERA.y / rd.y;
    color = ground(CAMERA, rd, t);
    float fog = 1.0 - exp(-min(t, 150.0) * W.haze);
    color = mix(color, skyColor(normalize(vec3(rd.x, 0.0, rd.z))), fog);
  }

  // Rain and snow fall in front of everything, lit by the sky and the lightning.
  vec3 fallColor = skyColor(vec3(0.0, 1.0, 0.0)) * 1.5 + 0.3 + vec3(1.0) * W.flash;
  float rain = rainLayer(p, 10.0, 6.0, 1.0) * 0.5;
  rain += rainLayer(p, 18.0, 9.0, 2.0) * 0.35;
  rain += rainLayer(p, 30.0, 12.0, 3.0) * 0.25;
  color = mix(color, fallColor * 0.6, rain * 0.6);
  float snow = snowLayer(p, 8.0, 0.8, 1.0);
  snow += snowLayer(p, 14.0, 1.0, 2.0) * 0.7;
  snow += snowLayer(p, 24.0, 1.3, 3.0) * 0.4;
  color = mix(color, fallColor, clamp(snow, 0.0, 1.0) * 0.9);

  // Mist over everything, then the steps from the colour chapter. Night gets more exposure,
  // as eyes adjust to the dark, and storms lose some colour.
  color = mix(color, skyColor(vec3(0.0, 0.05, 1.0)), 0.25 * u_mist);
  color = 1.0 - exp(-color * mix(1.3, 3.0, W.night));
  float grey = dot(color, vec3(0.2126, 0.7152, 0.0722));
  color = mix(color, vec3(grey), 0.35 * W.dark);
  color = pow(color, vec3(1.0 / 2.2));
  fragColor = vec4(color, 1.0);
}
```

The end of `main` follows [Colour](colour.md#grading-a-scene): tone mapping, a loss of colour in storms, and the gamma step. Night gets more exposure, the way eyes adjust to the dark, so a clear night still shows its stars and moonlit clouds.

## The whole shader

This is the complete shader. Paste it into a new GLSL shader, or open `shaders/weather.frag`. It is heavy, so use the Preview's `0.5` scale button on a slow computer.

```glsl
// A weather system: a sky that turns from day to night, clouds that build and darken, rain,
// snow, lightning and wet ground. The Handbook's "A weather system" page explains each part.

uniform float u_weather; // @range 0 1 @default 0.35
uniform float u_cold; // @range 0 1 @default 0
uniform float u_wind; // @range 0 1 @default 0.3
uniform float u_hour; // @range 0 24 @default 16
uniform float u_cycle; // @range 0 2 @default 0
uniform float u_mist; // @range 0 1 @default 0

const float PI = 3.14159265;
const float CLOUD_BASE = 12.0;
const float CLOUD_TOP = 22.0;
const vec3 CAMERA = vec3(0.0, 1.5, 0.0);

// Random numbers and noise --------------------------------------------------------------------

float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

vec2 hash2(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.xx + p3.yz) * p3.zy);
}

float hash3(vec3 p) {
  p = fract(p * 0.1031);
  p += dot(p, p.zyx + 31.32);
  return fract((p.x + p.y) * p.z);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash(i);
  float b = hash(i + vec2(1.0, 0.0));
  float c = hash(i + vec2(0.0, 1.0));
  float d = hash(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float noise3(vec3 p) {
  vec3 i = floor(p);
  vec3 f = fract(p);
  vec3 u = f * f * (3.0 - 2.0 * f);
  vec2 e = vec2(1.0, 0.0);
  float a = mix(hash3(i), hash3(i + e.xyy), u.x);
  float b = mix(hash3(i + e.yxy), hash3(i + e.xxy), u.x);
  float c = mix(hash3(i + e.yyx), hash3(i + e.xyx), u.x);
  float d = mix(hash3(i + e.yxx), hash3(i + e.xxx), u.x);
  return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}

float fbm(vec2 p) {
  float sum = 0.0;
  float amplitude = 0.5;
  for (int i = 0; i < 4; i++) {
    sum += amplitude * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p;
    amplitude *= 0.5;
  }
  return sum / 0.9375;
}

float fbm3(vec3 p, int octaves) {
  float sum = 0.0;
  float amplitude = 0.5;
  float total = 0.0;
  for (int i = 0; i < 5; i++) {
    if (i >= octaves) break;
    sum += amplitude * noise3(p);
    total += amplitude;
    p = p * 2.03 + vec3(0.0, 0.0, 1.7);
    amplitude *= 0.5;
  }
  return sum / total;
}

float sdSegment(vec2 p, vec2 a, vec2 b) {
  vec2 pa = p - a;
  vec2 ba = b - a;
  float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
  return length(pa - ba * h);
}

// The weather ----------------------------------------------------------------------------------

// Everything the sliders decide, worked out once per pixel and read by every part below.
struct Weather {
  float cover; // How much of the sky has cloud, from 0.2 to 1.
  float dark; // How thick and grey the clouds are, from 0 to 1.
  float rain; // How hard it rains, from 0 to 1.
  float snow; // How hard it snows, from 0 to 1.
  float storm; // How often lightning strikes, from 0 to 1.
  float haze; // How thick the air is.
  float wind; // How fast clouds, rain and snow move sideways.
  float night; // 0 by day and 1 at night.
  vec3 sunDir;
  vec3 sunColor;
  vec3 moonDir;
  float slot; // Which 2.5-second slot of time this is, for lightning.
  float flash; // How bright the lightning is right now.
  float boltX; // Where the bolt strikes across the picture, from -1 to 1.
  float boltAge; // Seconds since the strike began.
};

Weather W;

void setWeather(float time) {
  float w = u_weather;
  W.cover = mix(0.2, 1.0, smoothstep(0.0, 0.65, w));
  W.dark = smoothstep(0.35, 0.95, w);
  float fall = smoothstep(0.55, 0.75, w);
  float cold = smoothstep(0.4, 0.6, u_cold);
  W.rain = fall * (1.0 - cold);
  W.snow = fall * cold;
  W.storm = smoothstep(0.8, 1.0, w) * (1.0 - cold);
  W.haze = 0.004 + 0.03 * smoothstep(0.4, 1.0, w) + 0.06 * u_mist;
  W.wind = u_wind * (1.0 + W.storm);

  // The sun rises at 6, is highest at 12 and sets at 18. The moon is always opposite it.
  float hour = mod(u_hour + time * u_cycle, 24.0);
  float a = (hour - 6.0) / 24.0 * 2.0 * PI;
  W.sunDir = normalize(vec3(0.45 * cos(a), sin(a), 0.9));
  W.moonDir = normalize(vec3(-0.45 * cos(a), -sin(a), 0.9));
  W.night = 1.0 - smoothstep(-0.15, 0.05, W.sunDir.y);
  vec3 low = vec3(1.0, 0.45, 0.2);
  vec3 high = vec3(1.0, 0.93, 0.85);
  W.sunColor = mix(low, high, smoothstep(0.0, 0.45, W.sunDir.y));
  W.sunColor *= smoothstep(-0.08, 0.06, W.sunDir.y) * 3.0 * (1.0 - 0.9 * W.dark);

  // Lightning: each 2.5-second slot may hold one strike, more likely as the storm grows.
  W.slot = floor(time / 2.5);
  float start = W.slot * 2.5 + 1.5 * hash(vec2(W.slot, 3.0));
  W.boltAge = time - start;
  W.boltX = hash(vec2(W.slot, 11.0)) * 2.0 - 1.0;
  bool strikes = hash(vec2(W.slot, 7.0)) < W.storm;
  W.flash = 0.0;
  if (strikes && W.boltAge > 0.0) {
    W.flash = exp(-W.boltAge * 5.0) * (0.7 + 0.3 * sin(W.boltAge * 70.0));
  }
}

// The sky --------------------------------------------------------------------------------------

// The sky in one direction, with no sun, moon, stars or clouds. Amounts of light.
vec3 skyColor(vec3 rd) {
  float up = clamp(rd.y, 0.0, 1.0);
  float toward = max(dot(rd, W.sunDir), 0.0);
  float day = smoothstep(-0.05, 0.4, W.sunDir.y);

  vec3 dayColor = mix(vec3(0.3, 0.48, 0.8), vec3(0.02, 0.09, 0.45), pow(up, 0.5));
  vec3 duskHorizon = mix(vec3(0.35, 0.15, 0.15), vec3(1.2, 0.35, 0.08), pow(toward, 3.0));
  vec3 duskColor = mix(duskHorizon, vec3(0.02, 0.03, 0.12), pow(up, 0.4));
  vec3 nightColor = mix(vec3(0.004, 0.006, 0.015), vec3(0.0005, 0.001, 0.004), pow(up, 0.5));

  vec3 color = mix(duskColor, dayColor, day);
  color = mix(color, nightColor, W.night);
  // Cloudy weather greys the sky.
  float grey = dot(color, vec3(0.2126, 0.7152, 0.0722));
  return mix(color, vec3(grey) * 0.8, 0.8 * W.dark);
}

vec3 stars(vec3 rd) {
  if (rd.y < 0.0) return vec3(0.0);
  vec2 sp = vec2(atan(rd.x, rd.z), rd.y) * 80.0;
  vec2 cell = floor(sp);
  vec2 star = 0.2 + 0.6 * hash2(cell);
  float d = length(fract(sp) - star);
  float brightness = pow(hash(cell + 7.0), 12.0);
  float twinkle = 0.6 + 0.4 * sin(u_time * (1.0 + 3.0 * hash(cell + 3.0)) + 6.28 * hash(cell));
  return vec3(1.0, 0.95, 0.85) * brightness * twinkle * exp(-d * 30.0) * 4.0;
}

// Sky, sun, moon and stars, with no clouds.
vec3 background(vec3 rd) {
  vec3 color = skyColor(rd);
  float clear = 1.0 - W.dark;
  float s = max(dot(rd, W.sunDir), 0.0);
  color += W.sunColor * pow(s, 8.0) * 0.15 * (0.4 + 0.6 * clear);
  color += W.sunColor * smoothstep(0.9994, 0.9997, s) * 8.0;
  float m = max(dot(rd, W.moonDir), 0.0);
  color += vec3(0.8, 0.85, 1.0) * smoothstep(0.9997, 0.9998, m) * 1.5 * W.night;
  color += vec3(0.4, 0.5, 0.7) * pow(m, 20.0) * 0.08 * W.night;
  color += stars(rd) * W.night * W.night * clear;
  return color;
}

// Clouds ---------------------------------------------------------------------------------------

float cloudDensity(vec3 p, int octaves) {
  float h = (p.y - CLOUD_BASE) / (CLOUD_TOP - CLOUD_BASE);
  if (h < 0.0 || h > 1.0) return 0.0;
  float profile = smoothstep(0.0, 0.1, h) * smoothstep(1.0, 0.35, h);
  vec3 q = p * 0.07 + vec3(u_time * W.wind * 0.1, 0.0, u_time * 0.01);
  float n = fbm3(q, octaves);
  // More cover lowers the bar the noise must clear. Storm clouds are thicker as well.
  float bar = mix(0.62, 0.2, W.cover) - 0.15 * W.dark;
  return clamp((n - bar) * profile * 3.0, 0.0, 1.0) * (1.0 + 1.5 * W.dark);
}

float phase(float c, float g) {
  float g2 = g * g;
  return (1.0 - g2) / pow(1.0 + g2 - 2.0 * g * c, 1.5);
}

// The light the clouds send toward the eye in rgb, and the share of what is behind them that
// still shows through in a.
vec4 clouds(vec3 ro, vec3 rd, float jitter) {
  if (rd.y <= 0.01) return vec4(0.0, 0.0, 0.0, 1.0);
  float t0 = (CLOUD_BASE - ro.y) / rd.y;
  float t1 = min((CLOUD_TOP - ro.y) / rd.y, t0 + 40.0);
  const int STEPS = 40;
  float dt = (t1 - t0) / float(STEPS);
  float t = t0 + dt * jitter;

  // By night the moon lights the clouds, faintly.
  vec3 lightDir = W.sunDir.y > 0.0 ? W.sunDir : W.moonDir;
  vec3 lightColor = W.sunDir.y > 0.0 ? W.sunColor : vec3(0.15, 0.17, 0.22) * W.night;
  float c = dot(rd, lightDir);
  float ph = mix(phase(c, 0.6), phase(c, -0.2), 0.4);
  vec3 ambientTop = skyColor(vec3(0.0, 1.0, 0.0)) * 0.8 * (1.0 - 0.5 * W.dark);
  vec3 ambientBottom = skyColor(vec3(0.0, 0.2, 0.0)) * 0.15 * (1.0 - 0.8 * W.dark);
  vec3 flashColor = vec3(0.7, 0.75, 1.0) * W.flash * 2.5;
  float absorb = mix(0.6, 1.4, W.dark);

  vec3 light = vec3(0.0);
  float transmit = 1.0;
  for (int i = 0; i < STEPS; i++) {
    vec3 pos = ro + rd * t;
    float d = cloudDensity(pos, 4);
    if (d > 0.002) {
      float depth = 0.0;
      for (int j = 0; j < 3; j++) {
        float dist = 0.8 + 2.5 * float(j * j);
        depth += cloudDensity(pos + lightDir * dist, 2) * (1.0 + 2.0 * float(j));
      }
      float h = (pos.y - CLOUD_BASE) / (CLOUD_TOP - CLOUD_BASE);
      vec3 sun = lightColor * exp(-depth * absorb) * ph;
      // Thick cloud overhead blocks some of the sky's light too, which textures the base.
      vec3 ambient = mix(ambientBottom, ambientTop, h) * (0.3 + 0.7 * exp(-depth * 0.5));
      // Lightning lights the lower cloud near the bolt.
      vec3 flash = flashColor * exp(-abs(pos.x / pos.z - W.boltX * 0.55) * 3.0) * (1.0 - h);
      float block = 1.0 - exp(-d * dt * absorb);
      light += transmit * (sun + ambient + flash) * block;
      transmit *= 1.0 - block;
      if (transmit < 0.01) {
        transmit = 0.0;
        break;
      }
    }
    t += dt;
  }
  float far = exp(-t0 * 0.007);
  return vec4(light * far, mix(1.0, transmit, far));
}

// Lightning, rain and snow --------------------------------------------------------------------

// A jagged bolt from the top of the picture down to the horizon, in screen space.
vec3 bolt(vec2 p, float horizon) {
  if (W.flash < 0.05 || W.boltAge > 0.3) return vec3(0.0);
  vec2 a = vec2(W.boltX * 0.7, 0.6);
  float d = 10.0;
  for (int i = 0; i < 10; i++) {
    float y = mix(0.6, horizon, float(i + 1) / 10.0);
    vec2 b = vec2(a.x + (hash(vec2(W.slot, float(i))) - 0.5) * 0.08, y);
    d = min(d, sdSegment(p, a, b));
    a = b;
  }
  float glow = exp(-d * 400.0) + 0.25 * exp(-d * 40.0);
  return vec3(0.85, 0.9, 1.0) * glow * W.flash * 4.0;
}

// One layer of falling streaks. Nearer layers use larger cells and fall faster.
float rainLayer(vec2 p, float scale, float speed, float seed) {
  p *= scale;
  p.x += p.y * W.wind * 0.4;
  p.y += u_time * speed;
  // Cells four times taller than they are wide, one streak in each.
  vec2 grid = vec2(p.x, p.y / 4.0);
  vec2 cell = floor(grid);
  vec2 local = fract(grid);
  float on = step(hash(cell + seed), W.rain);
  float x = 0.2 + 0.6 * hash(cell + seed + 13.0);
  float y = 0.2 + 0.6 * hash(cell + seed + 29.0);
  float streak = smoothstep(0.08, 0.0, abs(local.x - x)) * smoothstep(0.2, 0.0, abs(local.y - y));
  return streak * on;
}

// One layer of flakes, drifting with the wind and wobbling as they fall.
float snowLayer(vec2 p, float scale, float speed, float seed) {
  p *= scale;
  p.y += u_time * speed;
  p.x += u_time * W.wind * speed * 0.8 + 0.4 * sin(p.y * 0.4 + seed);
  vec2 cell = floor(p);
  vec2 local = fract(p);
  float on = step(hash(cell + seed), W.snow * 0.7);
  vec2 pos = 0.3 + 0.4 * hash2(cell + seed);
  pos.x += 0.15 * sin(u_time * 1.5 + 6.28 * hash(cell + seed + 5.0));
  float d = length(local - pos);
  return smoothstep(0.12, 0.05, d) * on;
}

// The ground -----------------------------------------------------------------------------------

// Rings spreading where raindrops land: a push to the surface's normal.
vec2 ripple(vec2 xz) {
  vec2 grid = xz * 1.5;
  vec2 cell = floor(grid);
  vec2 local = fract(grid) - 0.5;
  float age = fract(u_time * 1.3 + hash(cell));
  vec2 d = local - (hash2(cell) - 0.5) * 0.4;
  float r = length(d);
  float ring = sin((r - age * 0.45) * 50.0) * smoothstep(0.08, 0.0, abs(r - age * 0.45)) * (1.0 - age);
  return d / max(r, 0.001) * ring;
}

vec3 ground(vec3 ro, vec3 rd, float t) {
  vec3 pos = ro + rd * t;
  float n = fbm(pos.xz * 0.3);
  vec3 albedo = mix(vec3(0.03, 0.06, 0.015), vec3(0.09, 0.07, 0.03), n);

  // Snow settles in the low parts first, where the noise is smallest.
  float snowCover = smoothstep(n * 0.8, n * 0.8 + 0.3, W.snow);
  albedo = mix(albedo, vec3(0.7, 0.75, 0.8), snowCover);

  // Wet ground is darker, and puddles gather in the low parts.
  float wet = W.rain;
  albedo *= 1.0 - 0.45 * wet;
  float puddle = smoothstep(0.42, 0.4, n - wet * 0.15) * wet;
  vec2 rip = ripple(pos.xz) * W.rain * exp(-t * 0.08) * 0.25;
  vec3 normal = normalize(vec3(rip.x, 1.0, rip.y));

  // Cloud shadow: the cloud's density above this point, toward the sun.
  float shadow = 1.0;
  if (W.sunDir.y > 0.05) {
    vec3 above = pos + W.sunDir * ((CLOUD_BASE + 3.0 - pos.y) / W.sunDir.y);
    shadow = exp(-cloudDensity(above, 2) * 3.0);
  }

  vec3 ambient = skyColor(vec3(0.0, 1.0, 0.0)) * (1.0 - 0.5 * W.dark);
  ambient += vec3(0.6, 0.65, 0.8) * W.flash * 2.0;
  vec3 color = albedo * (W.sunColor * max(W.sunDir.y, 0.0) * shadow + ambient);

  // Wet ground reflects a little and puddles a lot, more so at a glancing angle.
  vec3 r = reflect(rd, normal);
  float fresnel = 0.04 + 0.96 * pow(1.0 - max(dot(-rd, normal), 0.0), 5.0);
  vec3 overcast = skyColor(vec3(0.0, 1.0, 0.0)) * (1.0 - 0.6 * W.dark);
  vec3 reflected = mix(background(r), overcast, W.cover * 0.8);
  float shine = max(puddle, wet * 0.4) * fresnel + puddle * 0.5;
  return mix(color, reflected, clamp(shine, 0.0, 1.0));
}

// Far hills along the horizon, drawn by their outline alone and faded by the haze.
vec3 hills(vec3 rd, vec3 color) {
  float a = atan(rd.x, rd.z);
  float height = 0.005 + 0.06 * pow(fbm(vec2(a * 2.5, 1.0)), 2.0);
  if (rd.y >= height) return color;
  float day = 1.0 - W.night;
  vec3 hill = vec3(0.015, 0.03, 0.02) * (0.1 + 0.9 * day) + vec3(0.3, 0.32, 0.4) * W.flash;
  hill = mix(hill, vec3(0.4, 0.42, 0.46) * (0.1 + 0.9 * day), smoothstep(0.3, 0.7, W.snow));
  float fog = 1.0 - exp(-150.0 * W.haze);
  return mix(hill, skyColor(normalize(vec3(rd.x, 0.0, rd.z))), fog);
}

// Everything together --------------------------------------------------------------------------

void main() {
  vec2 p = (gl_FragCoord.xy - 0.5 * u_resolution) / u_resolution.y;
  setWeather(u_time);

  // A camera on the ground, looking a little upward.
  vec3 forward = normalize(vec3(0.0, 0.18, 1.0));
  vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), forward));
  vec3 up = cross(forward, right);
  float zoom = 1.3;
  vec3 rd = normalize(p.x * right + p.y * up + zoom * forward);
  // The height of the horizon in the picture, where rd.y is 0.
  float horizon = -zoom * forward.y / up.y;

  vec3 color;
  if (rd.y > 0.0) {
    color = background(rd);
    color += bolt(p, horizon);
    // A new random start each frame turns the march's bands into a fine grain.
    vec4 c = clouds(CAMERA, rd, hash(gl_FragCoord.xy + fract(u_time) * 100.0));
    color = color * c.a + c.rgb;
    color = hills(rd, color);
  } else {
    float t = -CAMERA.y / rd.y;
    color = ground(CAMERA, rd, t);
    float fog = 1.0 - exp(-min(t, 150.0) * W.haze);
    color = mix(color, skyColor(normalize(vec3(rd.x, 0.0, rd.z))), fog);
  }

  // Rain and snow fall in front of everything, lit by the sky and the lightning.
  vec3 fallColor = skyColor(vec3(0.0, 1.0, 0.0)) * 1.5 + 0.3 + vec3(1.0) * W.flash;
  float rain = rainLayer(p, 10.0, 6.0, 1.0) * 0.5;
  rain += rainLayer(p, 18.0, 9.0, 2.0) * 0.35;
  rain += rainLayer(p, 30.0, 12.0, 3.0) * 0.25;
  color = mix(color, fallColor * 0.6, rain * 0.6);
  float snow = snowLayer(p, 8.0, 0.8, 1.0);
  snow += snowLayer(p, 14.0, 1.0, 2.0) * 0.7;
  snow += snowLayer(p, 24.0, 1.3, 3.0) * 0.4;
  color = mix(color, fallColor, clamp(snow, 0.0, 1.0) * 0.9);

  // Mist over everything, then the steps from the colour chapter. Night gets more exposure,
  // as eyes adjust to the dark, and storms lose some colour.
  color = mix(color, skyColor(vec3(0.0, 0.05, 1.0)), 0.25 * u_mist);
  color = 1.0 - exp(-color * mix(1.3, 3.0, W.night));
  float grey = dot(color, vec3(0.2126, 0.7152, 0.0722));
  color = mix(color, vec3(grey), 0.35 * W.dark);
  color = pow(color, vec3(1.0 / 2.2));
  fragColor = vec4(color, 1.0);
}
```

## Where to take it next

Each of these uses ideas from the course:

- **A rainbow** can appear after rain, opposite the sun. It is a faint ring of `hsv2rgb` colours around `-W.sunDir`, about 42 degrees out from its centre, and shows only while the sun is low.
- **Fog banks** can lie low over the ground. Make `haze` depend on height, as in the last change in [Light, shadow and fog](lighting.md#try-this).
- **Grass** can bend in the wind. Bend the ground's noise with the wind as in [Moving space](space.md#bending-space).
- **Sleet** falls between rain and snow, when `u_cold` is near 0.5. Draw both, with fewer of each.
- **An aurora** can light clear, cold nights. Draw it with warped noise from [Randomness and noise](noise.md#warping), in green bands, high in the sky.
- **Real cloud reflections** can show in the puddles. March the clouds a second time along the reflected ray, which doubles the cost.
- **Heat haze** can shimmer on a hot, clear day. Bend `p` by a little noise near the horizon before drawing anything.

For more weather to study, Shadertoy holds many examples. [Heartfelt](https://www.shadertoy.com/view/ltffzl) by Martijn Steinrucken draws rain on a window, and he builds it step by step in a video on his channel, [The Art of Code](https://www.youtube.com/@TheArtofCodeIsCool). [Just snow](https://www.shadertoy.com/view/ldsGDn) by Andrew Baldwin is a classic snowfall.

Inigo Quilez's [Rainforest](https://www.shadertoy.com/view/4ttSWf) shows how far terrain, fog and light can go. Sébastien Hillaire's talk on the [sky and clouds of Frostbite](https://media.contentapi.ea.com/content/dam/eacom/frostbite/files/s2016_pbs_frostbite_sky_clouds.pdf) is the next step after this course for a sky that follows the physics of the atmosphere.

[Further reading](resources.md) lists every source in one place.
