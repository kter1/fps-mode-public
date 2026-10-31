// Broadleaf and shrub cards for Village (leaf sprays composed by
// tools/generate_village_leaves.gd from CC0 ambientCG leaf scans). Alpha-scissored
// so cards stay in the opaque pass and cast clean shadows. The mesh normals are
// bent toward the crown's outside so a tree shades as one volume; the leaf normal
// map adds vein relief on top. Vertex colour R darkens the inner crown, G shifts
// a card toward yellow-green so the crown is not one flat tone. Thin leaves let
// sunlight through from behind.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D opacity_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(0.9, 0.95, 0.8, 1.0);
uniform float alpha_cut = 0.4;
uniform vec4 transmission : source_color = vec4(0.3, 0.38, 0.1, 1.0);
uniform float leaf_specular = 0.35;
uniform float leaf_roughness = 0.6;

void fragment() {
	// Godot flips normals on back faces of double-sided geometry; the crown
	// normals already point outward, so both sides keep them.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 leaf = texture(albedo_tex, UV).rgb * tint.rgb;
	leaf = mix(leaf, leaf * vec3(1.2, 1.06, 0.6), COLOR.g * 0.55);
	ALBEDO = leaf * mix(0.4, 1.0, COLOR.r);
	ALPHA = texture(opacity_tex, UV).r;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = 0.6;
	ROUGHNESS = leaf_roughness;
	SPECULAR = leaf_specular;
	BACKLIGHT = transmission.rgb * COLOR.r;
	AO = mix(0.5, 1.0, COLOR.r);
	AO_LIGHT_AFFECT = 0.4;
}
