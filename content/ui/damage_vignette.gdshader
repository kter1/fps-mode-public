shader_type canvas_item;
// Red edge vignette for taking damage: `wound` (0-1, from missing health) holds a steady
// red border that closes in as health falls; `flash` (0-1) adds a brief hit pulse.
uniform float wound = 0.0;
uniform float flash = 0.0;

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * vec2(1.0, 0.92);
	float r = length(p);
	float reach = mix(1.12, 0.6, wound);
	float edge = smoothstep(reach, reach + 0.55, r + 0.1 * flash);
	float a = clamp(edge * (0.2 + 0.58 * wound) + edge * flash * 0.45 + flash * 0.05, 0.0, 0.78);
	COLOR = vec4(mix(vec3(0.32, 0.0, 0.0), vec3(0.6, 0.03, 0.02), edge), a);
}
