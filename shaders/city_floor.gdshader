shader_type spatial;
render_mode cull_back;

global uniform vec4 audio_bands;
uniform vec4 shockwaves[8]; // origin X/Z, age in seconds, strength (zero=inactive).
uniform float wave_speed = 24.0;
uniform float cell_spacing = 2.2;
varying vec2 ground_position;

void vertex() {
	ground_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 cell = ground_position / cell_spacing + vec2(0.5);
	vec2 width = max(fwidth(cell), vec2(0.01));
	vec2 line_distance = abs(fract(cell) - 0.5);
	float grid = 1.0 - min(smoothstep(0.012, 0.012 + width.x, line_distance.x),
		smoothstep(0.012, 0.012 + width.y, line_distance.y));
	float waves = 0.0;
	for (int i = 0; i < 8; i++) {
		vec4 wave = shockwaves[i];
		if (wave.w <= 0.0) { continue; }
		float radius = wave.z * wave_speed;
		float edge = abs(length(ground_position - wave.xy) - radius);
		float ring = 1.0 - smoothstep(0.22, 1.8, edge);
		float halo = exp(-edge * 0.65) * 0.2;
		waves += (ring + halo) * exp(-wave.z * 0.65) * wave.w;
	}
	waves = min(waves, 2.5);
	ALBEDO = vec3(0.015, 0.023, 0.04);
	METALLIC = 0.8;
	ROUGHNESS = 0.22;
	EMISSION = vec3(0.025, 0.3, 0.55) * grid * (0.3 + audio_bands.x * 0.25)
		+ vec3(0.1, 0.85, 1.0) * waves * 3.5;
}
