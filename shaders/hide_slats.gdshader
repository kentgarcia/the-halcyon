shader_type canvas_item;
// Looking out through a wardrobe's slats: horizontal bars with gaps, dark edges.
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float slats = 14.0;
void fragment() {
	float band = fract(UV.y * slats);
	float bar = smoothstep(0.50, 0.58, band) * (1.0 - smoothstep(0.92, 1.0, band));
	float edge = smoothstep(0.30, 0.0, min(UV.x, 1.0 - UV.x)) * 0.7;
	float a = max(bar * 0.92, edge) * amount;
	COLOR = vec4(0.02, 0.015, 0.01, a);
}
