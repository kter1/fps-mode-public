// Ground and terrain: a photoscanned base layer plus three overlays weighted by
// vertex colour R, G and B (splat painted at generation time from slope,
// height and layout). UV is metric. All layers stay fixed to the ground; a
// second, rotated sample hides tiling across open yards.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D base_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_arm : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D base_height : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform float base_scale = 0.33;
uniform vec4 base_tint : source_color = vec4(1.0);
// Retained for older saved materials. Ground UVs no longer move with VIEW.
uniform float parallax_depth = 0.0;
uniform sampler2D r_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D r_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float r_scale = 0.5;
uniform float r_roughness = 0.9;
uniform sampler2D g_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D g_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float g_scale = 0.5;
uniform float g_roughness = 0.9;
uniform sampler2D b_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D b_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float b_scale = 0.5;
uniform float b_roughness = 0.8;
uniform sampler2D breakup_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float macro_amount = 0.2;
uniform float blend_sharpness = 4.0;
// Terrain: the rock layer is projected along the dominant world axis
// (triplanar) so cliffs are not smeared by the top-down UVs.
uniform bool steep_projection = false;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec3 triplanar(sampler2D tex, vec3 p, vec3 n) {
	vec3 w = pow(abs(n), vec3(4.0));
	w /= (w.x + w.y + w.z);
	return texture(tex, p.zy).rgb * w.x + texture(tex, p.xz).rgb * w.y + texture(tex, p.xy).rgb * w.z;
}

// Height-aware blend: a layer wins where its weight plus local detail is high,
// giving ragged natural transitions instead of soft smears.
float sharpen(float weight, float detail) {
	return clamp((weight * 1.6 - 0.3 + (detail - 0.5) * 0.8) * blend_sharpness - (blend_sharpness - 1.0) * 0.5, 0.0, 1.0);
}

void fragment() {
	vec2 uv = UV * base_scale;
	float height = texture(base_height, uv).r;
	// Two decorrelated samples of the base, blended by a low-frequency mask.
	vec2 uv_b = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * uv * 0.63 + vec2(0.37, 0.11);
	float mask = smoothstep(0.35, 0.65, texture(breakup_tex, UV * 0.021).r);
	vec3 albedo = mix(texture(base_albedo, uv).rgb, texture(base_albedo, uv_b).rgb, mask) * base_tint.rgb;
	vec3 arm = mix(texture(base_arm, uv).rgb, texture(base_arm, uv_b).rgb, mask);
	vec3 normal = mix(texture(base_normal, uv).rgb, texture(base_normal, uv_b).rgb, mask);
	float roughness = arm.g;
	float ao = arm.r;
	float detail = texture(breakup_tex, UV * 0.17).r;
	float wr = sharpen(COLOR.r, detail);
	float wg = sharpen(COLOR.g, 1.0 - detail);
	float wb = sharpen(COLOR.b, detail * 0.7 + height * 0.3);
	// Evaluate filtered samples uniformly: derivatives inside weight-dependent
	// branches are undefined at splat boundaries and can choose unstable mip levels.
	vec3 rock = steep_projection ? triplanar(r_albedo, world_pos * r_scale, world_normal) : texture(r_albedo, UV * r_scale).rgb;
	vec3 red_normal = texture(r_normal, UV * r_scale).rgb;
	vec3 green_albedo = texture(g_albedo, UV * g_scale).rgb;
	vec3 green_normal = texture(g_normal, UV * g_scale).rgb;
	vec3 blue_albedo = texture(b_albedo, UV * b_scale).rgb;
	vec3 blue_normal = texture(b_normal, UV * b_scale).rgb;
	if (wr > 0.001) {
		albedo = mix(albedo, rock, wr);
		normal = mix(normal, steep_projection ? vec3(0.5, 0.5, 1.0) : red_normal, wr);
		roughness = mix(roughness, r_roughness, wr);
		ao = mix(ao, 1.0, wr);
	}
	if (wg > 0.001) {
		albedo = mix(albedo, green_albedo, wg);
		normal = mix(normal, green_normal, wg);
		roughness = mix(roughness, g_roughness, wg);
		ao = mix(ao, 1.0, wg);
	}
	if (wb > 0.001) {
		albedo = mix(albedo, blue_albedo, wb);
		normal = mix(normal, blue_normal, wb);
		roughness = mix(roughness, b_roughness, wb);
		ao = mix(ao, 1.0, wb);
	}
	float macro = texture(breakup_tex, UV * 0.0061 + vec2(0.3, 0.7)).r;
	albedo *= 1.0 + (macro - 0.5) * macro_amount * 2.0;
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	AO = ao;
	AO_LIGHT_AFFECT = 0.2;
	NORMAL_MAP = normal;
}
