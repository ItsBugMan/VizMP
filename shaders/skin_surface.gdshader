shader_type canvas_item;
render_mode unshaded;
uniform vec4 accent : source_color = vec4(0.4,0.8,1.0,1.0);
uniform int surface_type = 0;
void fragment() {
	vec2 uv = UV;
	float brushing = sin(uv.y*1800.0+sin(uv.x*31.0)*0.6)*0.018;
	float specular = pow(max(0.0,1.0-abs(uv.y-0.24)*3.0),8.0)*0.3;
	float ribs = step(0.86,fract(uv.x*24.0))*step(0.4,uv.y)*0.1;
	float base = 0.085 + brushing + specular;
	if (surface_type == 1) { base = 0.04 + specular*1.5; }
	if (surface_type == 2) { base -= ribs; }
	float edge = step(uv.y,0.025)+step(0.975,uv.y);
	vec3 color = vec3(base)*vec3(0.8,0.9,1.0)+accent.rgb*(0.06+edge*0.6);
	float cut = step(abs(uv.x-0.5)+abs(uv.y-0.5)*0.12,0.545);
	COLOR = vec4(color,cut);
}
