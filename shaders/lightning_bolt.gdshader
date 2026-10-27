shader_type canvas_item;
render_mode unshaded, blend_add;
void fragment() {
	// Add emissive cores without painting opaque dark rims over lit clouds.
	COLOR = vec4(COLOR.rgb, 1.0);
}
