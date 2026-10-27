shader_type canvas_item;
render_mode unshaded;

uniform sampler2D phosphor_buffer : filter_linear, repeat_disable;
uniform vec4 phosphor_color : source_color = vec4(0.12, 1.0, 0.32, 1.0);
uniform float buffer_size = 512.0;
uniform float curvature : hint_range(0.0, 0.2) = 0.065;
uniform float mask_strength : hint_range(0.0, 1.0) = 0.22;

float phosphor(vec2 uv) {
	vec2 border = vec2(0.5 / buffer_size);
	float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
	return texture(phosphor_buffer, clamp(uv, border, vec2(1.0) - border)).r * inside;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	vec2 glass = p * (1.0 + curvature * dot(p, p));
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	// L/R have the same screen scale; quadrature remains circular at any aspect.
	vec2 plane = p * vec2(max(aspect, 1.0), max(1.0 / aspect, 1.0));
	vec2 square = plane * (1.0 + curvature * dot(plane, plane));
	vec2 uv = square * 0.5 + 0.5;
	vec2 texel = vec2(1.0 / buffer_size);
	float center = phosphor(uv);
	float bloom = 0.0;
	bloom += phosphor(uv + vec2(2.5, 0.0) * texel);
	bloom += phosphor(uv - vec2(2.5, 0.0) * texel);
	bloom += phosphor(uv + vec2(0.0, 2.5) * texel);
	bloom += phosphor(uv - vec2(0.0, 2.5) * texel);
	bloom += phosphor(uv + vec2(5.0, 5.0) * texel) * 0.5;
	bloom += phosphor(uv + vec2(-5.0, 5.0) * texel) * 0.5;
	bloom += phosphor(uv + vec2(5.0, -5.0) * texel) * 0.5;
	bloom += phosphor(uv - vec2(5.0, 5.0) * texel) * 0.5;
	float energy = 1.0 - exp(-max(0.0, center + bloom * 0.12) * 1.15);
	vec3 tint = mix(phosphor_color.rgb, vec3(0.85, 1.0, 0.88), smoothstep(0.65, 1.0, energy) * 0.45);
	vec3 color = tint * energy;
	// Static graticule stays crisp: it is not accumulated into phosphor history.
	vec2 cell = abs(fract(square * 5.0 + 0.5) - 0.5);
	vec2 aa = max(fwidth(square * 5.0), vec2(0.002));
	float grid = 1.0 - min(smoothstep(0.005, 0.005 + aa.x, cell.x), smoothstep(0.005, 0.005 + aa.y, cell.y));
	float axes = exp(-min(abs(square.x), abs(square.y)) * 180.0);
	float grid_bounds = (1.0 - smoothstep(0.86, 0.92, max(abs(square.x), abs(square.y))));
	color += phosphor_color.rgb * (grid * 0.025 + axes * 0.04) * grid_bounds;
	color += phosphor_color.rgb * 0.004;
	float scanline = 0.94 + 0.06 * cos(FRAGCOORD.y * PI);
	float column = mod(floor(FRAGCOORD.x), 3.0);
	vec3 triad = vec3(float(column < 1.0), float(column >= 1.0 && column < 2.0), float(column >= 2.0));
	vec3 mask = mix(vec3(1.0), vec3(0.7) + triad * 0.3, mask_strength);
	float dots = 0.96 + 0.04 * cos(FRAGCOORD.y * PI) * cos(FRAGCOORD.x * TAU / 3.0);
	float vignette = 1.0 - smoothstep(0.35, 1.4, length(p)) * 0.55;
	float screen_edge = 1.0 - smoothstep(0.985, 1.015, max(abs(glass.x), abs(glass.y)));
	COLOR = vec4(color * mask * scanline * dots * vignette * screen_edge, 1.0);
}
