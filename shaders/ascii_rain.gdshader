shader_type canvas_item;
render_mode unshaded;
global uniform sampler2D audio_spectrum;
uniform sampler2D portrait : filter_linear, repeat_disable;
uniform sampler2D glyph_atlas : filter_linear, repeat_disable;
uniform float rain_time = 0.0;
uniform float energy = 0.0;
uniform bool signal_active = false;
uniform float columns = 240.0;
uniform float aspect = 1.6;
float hash(float n) { return fract(sin(n * 127.1) * 43758.5453); }
void fragment() {
 vec3 color = vec3(0.0);
 if (signal_active && energy > 0.0001) {
  vec2 grid = vec2(columns, columns / max(aspect, 0.1) * (2.0 / 3.0));
  vec2 cell = floor(UV * grid);
  vec2 local = fract(UV * grid);
  vec2 center = (cell + 0.5) / grid;
  float seed = hash(cell.x + 13.0);
  float head = fract(seed + rain_time * (0.055 + seed * 0.065));
  float trail = fract(head - center.y);
  // Three staggered streams preserve detail without broad vertical holes.
  float distance = min(trail, min(fract(trail + 0.33333), fract(trail + 0.66667)));
  float coverage = 1.0 - smoothstep(0.30, 0.333, distance);
  float streak = pow(1.0 - distance * 3.0, 3.0);
  float band = clamp(texture(audio_spectrum, vec2((cell.x + 0.5) / columns, 0.5)).r, 0.0, 1.0);
  vec2 portrait_size = vec2(textureSize(portrait, 0));
  float portrait_aspect = portrait_size.x / portrait_size.y;
  vec2 face_uv = (center - 0.5) * vec2(aspect / portrait_aspect, 1.0) * 0.62 + vec2(0.5, 0.53);
  float inside = step(0.0, face_uv.x) * step(face_uv.x, 1.0) * step(0.0, face_uv.y) * step(face_uv.y, 1.0);
  float face = dot(texture(portrait, clamp(face_uv, vec2(0.0), vec2(1.0))).rgb, vec3(0.2126, 0.7152, 0.0722)) * inside;
  // Portrait luminance chooses glyph density; arbitrary glyphs erased the eyes.
  float tone = pow(clamp(face, 0.0, 1.0), 0.8);
  float glyph = clamp(floor(tone * 13.0 + 1.0 + hash(cell.x * 71.0 + cell.y * 13.0 + floor(rain_time * 5.0))), 1.0, 15.0);
  if (face < 0.02) glyph = 2.0 + floor(hash(cell.x * 47.0 + cell.y * 11.0 + floor(rain_time * 7.0)) * 14.0);
  float ink = texture(glyph_atlas, vec2((glyph + local.x) / 16.0, local.y)).a;
  float illumination = (0.65 + 0.35 * sqrt(clamp(energy, 0.0, 1.0))) * (0.85 + 0.15 * band);
  float value = ink * coverage * (0.72 + 0.28 * streak) * illumination * (0.008 + tone * 0.88 + (1.0 - smoothstep(0.0, 0.06, face)) * streak * 0.065 * energy);
  // Bounded phosphor intensity: no HDR spikes or static portrait underlay.
  color = vec3(0.055, 0.82, 0.29) * value;
 }
 COLOR = vec4(color, 1.0);
}
