// Ground grass clumps (Ridgeline, Village): alpha-tested crossed cards carrying
// photographed CC0 blades (ambientCG Foliage001, composed by
// tools/generate_grass_clumps.gd). Batched in MultiMeshes by MapNature.
//
// - Colour: the scan's own greens, varied per clump (hash of its position) and in
//   large patches (value noise on the ground) between a fresh green and a dry
//   straw, so a lawn reads as one sward and not as identical copies.
// - Fade: clumps shrink into the ground between fade_start and fade_end metres
//   from the camera (no popping, no blending); the alpha threshold drops with
//   distance so mip-mapped blades do not thin out.
// - Wind: a slow, subtle sway from the tips, in gusts travelling across the field.
// - Lighting: both faces are lit with a world-up normal tipped by the blade
//   normal map, so a clump in shade is as dark as the turf it grows from.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D opacity_tex : hint_default_white, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_disable;
uniform vec4 fresh : source_color = vec4(0.5, 0.82, 0.36, 1.0);
uniform vec4 dry : source_color = vec4(0.78, 0.8, 0.42, 1.0);
uniform float patch_scale = 0.045;
uniform float alpha_cut = 0.5;
uniform float fade_start = 22.0;
uniform float fade_end = 34.0;
uniform float wind = 0.022;
uniform vec4 transmission : source_color = vec4(0.26, 0.34, 0.1, 1.0);
uniform float scatter = 0.12;

varying float fade;
varying float tone;
varying float patch_mix;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1, 0)), f.x), mix(hash21(i + vec2(0, 1)), hash21(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float dist = distance(origin, CAMERA_POSITION_WORLD);
	fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	// COLOR.r is the height along the card (0 at the root, 1 at the tip).
	float lift = COLOR.r;
	VERTEX.y *= mix(0.05, 1.0, fade);
	VERTEX.xz *= mix(0.6, 1.0, fade);
	// Gusts: a wave crossing the field plus a faster flutter, strongest at the tips.
	float gust = sin(TIME * 0.9 + origin.x * 0.22 + origin.z * 0.15) * 0.65 + sin(TIME * 2.3 + origin.x * 0.9 + origin.z * 0.7) * 0.35;
	float sway = gust * wind * lift * lift;
	VERTEX.x += sway;
	VERTEX.z += sway * 0.6;
	tone = mix(0.82, 1.14, hash21(origin.xz * 3.7));
	patch_mix = 0.85 * smoothstep(0.4, 0.8, value_noise(origin.xz * patch_scale * 6.0) * 0.65 + value_noise(origin.xz * patch_scale * 1.7 + 11.0) * 0.35);
}

void fragment() {
	float a = texture(opacity_tex, UV).r;
	// Mip levels thin the blades; accept more of them with distance.
	float cut = mix(alpha_cut, alpha_cut * 0.45, smoothstep(4.0, 24.0, -VERTEX.z));
	if (a < cut) discard;
	vec3 base = texture(albedo_tex, UV).rgb;
	ALBEDO = base * mix(fresh.rgb, dry.rgb, patch_mix) * tone;
	// World-up normal, tipped sideways by the blade's own relief.
	vec3 n_tex = texture(normal_tex, UV).xyz * 2.0 - 1.0;
	vec3 up = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float side = FRONT_FACING ? 1.0 : -1.0;
	NORMAL = normalize(up + TANGENT * n_tex.x * 0.35 * side);
	ROUGHNESS = 0.82;
	SPECULAR = 0.2;
	BACKLIGHT = transmission.rgb;
	EMISSION = ALBEDO * scatter;
}
