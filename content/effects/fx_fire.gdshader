shader_type spatial;
// Fire / fireball flipbook sprite. Premultiplied alpha so one pass both glows (hot core,
// alpha near zero) and occludes (cool soot edges, alpha up). The heat ramp is HDR.
render_mode blend_premul_alpha, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D flipbook : filter_linear, repeat_disable;
uniform int frames = 4;
uniform float soft_distance = 0.8;
uniform float intensity = 1.0;
uniform float heat_bias = 0.0;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

varying float v_frame;
varying float v_angle;
varying vec4 v_color;

void vertex() {
	v_angle = INSTANCE_CUSTOM.x;
	v_frame = INSTANCE_CUSTOM.z;
	v_color = COLOR;
	mat4 world = mat4(normalize(INV_VIEW_MATRIX[0]) * length(MODEL_MATRIX[0].xyz), normalize(INV_VIEW_MATRIX[1]) * length(MODEL_MATRIX[1].xyz), normalize(INV_VIEW_MATRIX[2]) * length(MODEL_MATRIX[2].xyz), MODEL_MATRIX[3]);
	float c = cos(v_angle);
	float s = sin(v_angle);
	world = world * mat4(vec4(c, -s, 0.0, 0.0), vec4(s, c, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * world;
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

vec4 cell(float index, vec2 uv) {
	float total = float(frames * frames);
	float i = clamp(index, 0.0, total - 1.0);
	vec2 origin = vec2(mod(i, float(frames)), floor(i / float(frames)));
	return textureLod(flipbook, (origin + clamp(uv, vec2(0.002), vec2(0.998))) / float(frames), 0.0);
}

vec3 heat_ramp(float h) {
	vec3 c = mix(vec3(0.10, 0.012, 0.004), vec3(1.0, 0.16, 0.02), smoothstep(0.0, 0.35, h));
	c = mix(c, vec3(1.0, 0.5, 0.07) * 2.2, smoothstep(0.3, 0.66, h));
	c = mix(c, vec3(1.0, 0.86, 0.5) * 4.2, smoothstep(0.62, 1.0, h));
	return c;
}

void fragment() {
	float f = clamp(v_frame, 0.0, 0.9999) * float(frames * frames);
	float f0 = floor(f);
	vec4 s = mix(cell(f0, UV), cell(f0 + 1.0, UV), fract(f));
	float heat = clamp(s.r + heat_bias, 0.0, 1.0);
	float depth = texture(depth_texture, SCREEN_UV).x;
	vec4 ndc = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -ndc.z / ndc.w;
	float fade = clamp((scene_z - (-VERTEX.z)) / max(soft_distance, 0.01), 0.0, 1.0);
	float a = s.a * v_color.a * fade;
	vec3 glow = heat_ramp(heat) * v_color.rgb * intensity;
	// Hot pixels add light; cooler, sootier ones darken what is behind them.
	float occlude = a * (1.0 - heat) * s.g * 0.85;
	ALBEDO = glow * a;
	ALPHA = clamp(occlude, 0.0, 1.0);
}
