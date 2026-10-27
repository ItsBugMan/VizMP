shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

global uniform vec4 audio_details;

void vertex() {
	// View-aligned quads, preserving the scale written by the process shader.
	vec3 scale = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = mat4(vec4(scale.x, 0.0, 0.0, 0.0),
		vec4(0.0, scale.y, 0.0, 0.0), vec4(0.0, 0.0, scale.z, 0.0),
		(VIEW_MATRIX * MODEL_MATRIX)[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r2 = dot(p, p);
	float halo = exp(-r2 * 5.0) * 0.3;
	float core = exp(-r2 * 34.0);
	float edge = 1.0 - smoothstep(0.7, 1.0, r2);
	ALBEDO = COLOR.rgb * (1.4 + audio_details.z * 0.45);
	EMISSION = COLOR.rgb * core * 2.0;
	ALPHA = clamp((core + halo) * COLOR.a * edge, 0.0, 1.0);
}
