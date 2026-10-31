shader_type spatial;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool terrain = false;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    vec3 n = normalize(world_normal);
    vec3 weights = pow(abs(n), vec3(4.0));
    weights /= max(dot(weights, vec3(1.0)), 0.001);
    vec3 p = world_pos * 0.55;
    vec3 snow = texture(albedo_tex, p.yz).rgb * weights.x + texture(albedo_tex, p.xz).rgb * weights.y + texture(albedo_tex, p.xy).rgb * weights.z;
    vec3 weather = texture(rock_tex, p.yz * 0.35).rgb * weights.x + texture(rock_tex, p.xz * 0.35).rgb * weights.y + texture(rock_tex, p.xy * 0.35).rgb * weights.z;
    float granular = dot(weather, vec3(0.3333));
    vec3 ice = mix(vec3(0.31,0.43,0.48), vec3(0.66,0.76,0.79), granular);
    float cover = terrain ? 1.0 - COLOR.r : 0.38 + 0.62 * smoothstep(0.08,0.7,n.y + (granular - 0.5) * 0.3);
    if (!terrain) cover *= 1.0 - COLOR.r * 0.65;
    ALBEDO = mix(ice, snow * vec3(0.91,0.96,1.0), cover);
    ROUGHNESS = mix(0.72,0.94,cover);
    SPECULAR = 0.22;
}
