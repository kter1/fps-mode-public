shader_type spatial;
// Soft billboarded smoke / dust sprite for CPUParticles3D (flipbook, particle rotation,
// depth-faded against geometry, sun + ambient + explosion-light shaded from a baked
// sprite normal so billows read as volumes).
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform sampler2D flipbook : filter_linear, repeat_disable;
uniform int frames = 4;
uniform float soft_distance = 1.2;
uniform float edge_cut = 0.0;
uniform vec3 sun_direction = vec3(0.35, -0.8, 0.25);
uniform vec3 sun_color = vec3(1.0, 0.95, 0.88);
uniform vec3 ambient_color = vec3(0.34, 0.38, 0.45);
uniform vec3 flash_position = vec3(0.0, -1000.0, 0.0);
uniform vec3 flash_color = vec3(0.0);
uniform float flash_range = 12.0;
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

void fragment() {
	float f = clamp(v_frame, 0.0, 0.9999) * float(frames * frames);
	float f0 = floor(f);
	vec4 s = mix(cell(f0, UV), cell(f0 + 1.0, UV), fract(f));
	float alpha = clamp((s.a - edge_cut) / max(1.0 - edge_cut, 0.01), 0.0, 1.0);
	// Sprite-space normal, turned with the particle, into world space.
	vec2 nxy = (s.rg * 2.0 - 1.0);
	float nz = sqrt(max(1.0 - dot(nxy, nxy), 0.02));
	float c = cos(v_angle);
	float sn = sin(v_angle);
	vec3 nview = normalize(vec3(c * nxy.x - sn * nxy.y, sn * nxy.x + c * nxy.y, nz));
	vec3 nworld = normalize((INV_VIEW_MATRIX * vec4(nview, 0.0)).xyz);
	vec3 pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ndl = dot(nworld, -normalize(sun_direction)) * 0.5 + 0.5;
	vec3 light = ambient_color + sun_color * (ndl * ndl) * 0.9;
	vec3 to_flash = flash_position - pos;
	float d = length(to_flash);
	float reach = clamp(1.0 - d / flash_range, 0.0, 1.0);
	light += flash_color * reach * reach * (dot(nworld, to_flash / max(d, 0.01)) * 0.5 + 0.5);
	float shade = 0.82 + s.b * 0.36;
	// Soft particles: fade where the sprite plane nears solid geometry.
	float depth = texture(depth_texture, SCREEN_UV).x;
	vec4 ndc = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float scene_z = -ndc.z / ndc.w;
	float fade = clamp((scene_z - (-VERTEX.z)) / max(soft_distance, 0.01), 0.0, 1.0);
	ALBEDO = v_color.rgb * light * shade;
	ALPHA = alpha * v_color.a * fade;
}
