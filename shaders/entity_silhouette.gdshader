shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque;
// Dithered billboard silhouettes (SPEC 6.8: flat, low-contrast, painted-pixel; no gloss; no emissive eyes).
// The shape is a signed-distance function so every staff silhouette is one cheap quad. Through the camcorder
// (cam_boost) the figure reads brighter; a lamp stun flashes it white.

uniform int shape_id = 0;                 // 0 hum, 1 foreman, 2 lifeguard in the chair, 3 queue, 4 greeter, 5 suit, 6 cart, 7 lifeguard on foot
uniform float occupied = 1.0;             // shape 2 only: 0 = the empty high chair
uniform float aspect = 0.42;              // width / height of the quad
uniform float cam_boost : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float presence : hint_range(0.0, 1.0) = 1.0;     // fades in/out (dither dissolve)
uniform vec4 body_color : source_color = vec4(0.02, 0.018, 0.015, 1.0);
uniform vec4 accent_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float crawl = 1.0;                // internal dither crawl strength
// Painted faces (queue figures + greeter): the only faces in the game (SPEC 6.8).
uniform float face_amount : hint_range(0.0, 1.0) = 0.0;  // queue: how much of the face the viewer sees (0 = back of the head)
uniform float face_side : hint_range(-1.0, 1.0) = 0.0;   // queue: which side the turned face sits on
uniform vec4 face_color : source_color = vec4(0.52, 0.47, 0.4, 1.0);
uniform float smile_seed : hint_range(-1.0, 1.0) = 0.0;  // greeter: 0 = the one fixed painted smile; else a subtly different frame

float sd_box(vec2 p, vec2 c, vec2 h) {
	vec2 d = abs(p - c) - h;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}
float sd_round(vec2 p, vec2 c, vec2 h, float r) {
	return sd_box(p, c, h - vec2(r)) - r;
}
float sd_circle(vec2 p, vec2 c, float r) {
	return length(p - c) - r;
}
float sd_seg(vec2 p, vec2 a, vec2 b, float r) {
	vec2 pa = p - a, ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h) - r;
}
float smin(float a, float b, float k) {
	float h = max(k - abs(a - b), 0.0) / k;
	return min(a, b) - h * h * k * 0.25;
}

float bayer4(vec2 fc) {
	ivec2 p = ivec2(mod(fc, 4.0));
	int idx = p.x + p.y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[idx] + 0.5) / 16.0;
}

