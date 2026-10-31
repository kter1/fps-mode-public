// Photoscanned PBR surface for generated map geometry.
// UV is in metres (generated meshes carry metric UVs), so uv_scale = 1 / scan size.
// Vertex colour R marks grime (1 clean, 0 at wall feet / under copings) and
// G marks bevelled edges (1 face, 0 edge); meshes without colours read white.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D breakup_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float uv_scale = 0.5;
uniform vec4 tint : source_color = vec4(1.0);
uniform float tint_mix = 0.0;
uniform float paint_gain = 2.0;
uniform float normal_depth = 1.0;
uniform float roughness_offset = 0.0;
uniform float metallic_scale = 1.0;
uniform vec4 grime_color : source_color = vec4(0.2, 0.18, 0.15, 1.0);
uniform float grime_amount = 0.7;
uniform float wear_amount = 0.45;
uniform float macro_amount = 0.16;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV * uv_scale;
	vec3 photo = texture(albedo_tex, uv).rgb;
	vec3 arm = texture(arm_tex, uv).rgb;
	float lum = dot(photo, vec3(0.299, 0.587, 0.114));
	// Painted surfaces keep the scan's luminance detail under a new paint colour.
	vec3 base = mix(photo, tint.rgb * lum * paint_gain, tint_mix);
	// Low-frequency variation breaks up repetition across long walls and slabs.
	float macro = texture(breakup_tex, world_pos.xz * 0.023 + vec2(world_pos.y * 0.013)).r;
	base *= 1.0 + (macro - 0.5) * macro_amount * 2.0;
	float breakup = texture(breakup_tex, uv * 0.41 + world_pos.xz * 0.05).r;
	float grime = clamp((1.0 - COLOR.r) * grime_amount * (0.45 + breakup), 0.0, 1.0);
	float wear = clamp((1.0 - COLOR.g) * wear_amount * (0.35 + breakup * 0.9), 0.0, 1.0);
	base = mix(base, base * 1.22 + vec3(0.035), wear);
	base = mix(base, grime_color.rgb * (0.65 + lum * 0.7), grime);
	ALBEDO = base;
	ROUGHNESS = clamp(arm.g + roughness_offset + grime * 0.1 + wear * 0.05, 0.05, 1.0);
	METALLIC = clamp(arm.b * metallic_scale * (1.0 - grime), 0.0, 1.0);
	AO = arm.r;
	AO_LIGHT_AFFECT = 0.25;
	NORMAL_MAP = texture(normal_tex, uv).rgb;
	NORMAL_MAP_DEPTH = normal_depth;
}
