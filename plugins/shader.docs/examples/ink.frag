// Ink: a shader with a buffer. Buffer A, in ink.buffer-a.frag, draws first each frame and keeps
// how much ink lies on each pixel. This pass, the image, reads it on iChannel0 and turns it into
// colour on paper, with noise on iChannel1 for the paper's grain. Press and drag over the
// preview to draw.
// @channel 0 buffer-a
// @channel 1 noise
void mainImage(out vec4 fragColor, in vec2 fragCoord) {
  vec2 uv = fragCoord / iResolution.xy;
  float ink = texture(iChannel0, uv).r;
  float grain = texture(iChannel1, fragCoord / 256.0).r;
  vec3 paper = vec3(0.96, 0.93, 0.86) - 0.05 * grain;
  vec3 colour = mix(vec3(0.15, 0.25, 0.6), vec3(0.02, 0.03, 0.12), ink);
  fragColor = vec4(mix(paper, colour, smoothstep(0.02, 0.6, ink)), 1.0);
}
