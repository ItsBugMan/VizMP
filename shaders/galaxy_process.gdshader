shader_type particles;
render_mode disable_force, disable_velocity;

global uniform vec4 audio_bands;
global uniform vec4 audio_details;
global uniform vec2 audio_event; // Persistent onset serial, onset strength.
global uniform sampler2D audio_spectrum;

uniform float galaxy_radius = 16.0;
uniform float spawn_ratio : hint_range(0.0, 1.0) = 0.65;
uniform float motion_strength : hint_range(0.0, 2.0) = 1.0;

float random_value(uint seed) {
	seed = (seed ^ (seed >> 16u)) * 2246822519u;
	seed = (seed ^ (seed >> 13u)) * 3266489917u;
	return float(seed ^ (seed >> 16u)) / 4294967295.0;
}

void start() {
	uint seed = NUMBER * 747796405u + RANDOM_SEED;
	// Custom process shaders must implement emission-density rejection.
	ACTIVE = random_value(seed + 19u) <= spawn_ratio;
	float radius = 0.45 + galaxy_radius * pow(random_value(seed + 2u), 0.82);
	float arm = float(INDEX % 4u) * TAU * 0.25;
	float angle = arm + log(radius + 1.0) * 2.5
		+ (random_value(seed + 3u) - 0.5) * (0.16 + 0.035 * radius);
	vec3 position = vec3(cos(angle) * radius,
		(random_value(seed + 4u) - 0.5) * (0.3 + radius * 0.045), sin(angle) * radius);
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = position;
	VELOCITY = vec3(-sin(angle), 0.0, cos(angle)) * (0.65 + radius * 0.025);
	// age, birth radius, stable appearance seed, last observed onset serial.
	CUSTOM = vec4(0.0, radius, random_value(seed + 5u), audio_event.x);
	COLOR = vec4(1.0);
}

void process() {
	CUSTOM.x += DELTA / LIFETIME;
	vec3 position = TRANSFORM[3].xyz;
	float radius = max(length(position.xz), 0.1);
	vec3 radial = vec3(position.x / radius, 0.0, position.z / radius);
	vec3 tangent = vec3(-radial.z, 0.0, radial.x);
	float bin = floor(clamp(CUSTOM.y / (galaxy_radius + 0.5), 0.0, 0.999) * 64.0);
	float frequency = textureLod(audio_spectrum, vec2((bin + 0.5) / 64.0, 0.5), 0.0).r;
	float swirl = (0.7 + audio_details.x * 4.5 + audio_bands.x * 1.2) * motion_strength;
	vec3 desired_velocity = tangent * swirl * (0.75 + radius * 0.045);
	// Stable velocity relaxation and radial restoring force keep the disk bounded.
	VELOCITY = mix(VELOCITY, desired_velocity, 1.0 - exp(-DELTA * 1.8));
	VELOCITY += radial * (CUSTOM.y - radius) * DELTA * 1.2;
	VELOCITY.y += (-position.y * 2.5 - VELOCITY.y * 0.8) * DELTA;
	if (CUSTOM.w != audio_event.x) {
		CUSTOM.w = audio_event.x;
		float burst = clamp(audio_event.y, 0.0, 1.0) * motion_strength;
		VELOCITY += radial * burst * (3.0 + frequency * 4.0);
		VELOCITY.y += (CUSTOM.z - 0.5) * burst * 3.0;
	}
	position += VELOCITY * DELTA;
	float new_radius = length(position.xz);
	if (new_radius > 24.0) {
		position.xz *= 24.0 / new_radius;
		VELOCITY.xz *= -0.2;
	}
	position.y = clamp(position.y, -4.0, 4.0);
	TRANSFORM[3].xyz = position;
	float scale = (0.045 + CUSTOM.z * CUSTOM.z * 0.095)
		* (1.0 + frequency * 0.7 + audio_bands.x * 0.45 + audio_details.z * 0.55);
	TRANSFORM[0].xyz = vec3(scale, 0.0, 0.0);
	TRANSFORM[1].xyz = vec3(0.0, scale, 0.0);
	TRANSFORM[2].xyz = vec3(0.0, 0.0, scale);
	vec3 warm = vec3(1.0, 0.66, 0.3);
	vec3 cyan = vec3(0.12, 0.72, 1.0);
	vec3 violet = vec3(0.68, 0.22, 1.0);
	vec3 outer = mix(cyan, violet, smoothstep(0.2, 1.0, CUSTOM.z + audio_bands.y * 0.15));
	COLOR.rgb = mix(warm, outer, smoothstep(1.5, 9.0, CUSTOM.y));
	float fade = smoothstep(0.0, 0.04, CUSTOM.x) * (1.0 - smoothstep(0.8, 1.0, CUSTOM.x));
	COLOR.a = fade * (0.42 + frequency * 0.42 + audio_bands.z * 0.16);
}
