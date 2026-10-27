shader_type canvas_item;
render_mode unshaded, blend_mix;
uniform float decay_alpha : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	// Black source over a retained HDR color attachment: old *= 1 - alpha.
	// This never samples the texture currently being rendered into.
	COLOR = vec4(0.0, 0.0, 0.0, decay_alpha);
}
