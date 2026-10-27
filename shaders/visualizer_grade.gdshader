shader_type canvas_item;
render_mode unshaded;
global uniform vec4 audio_details;
uniform float aberration : hint_range(0.0, 0.02) = 0.003;
uniform float distortion : hint_range(0.0, 0.1) = 0.018;
uniform float vibrance = 1.08;
void fragment() {
	vec2 center = UV - 0.5;
	float transient = clamp(audio_details.z, 0.0, 1.0);
	vec2 uv = center * (1.0 + dot(center, center) * distortion * (1.0 + transient)) + 0.5;
	vec2 inset = TEXTURE_PIXEL_SIZE * 0.5;
	vec2 shift = center * aberration * transient;
	vec3 color = vec3(texture(TEXTURE, clamp(uv + shift, inset, 1.0 - inset)).r,
		texture(TEXTURE, clamp(uv, inset, 1.0 - inset)).g,
		texture(TEXTURE, clamp(uv - shift, inset, 1.0 - inset)).b);
	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luma), color, vibrance);
	color *= 1.0 - smoothstep(0.24, 0.75, dot(center, center)) * 0.18;
	COLOR = vec4(max(color, vec3(0.0)), 1.0);
}
