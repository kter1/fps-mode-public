shader_type spatial;
// Weathered hazard-red steel drum on top of the scanned Poly Haven drum textures:
// the scan's paint is recoloured red (its scratches, dents and wear stay), exposed steel
// and rust build up on rims, ribs and at random, and a FLAMMABLE plate plus a class-3
// diamond are mapped around the body from the drum's own cylinder coordinates.

uniform sampler2D albedo_map : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D arm_map : filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D dent_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D label_map : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D diamond_map : source_color, filter_linear_mipmap, repeat_disable;
uniform vec3 paint_red : source_color = vec3(0.56, 0.045, 0.03);
uniform vec3 rust_color : source_color = vec3(0.3, 0.115, 0.045);
uniform float paint_luminance = 0.22;
uniform vec4 body_box = vec4(0.0, 1.0, 0.3, 0.0); // y min, y max, radius, unused
instance uniform float label_angle = 0.0;
instance uniform float wear : hint_range(0.0, 1.0) = 0.7;

varying vec3 v_local;
varying vec3 v_local_normal;

void vertex() {
	v_local = VERTEX;
	v_local_normal = NORMAL;
}

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 7.3) * 0.3 + vnoise(p * 4.7 + 3.1) * 0.15;
}

void fragment() {
	vec4 base = texture(albedo_map, UV);
	vec3 arm = texture(arm_map, UV).rgb;
	float high = max(base.r, max(base.g, base.b));
	float low = min(base.r, min(base.g, base.b));
	float saturation = (high - low) / max(high, 0.02);
	float painted = smoothstep(0.22, 0.45, saturation);
	float luminance = dot(base.rgb, vec3(0.3, 0.59, 0.11));
	float tone = clamp(luminance / max(paint_luminance, 0.02), 0.35, 1.8);
	vec3 paint = paint_red * mix(0.8, 1.25, clamp(tone - 0.5, 0.0, 1.0));
	vec3 steel = vec3(luminance) * vec3(0.95, 0.96, 1.0) * 1.15;
	vec3 color = mix(steel, paint, painted);

	// Position on the cylinder.
	float height = max(body_box.y - body_box.x, 0.01);
	float y = (v_local.y - body_box.x) / height;
	float angle = atan(v_local.z, v_local.x);
	float side = 1.0 - smoothstep(0.35, 0.6, abs(v_local_normal.y));

	// Wear: rims and rolled ribs wear to steel first, then rust; plus slow blotches and
	// grime that streaks downwards.
	float rim = max(smoothstep(0.1, 0.0, y), smoothstep(0.9, 1.0, y));
	float ribs = max(smoothstep(0.035, 0.0, abs(y - 0.33)), smoothstep(0.035, 0.0, abs(y - 0.68))) * 0.7;
	vec2 wp = vec2(angle * 3.2, y * 5.0);
	float blotch = fbm(wp * 1.4 + 11.0);
	float streak = fbm(vec2(angle * 11.0, y * 1.4) + 3.0);
	float rust_amount = clamp((rim * 0.9 + ribs * 0.45) * (0.45 + blotch) + smoothstep(0.5, 0.78, blotch) * 0.7 * wear + (1.0 - painted) * 0.55 + smoothstep(0.7, 0.9, streak) * 0.25 * wear, 0.0, 1.0);
	rust_amount *= mix(0.65, 1.1, wear);
	vec3 rust = rust_color * (0.55 + fbm(wp * 3.1) * 0.9);
	color = mix(color, rust, rust_amount);
	// Dirt: darker lower body and a fine grime film.
	color *= mix(0.75, 1.0, smoothstep(0.0, 0.35, y)) * (0.86 + 0.14 * fbm(wp * 6.0));
	float roughness = mix(0.4, 0.88, rust_amount);
	roughness = clamp(roughness + (arm.g - 0.5) * 0.25 + (1.0 - painted) * -0.15 * (1.0 - rust_amount), 0.2, 0.95);
	float metallic = mix(mix(0.05, 0.85, 1.0 - painted), 0.0, rust_amount);

	// Signage: FLAMMABLE plate and hazard diamond, in drum-surface metres.
	float arc = (angle - label_angle) * body_box.z;
	float plate_w = height * 0.46;
	vec2 plate_uv = vec2(0.5 - arc / plate_w, (y - 0.56) / (plate_w * 0.5 / height) + 0.5);
	vec2 diamond_uv = vec2(0.5 - (arc + plate_w * 0.95) / (height * 0.24), (y - 0.56) / 0.24 + 0.5);
	vec4 plate = vec4(0.0);
	vec4 diamond = vec4(0.0);
	if (plate_uv.x > 0.0 && plate_uv.x < 1.0 && plate_uv.y > 0.0 && plate_uv.y < 1.0) {
		plate = texture(label_map, vec2(plate_uv.x, 1.0 - plate_uv.y));
	}
	if (diamond_uv.x > 0.0 && diamond_uv.x < 1.0 && diamond_uv.y > 0.0 && diamond_uv.y < 1.0) {
		diamond = texture(diamond_map, vec2(diamond_uv.x, 1.0 - diamond_uv.y));
	}
	float sign_a = max(plate.a, diamond.a) * side;
	vec3 sign_color = mix(diamond.rgb, plate.rgb, plate.a / max(plate.a + diamond.a, 0.001));
	// Scuffs and rust creep onto the signage too.
	sign_color = mix(sign_color, rust, rust_amount * 0.35);
	color = mix(color, sign_color, clamp(sign_a, 0.0, 1.0) * (1.0 - rust_amount * 0.3));
	roughness = mix(roughness, 0.55, sign_a);
	metallic = mix(metallic, 0.0, sign_a);

	vec3 n1 = texture(normal_map, UV).rgb;
	vec3 n2 = texture(dent_map, vec2(angle * 1.1, y * 1.6) * 1.6).rgb;
	ALBEDO = color;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	AO = clamp(arm.r, 0.3, 1.0);
	SPECULAR = 0.55;
	NORMAL_MAP = normalize(vec3((n1.xy - 0.5) * 2.0 + (n2.xy - 0.5) * 2.0 * 0.55 * side, 1.0)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
