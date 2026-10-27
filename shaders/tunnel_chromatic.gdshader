shader_type canvas_item;
render_mode unshaded;

global uniform vec4 audio_bands;
global uniform vec4 audio_details;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

void fragment() {
	// One shared raymarch followed by three inexpensive screen-texture taps.
	float spike = clamp(audio_bands.z * 0.25 + audio_details.y * 0.15 + audio_details.z * 0.8, 0.0, 1.0);
	vec2 shift = (SCREEN_UV - 0.5) * spike * 0.013;
	vec2 low = SCREEN_PIXEL_SIZE * 0.5;
	vec2 high = vec2(1.0) - low;
	vec3 color;
	color.r = texture(screen_texture, clamp(SCREEN_UV + shift, low, high)).r;
	color.g = texture(screen_texture, SCREEN_UV).g;
	color.b = texture(screen_texture, clamp(SCREEN_UV - shift, low, high)).b;
	COLOR = vec4(color, 1.0);
}
