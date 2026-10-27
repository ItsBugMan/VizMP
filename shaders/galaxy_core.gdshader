shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform vec4 audio_bands;
global uniform vec4 audio_details;

void vertex() {
	MODELVIEW_MATRIX = mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 0.0),
		vec4(0.0, 0.0, 1.0, 0.0), (VIEW_MATRIX * MODEL_MATRIX)[3]);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float halo = exp(-r * r * 7.0);
	float core = exp(-r * r * 150.0);
	vec3 tint = mix(vec3(1.0, 0.38, 0.12), vec3(1.0, 0.88, 0.64), core);
	ALBEDO = tint;
	EMISSION = tint * (halo * 0.5 + core * 3.0);
	ALPHA = (halo * 0.2 + core * 0.7) * (0.65 + audio_bands.x * 0.2 + audio_details.z * 0.15)
		* (1.0 - smoothstep(0.75, 1.0, r));
}
