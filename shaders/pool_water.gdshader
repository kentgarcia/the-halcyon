shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
// Standing water of the Natatorium (SPEC 6.3 Tech note + Tells). Same look and the same light-field uniforms as
// the world surface shader (so MaterialLibrary keeps it lit), plus ONE honest signal: the surface itself.
//   calm   = 1  glassy: the slow drift stops (what HOLDS shows when the Lifeguard acts)
//   ripple_amp  rings of light that travel INWARD to ripple_center (the guest) at wave speed: what INVERTED shows
// The house may lie in what it says; this is what it shows.

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.82, 0.95, 1.0, 1.0);
uniform float emission_boost = 0.0;
uniform float scissor_cut = 0.0;
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_scroll = vec2(0.028, 0.017);
uniform float flicker_phase = 0.0;
uniform float lit_by_field = 1.0;

uniform sampler2D light_map : filter_linear, repeat_disable;
uniform vec4 light_rect = vec4(0.0, 0.0, 0.0, 0.0);
uniform vec4 light_color : source_color = vec4(1.0, 0.93, 0.74, 1.0);
uniform float ambient_floor = 0.05;
uniform float light_gain = 1.15;
uniform float dread_dim = 0.0;
uniform float vertex_snap = 0.0;

uniform vec3 ripple_center = vec3(0.0);
uniform float ripple_amp : hint_range(0.0, 1.0) = 0.0;
uniform float ripple_dir = 1.0;          // +1: crests travel toward ripple_center
uniform float calm : hint_range(0.0, 1.0) = 0.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = distance(wpos.xz, ripple_center.xz);
	float ring = sin(d * 7.0 + TIME * 3.4 * ripple_dir);
	float reach = smoothstep(0.9, 2.2, d) * (1.0 - smoothstep(9.0, 15.0, d));
	float crest = smoothstep(0.55, 1.0, ring) * reach * ripple_amp;
	vec2 uv = UV * uv_scale + uv_scroll * TIME * (1.0 - calm) + vec2(ring * 0.014 * ripple_amp * reach);
	vec3 base = texture(albedo_tex, uv).rgb * tint.rgb;
	float level = 1.0;
	if (lit_by_field > 0.5) {
		vec2 luv = (wpos.xz - light_rect.xy) * light_rect.zw;
		float inside = step(0.0, luv.x) * step(luv.x, 1.0) * step(0.0, luv.y) * step(luv.y, 1.0);
		float lm = texture(light_map, clamp(luv, vec2(0.0), vec2(1.0))).r * inside;
		level = (ambient_floor + lm * light_gain) * (1.0 - dread_dim * 0.35);
	}
	base = mix(base, vec3(0.78, 0.94, 0.96), crest * 0.6);
	ALBEDO = base;
	EMISSION = base * level * light_color.rgb + base * emission_boost + vec3(0.55, 0.8, 0.85) * crest * 0.18;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
