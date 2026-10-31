shader_type spatial;
// Short additive blast flash: a billboard radial glow with a hard white-hot core.
render_mode blend_add, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec3 tint = vec3(1.0, 0.72, 0.38);
uniform float intensity = 1.0;

void vertex() {
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]) * length(MODEL_MATRIX[0].xyz), normalize(INV_VIEW_MATRIX[1]) * length(MODEL_MATRIX[1].xyz), normalize(INV_VIEW_MATRIX[2]) * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float glow = pow(clamp(1.0 - r, 0.0, 1.0), 2.4);
	float core = pow(clamp(1.0 - r * 1.8, 0.0, 1.0), 2.0);
	ALBEDO = (tint * glow * 1.6 + vec3(1.0, 0.95, 0.8) * core * 3.0) * intensity;
	ALPHA = 1.0;
}
