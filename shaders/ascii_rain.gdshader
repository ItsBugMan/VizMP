shader_type canvas_item;
render_mode unshaded;
global uniform sampler2D audio_spectrum;
uniform sampler2D portrait : filter_linear, repeat_disable;
uniform sampler2D glyph_atlas : filter_linear, repeat_disable;
uniform float rain_time = 0.0;
uniform float energy = 0.0;
uniform bool signal_active = false;
uniform float columns = 112.0;
uniform float aspect = 1.6;
float hash(float n) { return fract(sin(n*127.1)*43758.5453); }
void fragment() {
	vec3 color = vec3(0.0);
	if (signal_active && energy > 0.0001) {
		vec2 grid = vec2(columns, columns / max(aspect, 0.1) * 0.64);
		vec2 cell = floor(UV*grid); vec2 local = fract(UV*grid);
		float seed = hash(cell.x+13.0);
		float head = fract(seed+rain_time*(0.07+seed*0.14));
		float trail = fract(head-UV.y);
		float band = texture(audio_spectrum,vec2((cell.x+0.5)/columns,0.5)).r;
		float tail_length = mix(0.12,0.72,energy);
		float tail = pow(max(0.0,1.0-trail/tail_length),1.1)*step(trail,tail_length);
		float glyph = floor(hash(cell.x*71.0+cell.y*13.0+floor(rain_time*9.0))*16.0);
		float ink = texture(glyph_atlas,vec2((glyph+local.x)/16.0,local.y)).a;
		vec2 face_uv = (UV-vec2(0.5,0.4))*vec2(aspect*0.72,0.8)+vec2(0.5,0.52);
		float inside = step(0.0,face_uv.x)*step(face_uv.x,1.0)*step(0.0,face_uv.y)*step(face_uv.y,1.0);
		vec3 face_sample = texture(portrait,clamp(face_uv,vec2(0),vec2(1))).rgb;
		float face = dot(face_sample,vec3(0.2126,0.7152,0.0722))*inside;
		// No portrait layer: only intersecting glyph ink reveals local luminance.
		float reveal = ink*tail*energy*(0.16+band*1.6);
		color = mix(vec3(0.015,0.3,0.16),vec3(0.08,1.4,0.65),face)*reveal*(0.15+face*2.6);
		color += vec3(0.6,1.0,0.8)*ink*step(trail,0.018)*face*band*energy;
	}
	COLOR = vec4(color,1.0);
}
