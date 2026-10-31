shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    vec3 n = normalize(world_normal);
    vec3 rock = texture(albedo_tex, UV).rgb;
    vec3 snow = texture(snow_tex, world_pos.xz * 0.55).rgb;
    float cover = smoothstep(0.22, 0.73, n.y + (snow.r - 0.5) * 0.16);
    ALBEDO = mix(rock * vec3(0.78, 0.82, 0.86), snow * vec3(0.92, 0.96, 1.0), cover);
    NORMAL_MAP = mix(texture(normal_tex, UV).rgb, vec3(0.5,0.5,1.0), cover * 0.86);
    ROUGHNESS = 0.92;
    SPECULAR = 0.2;
}
