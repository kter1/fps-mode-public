shader_type spatial;
render_mode cull_disabled;
uniform sampler2D rock_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap, repeat_enable;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    vec3 surface_normal = normalize(world_normal);
    vec3 weights = pow(abs(surface_normal), vec3(4.0));
    weights /= max(dot(weights, vec3(1.0)), 0.001);
    vec3 p = world_pos * 0.045;
    vec3 rock = texture(rock_tex, p.yz).rgb * weights.x + texture(rock_tex, p.xz).rgb * weights.y + texture(rock_tex, p.xy).rgb * weights.z;
    vec3 snow = texture(snow_tex, p.yz).rgb * weights.x + texture(snow_tex, p.xz).rgb * weights.y + texture(snow_tex, p.xy).rgb * weights.z;
    float ledges = sin(world_pos.y * 0.7 + sin(world_pos.x * 0.18) * 2.0 + world_pos.z * 0.12);
    float snowline = smoothstep(20.0, 65.0, world_pos.y + ledges * 5.0);
    float accumulation = smoothstep(0.3, 0.77, surface_normal.y + snowline * 0.28);
    ALBEDO = mix(rock * vec3(0.55, 0.65, 0.74), snow * vec3(0.88, 0.94, 1.0), accumulation);
    ROUGHNESS = 0.95;
}
