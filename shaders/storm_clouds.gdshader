shader_type canvas_item;
render_mode unshaded;
uniform float storm_time = 0.0;
uniform float flash = 0.0;
uniform float strike_x = 0.5;
uniform int cloud_layers = 6;
float hash(vec2 p) {
	vec3 q = fract(vec3(p.xyx)*0.1031);
	q += dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i), hash(i+vec2(1,0)), f.x), mix(hash(i+vec2(0,1)), hash(i+vec2(1,1)), f.x), f.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i=0; i<4; i++) { v += a*noise(p); p = mat2(vec2(1.6,1.2),vec2(-1.2,1.6))*p; a *= 0.5; }
	return v;
}
void fragment() {
	vec2 uv = UV; float density = 0.0; float light = 0.0; float transmittance = 1.0;
	// Front-to-back cloud slices approximate illuminated volume at fixed cost.
	for (int i=0; i<9; i++) {
		if (i >= cloud_layers) { break; }
		float z = float(i)*0.19;
		float d = smoothstep(0.3,0.8,fbm(uv*vec2(4.5,2.6)+vec2(z*2.0+storm_time*0.025,z)));
		d *= (1.0-smoothstep(0.25,0.95,uv.y))*0.55;
		float illumination = exp(-abs(uv.x-strike_x)*3.0-z)*flash*5.0;
		light += d*transmittance*illumination;
		density += d*transmittance; transmittance *= exp(-d*1.7);
	}
	vec3 color = vec3(0.004,0.007,0.014)*density + vec3(0.35,0.55,1.0)*light;
	color += vec3(0.028,0.042,0.065)*flash*exp(-abs(uv.x-strike_x)*2.0);
	COLOR = vec4(color,1.0);
}
