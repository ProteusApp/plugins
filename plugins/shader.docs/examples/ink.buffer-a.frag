// Ink, Buffer A: how much ink lies on each pixel. Each frame it reads its own last frame on
// iChannel0, spreads the ink a little to the pixels around, lets it fade, and drops more under
// the mouse while it is down, or under a point that wanders while it is up. ink.frag turns
// what it keeps into colour.
// @channel 0 buffer-a
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 px = 1.0 / iResolution.xy;
  vec2 uv = fragCoord * px;
  float around = texture(iChannel0, uv + vec2(px.x, 0.0)).r
    + texture(iChannel0, uv - vec2(px.x, 0.0)).r
    + texture(iChannel0, uv + vec2(0.0, px.y)).r
    + texture(iChannel0, uv - vec2(0.0, px.y)).r;
  float ink = mix(texture(iChannel0, uv).r, around * 0.25, 0.6) * 0.996;
  vec2 drop = iResolution.xy * (0.5 + vec2(0.3 * cos(iTime * 0.7), 0.25 * sin(iTime * 1.1)));
  if (iMouse.z > 0.0) {
    drop = iMouse.xy;
  }
  ink += 1.0 - smoothstep(0.0, 10.0, length(fragCoord - drop));
  fragColor = vec4(min(ink, 1.0), 0.0, 0.0, 1.0);
}
