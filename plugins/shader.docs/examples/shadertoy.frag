// A Shadertoy shader works as it is: the preview fills in iResolution, iTime, iTimeDelta,
// iFrame and iMouse, and calls mainImage for each pixel. Paste one in to try it.

vec3 palette(float t) {
  return 0.5 + 0.5 * cos(6.28318 * (t + vec3(0.0, 0.33, 0.67)));
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv = (fragCoord * 2.0 - iResolution.xy) / iResolution.y;
  vec2 uv0 = uv;
  vec3 color = vec3(0.0);
  for (float i = 0.0; i < 4.0; i++) {
    uv = fract(uv * 1.5) - 0.5;
    float d = length(uv) * exp(-length(uv0));
    vec3 col = palette(length(uv0) + i * 0.4 + iTime * 0.4);
    d = sin(d * 8.0 + iTime) / 8.0;
    d = abs(d);
    d = pow(0.01 / d, 1.2);
    color += col * d;
  }
  fragColor = vec4(color, 1.0);
}
