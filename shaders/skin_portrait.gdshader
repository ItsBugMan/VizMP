shader_type canvas_item;
render_mode unshaded;
void fragment() {
 vec4 art = texture(TEXTURE, UV);
 float edge = smoothstep(0.0, 0.09, UV.x) * smoothstep(0.0, 0.09, 1.0 - UV.x);
 float foot = smoothstep(0.0, 0.08, 1.0 - UV.y);
 COLOR = vec4(art.rgb, art.a * edge * foot);
}