float shape(vec2 uv) {
	// x in height units centred on 0, y up in 0..1
	vec2 p = vec2((uv.x - 0.5) * aspect, 1.0 - uv.y);
	float d = 1.0;
	if (shape_id == 0) {          // the Hum: too tall, too thin, arms to the knees, a head that is not quite a head
		float head = sd_circle(p, vec2(0.0, 0.915), 0.034);
		float neck = sd_seg(p, vec2(0.0, 0.89), vec2(0.0, 0.84), 0.011);
		float torso = sd_round(p, vec2(0.0, 0.66), vec2(0.045, 0.19), 0.03);
		float armL = sd_seg(p, vec2(-0.05, 0.82), vec2(-0.075, 0.22), 0.010);
		float armR = sd_seg(p, vec2(0.05, 0.82), vec2(0.07, 0.20), 0.010);
		float legL = sd_seg(p, vec2(-0.02, 0.47), vec2(-0.025, 0.0), 0.014);
		float legR = sd_seg(p, vec2(0.02, 0.47), vec2(0.03, 0.0), 0.014);
		d = smin(smin(head, neck, 0.02), torso, 0.03);
		d = min(d, min(min(armL, armR), min(legL, legR)));
	} else if (shape_id == 1) {   // foreman: hard hat, vest, wide shoulders
		float hat = sd_round(p, vec2(0.0, 0.925), vec2(0.045, 0.022), 0.012);
		float head = sd_circle(p, vec2(0.0, 0.895), 0.03);
		float torso = sd_round(p, vec2(0.0, 0.66), vec2(0.075, 0.2), 0.025);
		float armL = sd_seg(p, vec2(-0.075, 0.82), vec2(-0.1, 0.4), 0.018);
		float armR = sd_seg(p, vec2(0.075, 0.82), vec2(0.1, 0.34), 0.018);
		float wrench = sd_seg(p, vec2(0.1, 0.34), vec2(0.13, 0.04), 0.008);
		float legL = sd_seg(p, vec2(-0.03, 0.45), vec2(-0.035, 0.0), 0.02);
		float legR = sd_seg(p, vec2(0.03, 0.45), vec2(0.035, 0.0), 0.02);
		d = min(min(hat, head), torso);
		d = min(d, min(min(armL, armR), min(wrench, min(legL, legR))));
	} else if (shape_id == 2) {   // lifeguard in a high chair: ladder legs, a seat platform, a framed backrest
		float seat = sd_box(p, vec2(0.0, 0.50), vec2(0.085, 0.011));
		float chairL = sd_seg(p, vec2(-0.075, 0.50), vec2(-0.115, 0.0), 0.007);
		float chairR = sd_seg(p, vec2(0.075, 0.50), vec2(0.115, 0.0), 0.007);
		float brace = sd_seg(p, vec2(-0.095, 0.25), vec2(0.095, 0.25), 0.005);
		float rung = sd_seg(p, vec2(-0.085, 0.36), vec2(0.085, 0.36), 0.005);
		float frame = sd_box(p, vec2(0.0, 0.64), vec2(0.082, 0.14));
		frame = max(frame, -sd_box(p, vec2(0.0, 0.64), vec2(0.064, 0.122)));
		float chair = min(min(seat, min(chairL, chairR)), min(min(brace, rung), frame));
		float head = sd_circle(p, vec2(0.0, 0.84), 0.032);
		float neck = sd_seg(p, vec2(0.0, 0.81), vec2(0.0, 0.78), 0.012);
		float torso = sd_round(p, vec2(0.0, 0.67), vec2(0.052, 0.115), 0.02);
		float armL = sd_seg(p, vec2(-0.055, 0.76), vec2(-0.062, 0.56), 0.012);
		float armR = sd_seg(p, vec2(0.055, 0.76), vec2(0.062, 0.56), 0.012);
		float thighs = sd_round(p, vec2(0.0, 0.52), vec2(0.05, 0.016), 0.01);
		float shinL = sd_seg(p, vec2(-0.03, 0.51), vec2(-0.036, 0.33), 0.015);
		float shinR = sd_seg(p, vec2(0.03, 0.51), vec2(0.036, 0.33), 0.015);
		float body = min(smin(head, neck, 0.02), min(torso, min(min(armL, armR), min(thighs, min(shinL, shinR)))));
		d = min(chair, mix(1.0, body, step(0.5, occupied)));
	} else if (shape_id == 3 || shape_id == 5) {   // queue figure / suit: plain, slightly too straight
		float head = sd_circle(p, vec2(0.0, 0.9), 0.032);
		float torso = sd_round(p, vec2(0.0, 0.68), vec2(0.055, 0.2), 0.02);
		float armL = sd_seg(p, vec2(-0.056, 0.84), vec2(-0.058, 0.42), 0.013);
		float armR = sd_seg(p, vec2(0.056, 0.84), vec2(0.058, 0.42), 0.013);
		float legs = sd_round(p, vec2(0.0, 0.22), vec2(0.045, 0.22), 0.015);
		d = min(min(head, torso), min(min(armL, armR), legs));
		if (shape_id == 3) {
			float ticket = sd_box(p, vec2(0.06, 0.45), vec2(0.014, 0.02));
			d = min(d, ticket);
		}
	} else if (shape_id == 4) {   // greeter: bellhop cap, a painted smile that does not move
		float cap = sd_round(p, vec2(0.0, 0.93), vec2(0.04, 0.018), 0.01);
		float head = sd_circle(p, vec2(0.0, 0.895), 0.036);
		float torso = sd_round(p, vec2(0.0, 0.67), vec2(0.06, 0.2), 0.02);
		float armL = sd_seg(p, vec2(-0.06, 0.84), vec2(-0.075, 0.45), 0.014);
		float armR = sd_seg(p, vec2(0.06, 0.84), vec2(0.08, 0.5), 0.014);
		float legs = sd_round(p, vec2(0.0, 0.22), vec2(0.05, 0.22), 0.015);
		d = min(min(cap, head), min(torso, min(min(armL, armR), legs)));
	} else if (shape_id == 7) {   // lifeguard on foot: bare head, towel on the shoulders, long arms, a loose stride
		float head = sd_circle(p, vec2(0.0, 0.9), 0.032);
		float neck = sd_seg(p, vec2(0.0, 0.875), vec2(0.0, 0.84), 0.012);
		float towel = sd_round(p, vec2(0.0, 0.825), vec2(0.088, 0.02), 0.012);
		float torso = sd_round(p, vec2(0.0, 0.67), vec2(0.06, 0.19), 0.022);
		float armL = sd_seg(p, vec2(-0.075, 0.81), vec2(-0.095, 0.40), 0.014);
		float armR = sd_seg(p, vec2(0.075, 0.81), vec2(0.09, 0.38), 0.014);
		float legL = sd_seg(p, vec2(-0.03, 0.47), vec2(-0.05, 0.0), 0.018);
		float legR = sd_seg(p, vec2(0.03, 0.47), vec2(0.045, 0.0), 0.018);
		d = min(smin(head, neck, 0.02), min(torso, towel));
		d = min(d, min(min(armL, armR), min(legL, legR)));
	} else {                      // cart: a low linen trolley with a waist-down figure behind it
		float body = sd_box(p, vec2(0.0, 0.55), vec2(0.14, 0.28));
		float shelf1 = sd_box(p, vec2(0.0, 0.62), vec2(0.15, 0.008));
		float shelf2 = sd_box(p, vec2(0.0, 0.42), vec2(0.15, 0.008));
		float legs = sd_round(p, vec2(0.0, 0.14), vec2(0.06, 0.14), 0.01);
		d = min(body, legs);
		d = max(d, -min(shelf1, shelf2) + 0.004);
	}
	return d;
}

