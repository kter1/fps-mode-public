shader_type spatial;
// Kilometre-scale geology drives the view; scan detail fades with distance.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D arm_tex : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D snow_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_pos;
varying vec3 world_normal;
float hash21(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * vec3(0.1031,0.1030,0.0973));
    q += dot(q,q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}
float noise2(vec2 p) {
    vec2 cell = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(cell),hash21(cell+vec2(1,0)),f.x),mix(hash21(cell+vec2(0,1)),hash21(cell+vec2(1,1)),f.x),f.y);
}
float geology(vec2 p) {
    return noise2(p)*0.55 + noise2(p*2.07+vec2(17,31))*0.28 + noise2(p*4.13+vec2(43,11))*0.17;
}
vec3 project_scan(sampler2D tex, vec3 p, vec3 weights) {
    return texture(tex,p.yz).rgb*weights.x + texture(tex,p.xz).rgb*weights.y + texture(tex,p.xy).rgb*weights.z;
}
void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    vec3 n = normalize(world_normal);
    vec3 weights = pow(abs(n),vec3(4.0));
    weights /= max(dot(weights,vec3(1.0)),0.001);
    float macro = geology(world_pos.xz*0.008)*0.55 + geology(vec2(world_pos.x*0.015+world_pos.z*0.01,world_pos.y*0.035))*0.45;
    float deposits = geology(world_pos.xz*0.025+vec2(71,13));
    vec3 p = world_pos*0.12;
    vec3 turned = vec3(p.x*0.73+p.z*0.68,p.y,-p.x*0.68+p.z*0.73)*0.37 + vec3(17,43,29);
    vec3 scan = mix(project_scan(albedo_tex,p,weights),project_scan(albedo_tex,turned,weights),smoothstep(0.25,0.75,macro));
    float luminance = dot(scan,vec3(0.2126,0.7152,0.0722));
    float distance_fade = smoothstep(70.0,380.0,distance(CAMERA_POSITION_WORLD,world_pos));
    float detail = mix(1.0,(luminance-0.5)*0.9+1.0,mix(0.55,0.22,distance_fade));
    vec3 granite = mix(vec3(0.08,0.11,0.14),vec3(0.27,0.30,0.33),smoothstep(0.36,0.64,macro))*detail;
    // Snow settles in broad shelves and gullies; wind strips steep faces.
    float snowline = smoothstep(15.0,110.0,world_pos.y)*0.06;
    float cover = smoothstep(0.84,0.98,n.y + (deposits-0.5)*0.24 + snowline);
    vec3 snow_scan = project_scan(snow_tex,world_pos*0.32,weights);
    vec3 snow = vec3(0.82,0.88,0.93)*(0.94+deposits*0.08)*mix(vec3(1.0),snow_scan,0.13*(1.0-distance_fade));
    ALBEDO = mix(granite,snow,cover);
    vec3 nx = texture(normal_tex,p.yz).xyz*2.0-1.0;
    vec3 ny = texture(normal_tex,p.xz).xyz*2.0-1.0;
    vec3 nz = texture(normal_tex,p.xy).xyz*2.0-1.0;
    vec3 rock_normal = normalize(vec3(nx.z*sign(n.x),nx.x,nx.y)*weights.x + vec3(ny.x,ny.z*sign(n.y),ny.y)*weights.y + vec3(nz.x,nz.y,nz.z*sign(n.z))*weights.z);
    NORMAL = normalize((VIEW_MATRIX*vec4(normalize(mix(n,rock_normal,(1.0-cover)*0.36*(1.0-distance_fade))),0.0)).xyz);
    AO = mix(mix(project_scan(arm_tex,p,weights).r,0.8,distance_fade),1.0,cover);
    AO_LIGHT_AFFECT = 0.2;
    ROUGHNESS = 0.95;
    SPECULAR = 0.18;
}
