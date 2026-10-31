// Fir branch cards (ambientCG LeafSet019). Alpha-scissored so cards render in
// the opaque pass and cast clean shadows; normals were bent toward the crown's
// outside at generation so the tree shades as one volume; thin needles let
// sunlight through from behind.
shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D opacity_tex : hint_default_white, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(0.62, 0.72, 0.55, 1.0);
uniform float alpha_cut = 0.42;
uniform vec4 transmission : source_color = vec4(0.32, 0.42, 0.14, 1.0);

void fragment() {
	// Godot flips normals on back faces of double-sided geometry; the crown
	// normals already point outward, so both sides keep them.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 needles = texture(albedo_tex, UV).rgb * tint.rgb;
	// Vertex colour R darkens the inner crown and lower whorls (self-shadowing).
	ALBEDO = needles * mix(0.45, 1.0, COLOR.r);
	ALPHA = texture(opacity_tex, UV).r;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
	BACKLIGHT = transmission.rgb * COLOR.r;
	AO = mix(0.5, 1.0, COLOR.r);
}
