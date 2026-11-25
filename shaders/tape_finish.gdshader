shader_type canvas_item;
// The tape finish (SPEC 9.2): scanlines, horizontal colour bleed, vignette, tape noise and a tracking
// glitch band whose frequency/intensity is driven by dread. Applied to the TextureRect that shows the
// low-res world viewport, so it samples its own TEXTURE (no screen-texture dependency).

uniform float intensity : hint_range(0.0, 1.0) = 1.0;     // Settings.retro_intensity
uniform float dread : hint_range(0.0, 1.0) = 0.0;
uniform float cam_mix : hint_range(0.0, 1.0) = 0.0;       // camcorder raised -> heavier VHS look
uniform float glitch_amount : hint_range(0.0, 1.0) = 0.0; // burst glitches (tape errors, tells)
uniform float safe_mode : hint_range(0.0, 1.0) = 0.0;     // Safe Flicker: caps glitch/pulse
uniform float reduce_motion : hint_range(0.0, 1.0) = 0.0;
uniform float fade : hint_range(0.0, 1.0) = 1.0;          // 0 black .. 1 clear
uniform float desaturate : hint_range(0.0, 1.0) = 0.0;    // low Nerve
uniform vec4 fade_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec2 src_size = vec2(640.0, 360.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	float glitch_cap = mix(1.0, 0.35, safe_mode);
	float g = clamp(glitch_amount + dread * 0.25, 0.0, 1.0) * glitch_cap;

	// tracking band: a horizontal strip that drifts and tears the picture sideways
	float band_speed = 0.07 + dread * 0.18;
	float band_y = fract(t * band_speed);
	float band_w = 0.03 + 0.07 * g;
	float in_band = smoothstep(band_w, 0.0, abs(uv.y - band_y));
	float tear = (hash21(vec2(floor(t * 24.0), floor(uv.y * 90.0))) - 0.5) * 0.045 * in_band * (0.25 + g) * intensity;
	// occasional full-frame jitter burst
	float burst = step(0.985 - g * 0.05, hash21(vec2(floor(t * 8.0), 3.7))) * g;
	tear += (hash21(vec2(floor(t * 60.0), floor(uv.y * 40.0))) - 0.5) * 0.03 * burst;
	uv.x += tear;

	vec2 px = 1.0 / src_size;
	float bleed = (0.75 + cam_mix * 0.9) * intensity;
	vec3 c;
	c.r = texture(TEXTURE, uv + vec2(px.x * bleed, 0.0)).r;
	c.g = texture(TEXTURE, uv).g;
	c.b = texture(TEXTURE, uv - vec2(px.x * bleed, 0.0)).b;
	// luma smear (horizontal low-pass)
	vec3 smear = texture(TEXTURE, uv - vec2(px.x * 1.5, 0.0)).rgb * 0.5 + texture(TEXTURE, uv + vec2(px.x * 1.5, 0.0)).rgb * 0.5;
	c = mix(c, smear, 0.18 * intensity);

	// scanlines at the screen's own resolution so they stay fine on any window size
	float sl = sin(uv.y * src_size.y * 3.14159265);
	c *= 1.0 - (0.07 + cam_mix * 0.05) * intensity * (0.5 - 0.5 * sl);

	// tape noise
	float n = hash21(vec2(floor(uv.x * src_size.x * 0.5), floor(uv.y * src_size.y * 0.5)) + floor(t * 30.0));
	c += (n - 0.5) * (0.035 + cam_mix * 0.03 + g * 0.05) * intensity;

	// vignette: tightens with dread; a slow pulse unless motion is reduced
	float pulse = (1.0 - reduce_motion) * (1.0 - safe_mode * 0.7) * 0.04 * dread * sin(t * 1.9);
	vec2 d = uv - 0.5;
	float vig = smoothstep(0.82 - dread * 0.22 - pulse, 0.18, length(d * vec2(1.0, 1.15)));
	c *= mix(1.0, 0.45 + 0.55 * vig, intensity * (0.55 + dread * 0.45));

	// colour grade: slightly crushed, slightly warm, desaturated when Nerve is low
	float luma = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(c, vec3(luma), desaturate * 0.7);
	c = mix(c, c * vec3(1.04, 1.0, 0.92), intensity * 0.5);
	c = pow(max(c, vec3(0.0)), vec3(1.0 + 0.06 * intensity));

	c = mix(fade_color.rgb, c, fade);
	COLOR = vec4(c, 1.0);
}