void fragment() {
	float d = shape(UV);
	float a = 1.0 - smoothstep(-0.004, 0.012, d);
	vec2 fc = FRAGCOORD.xy;
	float inner = 1.0 - crawl * 0.25 * (0.5 + 0.5 * sin(TIME * 2.3 + UV.y * 40.0 + UV.x * 9.0));
	a *= inner * presence;
	if (a < bayer4(fc) * 0.96) {
		discard;
	}
	vec3 c = body_color.rgb;
	float paint = 0.0;            // 1 where painted detail sits on the body (kept readable through the lens)
	vec2 p = vec2((UV.x - 0.5) * aspect, 1.0 - UV.y);
	if (shape_id == 3 && face_amount > 0.02) {
		// a queue figure's face: a pale oval that slides across the head as it turns toward the viewer
		vec2 fc = vec2(face_side * 0.013, 0.9);
		float fw = max(0.03 * face_amount, 0.0008);
		if (length((p - fc) / vec2(fw, 0.03)) < 1.0) {
			c = face_color.rgb;
			paint = 1.0;
		}
	} else if (shape_id == 4) {
		// the greeter: red tunic, white gloves, a pale painted face with ONE smile (smile_seed != 0 = it drifts)
		float torso = sd_round(p, vec2(0.0, 0.67), vec2(0.06, 0.2), 0.02);
		float armL = sd_seg(p, vec2(-0.06, 0.84), vec2(-0.075, 0.45), 0.014);
		float armR = sd_seg(p, vec2(0.06, 0.84), vec2(0.08, 0.5), 0.014);
		if (min(torso, min(armL, armR)) < 0.0 && p.y > 0.47) {
			c = accent_color.rgb;
			paint = 1.0;
		}
		if (min(sd_circle(p, vec2(-0.075, 0.45), 0.017), sd_circle(p, vec2(0.08, 0.5), 0.017)) < 0.0) {
			c = vec3(0.7, 0.68, 0.64);
			paint = 1.0;
		}
		vec2 hc = vec2(0.0, 0.895);
		if (length(p - hc) < 0.032) {
			c = face_color.rgb;
			paint = 1.0;
			float s = smile_seed;
			float sr = 0.021 + 0.007 * s;                              // smile radius (wider / flatter between frames)
			vec2 sc = vec2(0.004 * s, 0.9 + 0.003 * s);                // smile circle centre
			float arc = abs(length(p - sc) - sr) - 0.0032;
			if (arc < 0.0 && p.y < sc.y - 0.006) {
				c = vec3(0.1, 0.03, 0.03);
			}
			float ex = 0.0105 + 0.0025 * s;
			if (min(length(p - hc - vec2(-ex, 0.011)), length(p - hc - vec2(ex, 0.011))) < 0.0034) {
				c = vec3(0.07, 0.05, 0.04);
			}
		}
	}
	c = mix(c, vec3(0.62, 0.66, 0.6), cam_boost * (1.0 - 0.7 * paint));
	c = mix(c, vec3(1.0), flash);
	ALBEDO = c;
}
