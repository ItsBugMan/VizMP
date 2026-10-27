shader_type canvas_item;
render_mode unshaded;

global uniform vec4 audio_bands;
global uniform vec4 audio_details;

uniform float flight_distance = 0.0;
uniform int march_steps : hint_range(24, 112) = 72;
uniform int fold_limit : hint_range(2, 5) = 4;
uniform float far_distance = 65.0;

mat2 rotation(float angle) {
	float s = sin(angle);
	float c = cos(angle);
	return mat2(vec2(c, s), vec2(-s, c));
}

vec2 centerline(float z) {
	return vec2(sin(z * 0.11) * 0.8, cos(z * 0.07) * 0.6);
}

// All longitudinal frequencies are multiples of 0.01. The geometry and
// palette repeat exactly after 100*TAU, allowing seamless CPU phase wrapping.
vec2 corridor_space(vec3 p) {
	return rotation(p.z * 0.09 + audio_bands.y * 0.65) * (p.xy - centerline(p.z));
}

float field(vec3 p, int folds) {
	vec2 q = corridor_space(p);
	vec2 f = q * 0.6;
	float detail = 0.0;
	float weight = 0.5;
	mat2 fold_rotation = rotation(0.72 + audio_bands.y * 0.22);
	for (int i = 0; i < 5; i++) {
		if (i >= folds) { break; }
		f = fold_rotation * abs(f) - vec2(0.72, 0.34);
		detail += exp(-abs(f.x) * 7.0) * weight;
		weight *= 0.5;
	}
	float octagon = max(max(abs(q.x), abs(q.y)), (abs(q.x) + abs(q.y)) * 0.70710678);
	float radius = 3.0 + audio_details.x * 0.28 - detail * 0.22;
	float wall = radius - octagon;
	// Narrow octagonal frames sit slightly inside the folded corridor wall.
	float frame = max(abs(wall - 0.18) - 0.07, abs(sin(p.z * 1.6)) * 0.65 - 0.065);
	return min(wall, frame);
}

void fragment() {
	vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 uv = (UV - 0.5) * vec2(resolution.x / resolution.y, 1.0);
	vec3 origin = vec3(centerline(flight_distance), flight_distance);
	vec2 ahead = (centerline(flight_distance + 3.0) - origin.xy) / 3.0;
	vec3 ray = normalize(vec3(rotation(sin(flight_distance * 0.05) * 0.09) * uv * 1.45 + ahead, 1.0));
	int folds = min(fold_limit, 2 + int(floor(clamp(audio_bands.y, 0.0, 1.0) * 3.0)));
	highp float travel = 0.0;
	float haze = 0.0;
	bool hit = false;
	highp vec3 p = origin;
	for (int step_index = 0; step_index < 112; step_index++) {
		if (step_index >= march_steps || travel >= far_distance) { break; }
		p = origin + ray * travel;
		float distance_to_surface = field(p, folds);
		float epsilon = max(0.003, travel * 0.00035);
		if (distance_to_surface < epsilon) { hit = true; break; }
		haze += exp(-abs(distance_to_surface) * 12.0) * 0.005;
		// Warps/folds make this a distance estimator, not an exact SDF.
		travel += clamp(distance_to_surface * 0.42, 0.012, 1.4);
	}
	vec3 color = vec3(0.003, 0.006, 0.018);
	if (hit) {
		vec2 q = corridor_space(p);
		float angle = atan(q.y, q.x);
		float frame = exp(-abs(sin(p.z * 1.6)) * 34.0);
		float rails = pow(0.5 + 0.5 * cos(angle * 8.0), 24.0);
		float micro_lines = pow(0.5 + 0.5 * sin(p.z * 12.0 + angle * 16.0), 18.0) * 0.15;
		float hue = angle * 0.3 + p.z * 0.03 + audio_bands.z * 0.6 + audio_details.z * 0.65;
		vec3 neon = 0.55 + 0.45 * cos(vec3(0.0, 2.1, 4.2) + hue * 2.0);
		float fog = exp(-travel * 0.035);
		color += (vec3(0.012, 0.02, 0.045) + neon * (frame * 1.6 + rails * 0.9 + micro_lines)) * fog;
		color += neon * haze * 0.22;
	}
	color += vec3(0.08, 0.015, 0.13) * exp(-dot(uv, uv) * 12.0) * (0.18 + audio_bands.w * 0.3);
	color *= 1.0 - smoothstep(0.35, 1.35, length(uv)) * 0.45;
	COLOR = vec4(color * 1.35, 1.0);
}
