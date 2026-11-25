// Shared body of the world surface shaders (see world_surface.gdshader / world_surface_2s.gdshader).
// Look: nearest-filtered 64px textures lit by a LIGHT FIELD, a small R8 texture (one texel per tile,
// bilinear) written by LightField from the ceiling light cells. This is the "fake lighting" of
// SPEC 9.3: dozens of light cells read correctly while only <= 6 real OmniLights exist.
// Real lights (camcorder lamp, light pool) add on top of it through ALBEDO.

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float emission_boost = 0.0;       // self-lit surfaces (ceiling panels that are ON)
uniform float scissor_cut = 0.0;          // > 0: alpha scissor threshold (doorways, open arches)
uniform vec2 uv_scale = vec2(1.0, 1.0);
uniform vec2 uv_scroll = vec2(0.0, 0.0);  // water
uniform float flicker_phase = 0.0;        // 0 steady; used by flickering panel material
uniform float lit_by_field = 1.0;         // props/panels that ignore the field set 0

uniform sampler2D light_map : filter_linear, repeat_disable;
uniform vec4 light_rect = vec4(0.0, 0.0, 0.0, 0.0);          // origin_x, origin_z, 1/size_x, 1/size_z (metres)
uniform vec4 light_color : source_color = vec4(1.0, 0.93, 0.74, 1.0);
uniform float ambient_floor = 0.05;
uniform float light_gain = 1.15;
uniform float dread_dim = 0.0;            // 0..1, nudged by the Director; darkens the field slightly
uniform float vertex_snap = 0.0;          // reserved: PS1 wobble (needs its own shader variant)

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 a = texture(albedo_tex, UV * uv_scale + uv_scroll * TIME);
	if (scissor_cut > 0.0 && a.a < scissor_cut) {
		discard;
	}
	vec3 base = a.rgb * tint.rgb;
	float level = 1.0;
	if (lit_by_field > 0.5) {
		vec2 luv = (wpos.xz - light_rect.xy) * light_rect.zw;
		float inside = step(0.0, luv.x) * step(luv.x, 1.0) * step(0.0, luv.y) * step(luv.y, 1.0);
		float lm = texture(light_map, clamp(luv, vec2(0.0), vec2(1.0))).r * inside;
		level = (ambient_floor + lm * light_gain) * (1.0 - dread_dim * 0.35);
	}
	ALBEDO = base;
	EMISSION = base * level * light_color.rgb + base * emission_boost;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
