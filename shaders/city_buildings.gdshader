shader_type spatial;
render_mode unshaded, cull_back;

global uniform sampler2D audio_spectrum;
global uniform vec4 audio_details;
varying vec3 facade_position;
varying flat vec3 facade_normal;
varying flat float energy;
varying flat float building_height;
varying flat float appearance;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	energy = textureLod(audio_spectrum, vec2(INSTANCE_CUSTOM.r, 0.5), 0.0).r;
	appearance = INSTANCE_CUSTOM.b;
	building_height = clamp(1.0 + INSTANCE_CUSTOM.g * 3.0
		+ energy * energy * (18.0 + INSTANCE_CUSTOM.g * 6.0), 1.0, 28.0);
	// BoxMesh is centered; move the base to y=0 before applying height.
	VERTEX.y = (VERTEX.y + 0.5) * building_height;
	facade_position = VERTEX;
	facade_normal = NORMAL;
	// Axis-aligned box faces retain their normal directions after Y scaling.
}

void fragment() {
	float roof = step(0.5, facade_normal.y);
	float side_u = abs(facade_normal.x) > 0.5 ? facade_position.z : facade_position.x;
	vec2 cells = vec2((side_u + 0.5) * 5.0, facade_position.y * 0.9);
	vec2 aa = clamp(fwidth(cells), vec2(0.015), vec2(0.18));
	vec2 cell = fract(cells);
	vec2 window_mask = smoothstep(vec2(0.17) - aa, vec2(0.17) + aa, cell)
		* (1.0 - smoothstep(vec2(0.76) - aa, vec2(0.76) + aa, cell));
	float lit = step(hash21(floor(cells) + appearance * 97.0), 0.13 + energy * 0.76);
	float windows = window_mask.x * window_mask.y * lit * (1.0 - roof);
	vec3 cyan = vec3(0.03, 0.7, 1.0);
	vec3 magenta = vec3(0.9, 0.07, 0.5);
	vec3 neon = mix(cyan, magenta, appearance);
	float edge = mix(smoothstep(0.46, 0.5, abs(side_u)),
		1.0 - smoothstep(0.01, 0.055, min(0.5 - abs(facade_position.x), 0.5 - abs(facade_position.z))), roof);
	float face_shade = 0.55 + abs(facade_normal.x) * 0.3 + roof * 0.3;
	// In the unshaded path, write HDR radiance to ALBEDO directly.
	ALBEDO = vec3(0.018, 0.028, 0.052) * face_shade
		+ neon * (windows * (0.18 + energy * 1.8) + edge * (0.06 + energy * 0.3))
		* (1.0 + audio_details.z * 0.3);
}
