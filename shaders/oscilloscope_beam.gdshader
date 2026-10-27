shader_type canvas_item;
render_mode unshaded, blend_add;

uniform sampler2D pcm_texture : filter_nearest, repeat_disable;
uniform int texture_width = 2048;
uniform int valid_frames = 0;
uniform int point_budget = 1024;
uniform float common_gain = 3.0;
uniform float beam_exposure = 0.025;
uniform float beam_enabled = 0.0;
uniform float buffer_size = 512.0;

void vertex() {
	// Static vertices encode segment index and signed ribbon side.
	float segment = VERTEX.x;
	float side = VERTEX.y;
	float offset = float(max(0, valid_frames - point_budget));
	vec2 a = textureLod(pcm_texture, vec2((segment + offset + 0.5) / float(texture_width), 0.5), 0.0).rg;
	vec2 b = textureLod(pcm_texture, vec2((segment + offset + 1.5) / float(texture_width), 0.5), 0.0).rg;
	a = clamp(vec2(a.x, -a.y) * common_gain, vec2(-1.08), vec2(1.08));
	b = clamp(vec2(b.x, -b.y) * common_gain, vec2(-1.08), vec2(1.08));
	vec2 direction = b - a;
	float segment_length = length(direction);
	vec2 normal = vec2(-direction.y, direction.x) / max(segment_length, 0.000001);
	float active = float(segment + 1.0 < float(min(valid_frames, point_budget))) * beam_enabled;
	VERTEX = (vec2(0.5) + mix(a, b, UV.x) * 0.42) * buffer_size
		+ normal * side * (2.2 * buffer_size / 512.0) * active;
	COLOR.a = active;
}

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float profile = exp(-across * across * 12.0);
	COLOR = vec4(vec3(1.0), profile * beam_exposure * COLOR.a);
}
