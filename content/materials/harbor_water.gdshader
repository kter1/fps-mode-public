shader_type spatial;
render_mode cull_back, specular_schlick_ggx;

// Harbour basin water: opaque green-grey sea water with two scrolling wave
// normal maps in world space. Reflections come from the sky radiance through
// the GGX specular term (Fresnel brightens grazing angles); the normal detail
// fades with distance so far water reads as a calm reflective sheet.

uniform vec4 near_color : source_color = vec4(0.075, 0.095, 0.09, 1.0);
uniform vec4 far_color : source_color = vec4(0.11, 0.13, 0.135, 1.0);
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float scale_a = 0.035;
uniform float scale_b = 0.11;
uniform vec2 drift_a = vec2(0.010, 0.006);
uniform vec2 drift_b = vec2(-0.007, 0.012);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	vec3 a = texture(wave_a, world_pos.xz * scale_a + TIME * drift_a).rgb;
	vec3 b = texture(wave_b, world_pos.xz * scale_b + TIME * drift_b).rgb;
	vec3 c = texture(wave_b, world_pos.xz * scale_a * 0.31 - TIME * drift_a * 0.5).rgb;
	NORMAL_MAP = normalize((a + b + c) / 3.0 * 2.0 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(0.9, 0.22, smoothstep(12.0, 260.0, dist));
	ALBEDO = mix(near_color.rgb, far_color.rgb, smoothstep(20.0, 400.0, dist));
	ROUGHNESS = mix(0.07, 0.16, smoothstep(30.0, 500.0, dist));
	METALLIC = 0.0;
	SPECULAR = 0.55;
}
