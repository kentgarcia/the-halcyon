shader_type canvas_item;
// Nerve vignette (SPEC 3.3: no HP bar). Darkens/reddens the screen edges as Nerve drops, with a
// heartbeat pulse unless motion is reduced.
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.35, 0.0, 0.0, 1.0);

void fragment() {
	vec2 d = UV - 0.5;
	float r = length(d * vec2(1.0, 0.85));
	float edge = smoothstep(0.18, 0.78, r);
	float a = edge * (strength * 0.85 + pulse * 0.2);
	COLOR = vec4(tint.rgb, clamp(a, 0.0, 0.95));
}
