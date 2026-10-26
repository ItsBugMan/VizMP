shader_type canvas_item;
render_mode unshaded;

// Same globals can be consumed by future city, galaxy and tunnel materials.
global uniform vec4 audio_bands;   // bass, mid, treble, volume
global uniform vec4 audio_details; // sub-bass, highs, transient pulse, reserved
global uniform sampler2D audio_spectrum;

uniform vec4 low_color : source_color = vec4(0.10, 0.90, 0.84, 1.0);
uniform vec4 high_color : source_color = vec4(0.67, 0.38, 1.0, 1.0);
uniform float intensity : hint_range(0.0, 3.0) = 1.0;

void fragment() {
	// SCREEN_PIXEL_SIZE preserves circular geometry at every window aspect.
	vec2 p = (SCREEN_UV - 0.5) * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0);
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float bin = floor(fract(angle / TAU + 1.0) * 64.0);
	// Sample texel centers to prevent accidental interpolation between bins.
	float energy = texture(audio_spectrum, vec2((bin + 0.5) / 64.0, 0.5)).r;
	float pulse = audio_details.z;
	float base = 0.205 + audio_bands.x * 0.035 + pulse * 0.018;
	float edge = base + energy * 0.17;
	float aa = max(fwidth(radius), 0.0005);
	float ring = 1.0 - smoothstep(aa, aa * 3.0, abs(radius - edge));
	float glow = exp(-abs(radius - edge) * 70.0) * (0.15 + audio_bands.w * 0.55);
	float spokes = pow(max(0.0, cos(angle * 64.0)), 5.0);
	float bars = smoothstep(base - aa, base + aa, radius)
		* (1.0 - smoothstep(edge, edge + aa, radius)) * spokes * energy;
	vec3 tint = mix(low_color.rgb, high_color.rgb, 0.5 + 0.5 * sin(angle + TIME * 0.12 + audio_bands.y));
	vec3 background = vec3(0.012, 0.019, 0.038);
	background += tint * exp(-radius * 5.0) * (0.025 + audio_bands.z * 0.04);
	// Modest pulse avoids a full-screen white flash on every onset.
	vec3 color = background + tint * (ring + glow + bars * 0.65) * intensity;
	color += tint * pulse * 0.025;
	COLOR = vec4(color, 1.0);
}
