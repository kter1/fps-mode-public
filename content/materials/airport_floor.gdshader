shader_type spatial;
uniform sampler2D grain_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 p = world_position.xz;
    vec2 grid = p / 1.6;
    vec2 tile = fract(grid);
    vec2 edge = min(tile, 1.0 - tile);
    // Integrate narrow grout lines over the pixel footprint. Fixed-width
    // steps and unfiltered hash noise shimmer and crawl at walking angles.
    vec2 footprint = max(fwidth(grid), vec2(0.0001));
    vec2 coverage = clamp((vec2(0.004) - edge) / footprint + 0.5, 0.0, 1.0);
    coverage *= min(vec2(1.0), vec2(0.008) / footprint);
    float grout = max(coverage.x, coverage.y);
    float grain = dot(texture(grain_tex, p / 3.0).rgb, vec3(0.299, 0.587, 0.114));
    vec3 base = vec3(0.32, 0.365, 0.39) + (grain - 0.5) * 0.045;
    ALBEDO = mix(base, base * 0.58, grout);
    ROUGHNESS = 0.57;
}
